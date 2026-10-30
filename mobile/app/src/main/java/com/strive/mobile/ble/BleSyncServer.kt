package com.strive.mobile.ble

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import java.util.UUID

/**
 * Peripheral side of the direct BLE link.
 *
 * Garmin's companion message bus is broken (CIQQA-4631) and the Connect IQ SDK
 * has no peripheral mode, so the direction is fixed: the watch is the central
 * and this app is the peripheral. It runs a GATT server plus an advertiser,
 * with no bonding and no encryption, so the watch connects without a pairing
 * prompt.
 *
 * Probe only: the watch reads PLAN and writes LOG. Nothing here touches the
 * plan data model.
 */
class BleSyncServer private constructor(private val context: Context) {

    var isAdvertising by mutableStateOf(false)
        private set
    var connectedDeviceCount by mutableStateOf(0)
        private set
    var lastLogValue by mutableStateOf("")
        private set
    var statusText by mutableStateOf("BLE sync is off")
        private set

    private var server: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null

    /** UTF-8 JSON served on PLAN. Replaced later by the real plan payload. */
    private var planValue: String = DEFAULT_PLAN

    private val connected = linkedSetOf<String>()
    private val notificationsOn = linkedSetOf<String>()

    // ---- lifecycle -------------------------------------------------------

    fun start() {
        if (server != null || isAdvertising) {
            Log.d(TAG, "start() ignored: already running")
            return
        }

        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter: BluetoothAdapter? = manager?.adapter
        Log.d(TAG, "start(): adapter=${adapter?.name} enabled=${adapter?.isEnabled}")

        if (adapter == null) {
            statusText = "This phone has no Bluetooth adapter."
            Log.e(TAG, "no Bluetooth adapter")
            return
        }
        if (!adapter.isEnabled) {
            statusText = "Bluetooth is off. Turn it on, then start BLE sync."
            Log.e(TAG, "adapter disabled")
            return
        }

        val missing = missingPermissions(context)
        if (missing.isNotEmpty()) {
            statusText = "Bluetooth permission missing: ${missing.joinToString(", ")}"
            Log.e(TAG, "missing permissions: $missing")
            return
        }

        // A GATT server with no service is useless, so build the service first
        // and only then open the server.
        val service = buildService()

        val gattServer = try {
            manager.openGattServer(context, serverCallback)
        } catch (t: Throwable) {
            Log.e(TAG, "openGattServer failed", t)
            statusText = "Could not open the GATT server: ${t.message}"
            null
        }

        if (gattServer == null) {
            if (statusText == "BLE sync is off") statusText = "Could not open the GATT server."
            return
        }

        val added = gattServer.addService(service)
        Log.d(TAG, "addService=${added} uuid=${SERVICE_UUID}")
        if (!added) {
            gattServer.close()
            statusText = "Could not register the GATT service."
            return
        }
        server = gattServer

        startAdvertising(adapter)
    }

    fun stop() {
        Log.d(TAG, "stop()")
        runCatching { advertiser?.stopAdvertising(advertiseCallback) }
        advertiseCallback = null
        isAdvertising = false

        runCatching { server?.clearServices() }
        runCatching { server?.close() }
        server = null

        connected.clear()
        notificationsOn.clear()
        connectedDeviceCount = 0
        statusText = "BLE sync is off"
    }

    /** Lets the UI report a denied permission without touching internal state. */
    fun reportPermissionDenied() {
        statusText = "Bluetooth permission denied — allow Nearby devices and try again."
        Log.e(TAG, "permission denied by the user")
    }

    /** Serves a new payload on the next PLAN read. */
    fun setPlan(json: String) {
        planValue = json
        Log.d(TAG, "plan value set (${json.length} chars)")
    }

    // ---- advertising -----------------------------------------------------

