package com.strive.mobile.watch

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import org.json.JSONArray
import org.json.JSONObject

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

        val ciq = ConnectIQ.getInstance(context, ConnectIQ.IQConnectType.WIRELESS)
        connectIQ = ciq

        runCatching {
            ciq.initialize(context, true, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    sdkReady = true
                    status = ""
                    refreshDevices()
                }

                override fun onInitializeError(errorStatus: ConnectIQ.IQSdkErrorStatus) {
                    sdkReady = false
                    status = "Garmin Connect Mobile is not available ($errorStatus)"
                }

                override fun onSdkShutDown() {
                    sdkReady = false
                }
            })
        }.onFailure {
            status = "Could not start the Garmin SDK: ${it.message}"
        }
    }

    fun refreshDevices() {
        val ciq = connectIQ ?: return
        runCatching {
            devices = ciq.knownDevices.map { device ->
                WatchDevice(
                    id = device.deviceIdentifier,
                    name = device.friendlyName ?: "Garmin watch",
                    connected = device.status == IQDevice.IQDeviceStatus.CONNECTED
                )
            }
        }.onFailure {
            status = "Could not list watches: ${it.message}"
        }
    }

    /**
     * Sends the current plan to the watch app and subscribes to anything it
     * sends back. Payload is JSON so both sides stay easy to extend.
     */
    fun sendPlan(deviceId: Long, items: List<Pair<String, Double>>) {
        val ciq = connectIQ ?: return
        val device = runCatching {
            ciq.knownDevices.firstOrNull { it.deviceIdentifier == deviceId }
        }.getOrNull()

        if (device == null) {
            status = "That watch is no longer known to Garmin Connect."
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
            ciq.registerForAppEvents(device, app, object : ConnectIQ.IQApplicationEventListener {
                override fun onMessageReceived(
                    from: IQDevice,
                    app: IQApp,
                    messages: List<Any>,
                    messageStatus: ConnectIQ.IQMessageStatus
                ) {
                    lastReceived = messages.map { it.toString() }
                }
            })

            ciq.sendMessage(device, app, payload.toString(), object : ConnectIQ.IQSendMessageListener {
                override fun onMessageStatus(
                    to: IQDevice,
                    app: IQApp,
                    messageStatus: ConnectIQ.IQMessageStatus
                ) {
                    status = "Plan sent: $messageStatus"
                }
            })
        }.onFailure {
            status = "Sending failed: ${it.message}"
        }
    }
}
