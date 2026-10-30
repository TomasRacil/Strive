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

    /** "installed" / "not_installed" / "unknown" — reported by the watch itself. */
    var appStatus by mutableStateOf<String?>(null)
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
            val previous = devices.associateBy { it.id }
            devices = known.map { it.toWatchDevice(previous[it.deviceIdentifier]) }

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

        // Ask the watch whether our Connect IQ app is actually on it. Sending to
        // a watch without the app produces no callback at all, so this is the
        // difference between "broken" and "nothing to deliver to".
        val first = devices.firstOrNull() ?: return
        val device = runCatching {
            ciq.knownDevices.firstOrNull { it.deviceIdentifier == first.id }
        }.getOrNull() ?: return

        runCatching {
            ciq.registerForAppEvents(device, app, object : ConnectIQ.IQApplicationEventListener {
                override fun onMessageReceived(
                    from: IQDevice,
                    app: IQApp,
                    messages: List<Any>,
                    messageStatus: ConnectIQ.IQMessageStatus
                ) {
                    Log.d(TAG, "message FROM WATCH: $messages ($messageStatus)")
                    lastReceived = messages.map { it.toString() }
                }
            })
        }.onFailure {
            Log.e(TAG, "could not register for app events", it)
        }

        runCatching {
            ciq.getApplicationInfo(
                STRIVE_APP_ID,
                device,
                object : ConnectIQ.IQApplicationInfoListener {
                    override fun onApplicationInfoReceived(app: IQApp) {
                        Log.d(TAG, "watch has the app: ${app.displayName} (${app.status})")
                        appStatus = "installed"
                    }

                    override fun onApplicationNotInstalled(applicationId: String) {
                        Log.d(TAG, "watch does NOT have the app: $applicationId")
                        appStatus = "not_installed"
                    }
                }
            )
        }.onFailure {
            Log.e(TAG, "getApplicationInfo threw", it)
        }
    }

    /**
     * Asks the watch to open the Strive app. Doubles as the only honest test of
     * whether the phone-to-watch channel works at all: the SDK reports a status
     * either way, unlike sendMessage which can go quiet.
     */
    fun openOnWatch(deviceId: Long) {
        val ciq = connectIQ ?: return
        val device = runCatching {
            ciq.knownDevices.firstOrNull { it.deviceIdentifier == deviceId }
        }.getOrNull()

        if (device == null) {
            status = "That watch is no longer known to Garmin Connect."
            return
        }

        runCatching {
            ciq.openApplication(device, app, object : ConnectIQ.IQOpenApplicationListener {
                override fun onOpenApplicationResponse(
                    target: IQDevice,
                    application: IQApp,
                    openStatus: ConnectIQ.IQOpenApplicationStatus
                ) {
                    Log.d(TAG, "openApplication: $openStatus")
                    status = "Open on watch: $openStatus"
                }
            })
        }.onFailure {
            Log.e(TAG, "openApplication threw", it)
            status = "Could not open the app: ${it.message}"
        }
    }

    /**
     * IQDevice carries a snapshot of the status, and that snapshot is frequently
     * UNKNOWN even while the device is connected. Only a definitive answer from
     * the snapshot is trusted; otherwise whatever the event listener last told
     * us wins, so refreshing does not flip a connected watch to "not connected".
     */
    private fun IQDevice.toWatchDevice(previous: WatchDevice?) = WatchDevice(
        id = deviceIdentifier,
        name = friendlyName ?: previous?.name ?: "Garmin watch",
        connected = when (status) {
            IQDevice.IQDeviceStatus.CONNECTED -> true
            IQDevice.IQDeviceStatus.NOT_CONNECTED,
            IQDevice.IQDeviceStatus.NOT_PAIRED -> false
            else -> previous?.connected ?: false
        }
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

        // Garmin's own sample only ever sends Strings, Booleans and Integers over
        // sendMessage; a Map is silently dropped. So the plan travels as
        // "id=weight;id=weight".
        val payload: String = items.joinToString(";") { (id, kg) -> "$id=$kg" }

        runCatching {
            Log.d(TAG, "registering events for ${app.applicationId}")
            // Combined registration: device and app listeners together. The
            // separate registerForAppEvents call does not appear to bind the
            // app mailbox that sendMessage delivers into.
            ciq.registerForEvents(
                device,
                object : ConnectIQ.IQDeviceEventListener {
                    override fun onDeviceStatusChanged(
                        changed: IQDevice,
                        status: IQDevice.IQDeviceStatus
                    ) {
                        Log.d(TAG, "device status: $status")
                    }
                },
                app,
                object : ConnectIQ.IQApplicationEventListener {
                    override fun onMessageReceived(
                        from: IQDevice,
                        app: IQApp,
                        messages: List<Any>,
                        messageStatus: ConnectIQ.IQMessageStatus
                    ) {
                        Log.d(TAG, "message received: $messages ($messageStatus)")
                        lastReceived = messages.map { it.toString() }
                    }
                }
            )

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