    private fun startAdvertising(adapter: BluetoothAdapter) {
        val leAdvertiser = adapter.bluetoothLeAdvertiser
        if (leAdvertiser == null) {
            statusText = "This phone cannot advertise over BLE."
            Log.e(TAG, "no BluetoothLeAdvertiser")
            return
        }
        advertiser = leAdvertiser

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .setTimeout(0)
            .build()

        // The service UUID is what the watch filters on, so it goes in the
        // advertisement. The name and a literal "Strive" tag go in the scan
        // response: the adapter name alone is the phone's own Bluetooth name.
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .build()

        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addManufacturerData(MANUFACTURER_ID, DEVICE_NAME.toByteArray(Charsets.UTF_8))
            .build()

        startAdvertisingWith(settings, data, scanResponse)
    }

    private fun startAdvertisingWith(
        settings: AdvertiseSettings,
        data: AdvertiseData,
        scanResponse: AdvertiseData
    ) {
        val leAdvertiser = advertiser ?: return

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                isAdvertising = true
                statusText = if (connected.isEmpty()) {
                    "Advertising as $DEVICE_NAME — waiting for the watch"
                } else {
                    "Advertising — ${connected.size} device connected"
                }
                Log.d(TAG, "advertising started: mode=${settingsInEffect.mode} tx=${settingsInEffect.txPowerLevel}")
            }

            override fun onStartFailure(errorCode: Int) {
                isAdvertising = false
                Log.e(TAG, "advertising failed: $errorCode (${advertiseErrorName(errorCode)})")

                // A long phone Bluetooth name can push the scan response past
                // the 31-byte legacy limit. Retry once with the name dropped
                // rather than leaving the user with a dead button.
                if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE) {
                    Log.w(TAG, "scan response too large, retrying with the UUID only")
                    val bare = AdvertiseData.Builder().build()
                    startAdvertisingWith(settings, data, bare)
                    return
                }

