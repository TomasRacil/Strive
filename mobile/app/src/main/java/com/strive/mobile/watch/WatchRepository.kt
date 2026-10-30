package com.strive.mobile.watch

import android.content.Context
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice

/**
 * Application id of the Connect IQ app. Must match `iq:application id` in
 * garmin/watch/manifest.xml, otherwise the watch never receives the message.
 */
const val STRIVE_APP_ID = "C3D39C12C10DCB1EC9E4AEFFABF5A0B5"

data class WatchDevice(
    val id: Long,
    val name: String,
    val connected: Boolean
)

/**
 * Bridge to the Connect IQ watch app over Bluetooth.
 *
 * This is the reason the phone app is native Kotlin: the Connect IQ companion
 * SDK is a JVM library that talks to Garmin Connect Mobile over a bound service,
 * which no WebView or PWA can reach.
 */
class WatchRepository(private val context: Context) {

    private var connectIQ: ConnectIQ? = null
    private val app = IQApp(STRIVE_APP_ID)

    var sdkReady by mutableStateOf(false)
        private set
    var devices by mutableStateOf<List<WatchDevice>>(emptyList())
        private set
    var status by mutableStateOf("")
        private set
    var lastReceived by mutableStateOf<List<String>>(emptyList())
        private set

    fun initialize() {
        if (connectIQ != null) return
        Log.d(TAG, "initialize()")

        val ciq = ConnectIQ.getInstance(context, ConnectIQ.IQConnectType.WIRELESS)
        connectIQ = ciq

        runCatching {
            ciq.initialize(context, true, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    Log.d(TAG, "sdk ready")
                    sdkReady = true
                    status = ""
                    refreshDevices()
                }

                override fun onInitializeError(errorStatus: ConnectIQ.IQSdkErrorStatus) {
                    Log.e(TAG, "sdk init error: $errorStatus")
                    sdkReady = false
                    status = "Garmin Connect Mobile is not available ($errorStatus)"
                }

                override fun onSdkShutDown() {
                    Log.d(TAG, "sdk shutdown")
                    sdkReady = false
                }
            })
        }.onFailure {
            Log.e(TAG, "initialize threw", it)
            status = "Could not start the Garmin SDK: ${it.message}"
        }
    }

    fun refreshDevices() {
        val ciq = connectIQ ?: return
        runCatching {
            val known = ciq.knownDevices
            devices = known.map { it.toWatchDevice() }

            // Subscribe to connection changes so the card flips to Connected on
            // its own instead of lying until the next refresh.
            known.forEach { device ->
                runCatching {
                    ciq.registerForDeviceEvents(device, object : ConnectIQ.IQDeviceEventListener {
                        override fun onDeviceStatusChanged(
                            changed: IQDevice,
                            status: IQDevice.IQDeviceStatus
                        ) {
                            val connected = status == IQDevice.IQDeviceStatus.CONNECTED
                            devices = devices.map {
                                if (it.id == changed.deviceIdentifier) it.copy(connected = connected) else it
                            }
                        }
                    })
                }
            }
        }.onFailure {
            status = "Could not list watches: ${it.message}"
        }
    }

    private fun IQDevice.toWatchDevice() = WatchDevice(
        id = deviceIdentifier,
        name = friendlyName ?: "Garmin watch",
        connected = status == IQDevice.IQDeviceStatus.CONNECTED
    )

    /**
     * Sends the current plan to the watch app and subscribes to anything it
     * sends back. Payload is JSON so both sides stay easy to extend.
     */
    fun sendPlan(deviceId: Long, items: List<Pair<String, Double>>) {
        Log.d(TAG, "sendPlan(device=$deviceId, items=${items.size}, ciq=${connectIQ != null})")
        val ciq = connectIQ ?: return
        val device = runCatching {
            ciq.knownDevices.firstOrNull { it.deviceIdentifier == deviceId }
        }.getOrNull()
        Log.d(TAG, "device=${device?.friendlyName} status=${device?.status}")

        if (device == null) {
            status = "That watch is no longer known to Garmin Connect."
            return
        }

        // Gate on the live status from the device-event listener, not on the
        // snapshot inside IQDevice: the snapshot goes stale and disagrees with
        // what the card is showing.
        val connectedNow = devices.firstOrNull { it.id == deviceId }?.connected ?: false
        Log.d(TAG, "connectedNow=$connectedNow")
        if (!connectedNow) {
            status = "The watch is not connected. Wake it, keep it near the phone, " +
                "and open Garmin Connect Mobile, then tap Find watches again."
            return
        }

        // A Map is delivered to the watch as a Dictionary. A JSON string would
        // arrive as a plain string and the watch could not read it.
        val payload: Map<String, Any> = mapOf(
            "type" to "plan",
            "items" to items.map { (exerciseId, weightKg) ->
                mapOf<String, Any>("id" to exerciseId, "weight" to weightKg)
            }
        )

        runCatching {
            Log.d(TAG, "registering app events for ${app.applicationId}")
            ciq.registerForAppEvents(device, app, object : ConnectIQ.IQApplicationEventListener {
                override fun onMessageReceived(
                    from: IQDevice,
                    app: IQApp,
                    messages: List<Any>,
                    messageStatus: ConnectIQ.IQMessageStatus
                ) {
                    Log.d(TAG, "message received: $messages ($messageStatus)")
                    lastReceived = messages.map { it.toString() }
                }
            })

            Log.d(TAG, "sending payload: $payload")
            ciq.sendMessage(device, app, payload, object : ConnectIQ.IQSendMessageListener {
                override fun onMessageStatus(
                    to: IQDevice,
                    app: IQApp,
                    messageStatus: ConnectIQ.IQMessageStatus
                ) {
                    Log.d(TAG, "send status: $messageStatus")
                    status = "Plan sent: $messageStatus"
                }
            })
        }.onFailure {
            Log.e(TAG, "send threw", it)
            status = "Sending failed: ${it.message}"
        }
    }

    private companion object {
        const val TAG = "StriveWatch"
    }
}