                statusText = "Advertising failed: ${advertiseErrorName(errorCode)}"
            }
        }

        advertiseCallback = callback
        try {
            leAdvertiser.startAdvertising(settings, data, scanResponse, callback)
            Log.d(TAG, "startAdvertising() called")
        } catch (t: Throwable) {
            isAdvertising = false
            statusText = "Could not start advertising: ${t.message}"
            Log.e(TAG, "startAdvertising threw", t)
        }
    }

    // ---- GATT service ----------------------------------------------------

    private fun buildService(): BluetoothGattService {
        // Plain READ / WRITE permissions, no encryption or authentication bits:
        // the watch connects and exchanges values with no pairing prompt.
        val plan = BluetoothGattCharacteristic(
            PLAN_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        val log = BluetoothGattCharacteristic(
            LOG_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        log.addDescriptor(
            BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
        )

        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(plan)
        service.addCharacteristic(log)
        return service
    }

    private val serverCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            val address = device.address
            Log.d(TAG, "onConnectionStateChange $address status=$status state=${stateName(newState)}")

            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connected.add(address)
                connectedDeviceCount = connected.size
                statusText = "Watch connected ($address)"
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connected.remove(address)
                notificationsOn.remove(address)
                connectedDeviceCount = connected.size
                statusText = if (isAdvertising) {
                    "Advertising as $DEVICE_NAME — waiting for the watch"
                } else {
                    "BLE sync is off"
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            Log.d(
                TAG,
                "onCharacteristicReadRequest ${device.address} offset=$offset uuid=${characteristic.uuid}"
            )

            val full = when (characteristic.uuid) {
                PLAN_CHAR_UUID -> planValue.toByteArray(Charsets.UTF_8)
                else -> ByteArray(0)
            }

            val slice = if (offset >= full.size) ByteArray(0) else full.copyOfRange(offset, full.size)
            val sent = server?.sendResponse(
                device,
                requestId,
                BluetoothGatt.GATT_SUCCESS,
                offset,
                slice
            ) ?: false

            Log.d(TAG, "read response sent=$sent bytes=${slice.size} body=${String(slice, Charsets.UTF_8)}")
            if (sent) statusText = "Plan read by ${device.address}"
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            val text = value?.toString(Charsets.UTF_8) ?: ""
            Log.d(
                TAG,
                "onCharacteristicWriteRequest ${device.address} uuid=${characteristic.uuid} " +
                    "offset=$offset prepared=$preparedWrite responseNeeded=$responseNeeded value=$text"
            )

            if (characteristic.uuid == LOG_CHAR_UUID) {
                lastLogValue = text
                statusText = "Watch wrote: $text"
            }

            if (responseNeeded) {
                val sent = server?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    null
                ) ?: false
                Log.d(TAG, "write response sent=$sent")
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            Log.d(
                TAG,
                "onDescriptorWriteRequest ${device.address} uuid=${descriptor.uuid} value=${value?.toHex()}"
            )

            if (descriptor.uuid == CCCD_UUID) {
                val enabled = value != null &&
                    value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                if (enabled) notificationsOn.add(device.address) else notificationsOn.remove(device.address)
                Log.d(
                    TAG,
                    "notifications ${if (enabled) "enabled" else "disabled"} for ${device.address} " +
                        "(total=${notificationsOn.size})"
                )
            }

            if (responseNeeded) {
                val sent = server?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    null
                ) ?: false
                Log.d(TAG, "descriptor write response sent=$sent")
            }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor
        ) {
            Log.d(TAG, "onDescriptorReadRequest ${device.address} uuid=${descriptor.uuid}")

            val value = if (descriptor.uuid == CCCD_UUID) {
                if (device.address in notificationsOn) {
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                } else {
                    BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                }
            } else {
                ByteArray(0)
            }

            val sent = server?.sendResponse(
                device,
                requestId,
                BluetoothGatt.GATT_SUCCESS,
                offset,
                value
            ) ?: false
            Log.d(TAG, "descriptor read response sent=$sent")
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            Log.d(TAG, "onNotificationSent ${device.address} status=$status")
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            Log.d(TAG, "onMtuChanged ${device.address} mtu=$mtu")
        }
    }

    companion object {
        private const val TAG = "BleSyncServer"

        /** Must match garmin/watch/source/BleClient.mc character for character. */
        val SERVICE_UUID: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        val PLAN_CHAR_UUID: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        val LOG_CHAR_UUID: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val DEVICE_NAME = "Strive"
        private const val MANUFACTURER_ID = 0xFFFF
        private const val DEFAULT_PLAN = "{\"bench_press\":100.0}"

        /**
         * One server for the whole process. The settings card lives inside a
         * `when(tab)`, so a plain `remember` would drop the object on every tab
         * switch while the GATT server kept running.
         */
        @Volatile
        private var shared: BleSyncServer? = null

        fun get(context: Context): BleSyncServer =
            shared ?: synchronized(this) {
                shared ?: BleSyncServer(context.applicationContext).also { shared = it }
            }

        /** Runtime grants this probe needs, per API level. */
        fun requiredPermissions(): Array<String> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                arrayOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_ADVERTISE
                )
            } else {
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }

        fun missingPermissions(context: Context): List<String> =
            requiredPermissions().filter {
                ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
            }

        private fun advertiseErrorName(code: Int): String = when (code) {
            1 -> "data too large"
            2 -> "too many advertisers"
            3 -> "already started"
            4 -> "internal error"
            5 -> "feature unsupported"
            else -> "code $code"
        }

        private fun stateName(state: Int): String = when (state) {
            BluetoothProfile.STATE_CONNECTED -> "CONNECTED"
            BluetoothProfile.STATE_DISCONNECTED -> "DISCONNECTED"
            BluetoothProfile.STATE_CONNECTING -> "CONNECTING"
            BluetoothProfile.STATE_DISCONNECTING -> "DISCONNECTING"
            else -> "state $state"
        }

        private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
    }
}
