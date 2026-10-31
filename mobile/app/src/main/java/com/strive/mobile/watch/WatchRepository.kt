package com.strive.mobile.watch

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import com.strive.mobile.BuildConfig
import com.strive.mobile.data.Session
import com.strive.mobile.data.StriveStore
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
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Which watch the framed bus is talking to. Set by the action that knows. */
    private var busDeviceId: Long? = null

    /** Where a session finished on the watch is written. Same file the UI reads. */
    private val store = StriveStore(context)

    /**
     * Names for the exercise ids the watch sends. Read once: the library changes
     * only when the user edits it, and a set should not re-parse it.
     */
    private val exerciseNames: Map<String, String> by lazy {
        store.loadExercises().orEmpty().associate { it.id to it.name }
    }

    /**
     * The payload-to-history mapping. It holds the live sessions, so it must be
     * the same instance for the lifetime of the repository.
     */
    private val inbox = WatchInbox(nameOf = { id -> exerciseNames[id] ?: id })

    /** The snapshots last built for the watch, kept so `ready` can re-send them. */
    private var lastPlan: JSONObject? = null
    private var lastRec: JSONObject? = null
    private var lastHistory: JSONObject? = null
    private var lastPlanVersion: Long = 0

    /**
     * The framed protocol. Everything the phone sends goes through here, and
     * everything the watch sends arrives here: the legacy delimited string is
     * gone, so a plan and its weights travel as `plan` and `rec` messages that
     * are chunked, acknowledged and retried.
     */
    private val bus = WatchBus(
        transport = object : WatchTransport {
            override fun send(text: String) {
                transmit(text)
            }
        },
        log = { Log.d(TAG, "bus: $it") }
    )

    private val busTicker = object : Runnable {
        override fun run() {
            // Retries and the 400 ms gap are both driven from here; the bus
            // itself has no thread of its own.
            runCatching { bus.tick() }
            mainHandler.postDelayed(this, 100)
        }
    }

    init {
        // The bus frames, chunks and acknowledges; what an applied message means
        // for history is this class's job. Without this assignment every `start`,
        // `set`, `end` and `ready` from the watch is acked and then dropped.
        bus.onMessage = ::applyFromWatch
    }

    /**
     * Called with a session the watch finished, once it is in the store. The
     * activity uses it to refresh the in-memory history the screens read, which
     * the store write alone would leave stale until the next launch.
     */
    var onSessionSaved: ((Session) -> Unit)? = null

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
        if (connectIQ != null) {
            // Already initialised: the SDK is ready by now, so refreshing here is
            // safe. This is what a second tap on "Find watches" does.
            refreshDevices()
            return
        }
        Log.d(TAG, "initialize()")

        // TETHERED makes the SDK listen on 7381 for the Connect IQ simulator,
        // which is what `adb forward tcp:7381 tcp:7381` forwards to. WIRELESS is
        // the real path through Garmin Connect Mobile, so it stays the default.
        val mode = if (BuildConfig.CIQ_TETHERED) {
            ConnectIQ.IQConnectType.TETHERED
        } else {
            ConnectIQ.IQConnectType.WIRELESS
        }
        Log.d(TAG, "connect type: $mode")

        val ciq = ConnectIQ.getInstance(context, mode)
        connectIQ = ciq

        runCatching {
            ciq.initialize(context, true, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    Log.d(TAG, "sdk ready")
                    sdkReady = true
                    status = ""

                    // The bus needs a heartbeat whether or not a watch is in
                    // range: a queued set must keep retrying across a reconnect.
                    mainHandler.removeCallbacks(busTicker)
                    mainHandler.postDelayed(busTicker, 100)

                    // In TETHERED mode the ADB strategy answers no SDK call until
                    // the simulator actually connects: there is no device list to
                    // fetch yet, and getApplicationInfo throws
                    // InvalidStateException. So wait for the connection instead of
                    // polling a channel that has nothing on the other end.
                    if (BuildConfig.CIQ_TETHERED) {
                        status = "Waiting for the simulator — Connection > Start in the Connect IQ simulator"
                        return
                    }

                    // The strategy marks itself initialised only after this
                    // callback returns, so a direct call here is too early; one
                    // main-loop tick later it is ready.
                    mainHandler.post { refreshDevices() }
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
        // initialize() is asynchronous, so a caller that fires straight after it
        // would otherwise hit the SDK before it is ready and get
        // InvalidStateException: "SDK not initialized".
        if (!sdkReady) return
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
            // The same listener the send path registers: one object, one place
            // where a frame reaches the bus, so the two registrations cannot
            // drift apart.
            ciq.registerForAppEvents(device, app, watchMessages())
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
     * Sends the workout to run now: a `plan` message for the shape of the
     * session and a `rec` message carrying the phone's suggested load, because
     * the plan payload deliberately has no weight in it.
     *
     * Both go through the framed bus, so they are chunked, paced, retried and
     * acknowledged like everything else.
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

        // Combined registration: device and app listeners together. The separate
        // registerForAppEvents call does not appear to bind the app mailbox that
        // sendMessage delivers into.
        runCatching {
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
                watchMessages()
            )
        }.onFailure {
            Log.e(TAG, "could not register for events", it)
        }

        busDeviceId = deviceId

        val plan = planPayload(items)
        val rec = recommendationPayload(items)
        val history = historyPayload()

        // Remembered so a `ready` from a watch that lost them can be answered
        // without the user sending the plan again.
        lastPlan = plan
        lastRec = rec
        lastHistory = history
        lastPlanVersion = plan.optLong("v")

        val planId = bus.sendSnapshot("plan", plan)
        val recId = bus.sendSnapshot("rec", rec)
        bus.sendSnapshot("hist", history)
        bus.tick()

        status = if (planId == null || recId == null) {
            "The plan is too large for the message bus."
        } else {
            "Plan queued for the watch (${items.size} exercises)"
        }
    }

    /**
     * `plan` carries the shape of the session, not the load: sets and rep ranges
     * per exercise. Rep targets fall back to the double-progression default of
     * three sets of six to eight until the phone's workout model is wired in.
     */
    private fun planPayload(items: List<Pair<String, Double>>): JSONObject {
        val rows = JSONArray()
        items.forEach { (id, _) ->
            rows.put(
                JSONObject()
                    .put("ex", id)
                    .put("sets", 3)
                    .put("lo", 6)
                    .put("hi", 8)
                    .put("rest", 120)
                    .put("ss", 0)
            )
        }

        return JSONObject()
            .put("v", System.currentTimeMillis() / 1000)
            .put("wid", "phone-" + System.currentTimeMillis() / 1000)
            .put("name", "Today")
            .put("items", rows)
    }

    /** The phone-computed load. This is the message that actually sets a weight. */
    private fun recommendationPayload(items: List<Pair<String, Double>>): JSONObject {
        val rows = JSONArray()
        items.forEach { (id, kg) ->
            rows.put(
                JSONObject()
                    .put("ex", id)
                    .put("w", kg)
                    .put("reps", 8)
                    .put("sets", 3)
                    .put("why", "double progression")
            )
        }

        return JSONObject()
            .put("at", System.currentTimeMillis() / 1000)
            .put("items", rows)
    }

    /**
     * The last three sets of each exercise, which is all the watch's offline
     * recommendation reads.
     *
     * Up to forty exercises keeps the body inside the bus limit; the bus refuses
     * an oversized body rather than truncating it, and a watch with no history
     * only loses its offline suggestion, so dropping the tail is the cheap half
     * of that trade. `ageDays` is in the protocol's units, not milliseconds.
     */
    private fun historyPayload(): JSONObject {
        val now = System.currentTimeMillis()
        val byExercise = store.loadSessions()
            .flatMap { it.sets }
            .groupBy { it.exerciseId }

        val rows = JSONObject()
        byExercise.entries
            .sortedByDescending { (_, sets) -> sets.maxOf { it.timestamp } }
            .take(40)
            .forEach { (id, sets) ->
                val recent = JSONArray()
                sets.sortedByDescending { it.timestamp }.take(3).forEach { set ->
                    recent.put(
                        JSONArray()
                            .put(set.weightKg)
                            .put(set.reps)
                            .put(set.rir ?: -1)
                            .put(((now - set.timestamp) / 86_400_000L).coerceAtLeast(0))
                    )
                }
                rows.put(id, recent)
            }

        return JSONObject().put("ex", rows)
    }

    /** Every registration of watch messages goes through the framed bus. */
    private fun watchMessages() = object : ConnectIQ.IQApplicationEventListener {
        override fun onMessageReceived(
            from: IQDevice,
            app: IQApp,
            messages: List<Any>,
            messageStatus: ConnectIQ.IQMessageStatus
        ) {
            Log.d(TAG, "message received: $messages ($messageStatus)")
            lastReceived = messages.map { it.toString() }
            messages.forEach { message ->
                if (message is String) bus.onIncoming(message)
            }
        }
    }

    // ---- messages from the watch -----------------------------------------

    /**
     * Everything the watch sends that is not an ack or a retry lands here, one
     * applied message at a time. The inbox decides what it means; this method
     * only carries out the two things it can ask for: write a session to history,
     * or re-send a snapshot the watch is behind on.
     */
    private fun applyFromWatch(kind: String, payload: JSONObject?) {
        val effect = runCatching { inbox.apply(kind, payload, heldSnapshots()) }
            .onFailure { Log.e(TAG, "could not apply $kind", it) }
            .getOrNull() ?: return

        when (effect) {
            is WatchInbox.Effect.Save -> save(effect.session)
            is WatchInbox.Effect.Resend -> effect.kinds.forEach { resendSnapshot(it) }
        }
    }

    /**
     * Writes a finished watch session into history, upserting by id.
     *
     * The guard against a replayed `end` is the store, not the inbox: a message
     * re-delivered after the app was killed finds its row already there, which an
     * in-memory set of ended sids would not.
     */
    private fun save(session: Session) {
        val all = store.loadSessions()
        val existing = all.firstOrNull { it.id == session.id }
        if (existing == session) return

        val merged = if (existing == null) {
            all + session
        } else {
            all.map { if (it.id == session.id) session else it }
        }

        store.saveSessions(merged.sortedByDescending { it.startedAt })
        onSessionSaved?.invoke(session)
        // Tonnage the way the rest of the app counts it: body mass is priced in
        // for bodyweight movements, so a calisthenics session is not "0 kg".
        val volume = session.volumeKg(
            store.loadExercises().orEmpty(),
            store.loadSettings().bodyKg
        )
        status = "Session from the watch: ${session.sets.size} sets, " +
            "${volume.toInt()} kg"
    }

    /**
     * What the phone holds, in the versions `ready` reports. The library snapshot
     * is not built yet, so its version stays at zero and a `lib` re-send is never
     * asked for.
     */
    private fun heldSnapshots() = WatchInbox.Held(
        libVersion = 0,
        planVersion = lastPlanVersion,
        hasHistory = lastHistory != null
    )

    /** Re-sends one snapshot the watch said it is behind on. */
    private fun resendSnapshot(kind: String) {
        val payload = when (kind) {
            "plan" -> lastPlan
            "rec" -> lastRec
            "hist" -> lastHistory
            else -> null
        } ?: return

        bus.sendSnapshot(kind, payload)
        Log.d(TAG, "re-sent $kind after ready")
    }

    /**
     * One chunk on its way to the watch. Garmin's own sample only ever sends
     * Strings over sendMessage, which is exactly what the envelope is.
     */
    private fun transmit(text: String) {
        val ciq = connectIQ ?: return
        val deviceId = busDeviceId ?: return
        val device = runCatching {
            ciq.knownDevices.firstOrNull { it.deviceIdentifier == deviceId }
        }.getOrNull() ?: return

        runCatching {
            ciq.sendMessage(device, app, text, object : ConnectIQ.IQSendMessageListener {
                override fun onMessageStatus(
                    to: IQDevice,
                    app: IQApp,
                    messageStatus: ConnectIQ.IQMessageStatus
                ) {
                    // Not delivery: only an `A|` from the watch is that. This is
                    // logged because a rejection here is a different fault from a
                    // message the watch never acked.
                    Log.d(TAG, "send status: $messageStatus")
                }
            })
        }.onFailure {
            Log.e(TAG, "send threw", it)
        }
    }

    /** Announces the phone and lets the bus re-send whatever it holds. */
    fun sendHello(deviceId: Long) {
        busDeviceId = deviceId
        bus.send("hello", JSONObject().put("pv", 1).put("app", "strive"))
        bus.tick()
    }


    /**
     * Sends a plain string to the watch app, with no plan semantics. Used to
     * prove the channel on its own: if the watch shows this text, delivery works
     * and anything that fails afterwards is parsing, not transport.
     */
    fun sendText(deviceId: Long, text: String) {
        val ciq = connectIQ ?: return
        val device = runCatching {
            ciq.knownDevices.firstOrNull { it.deviceIdentifier == deviceId }
        }.getOrNull()

        if (device == null) {
            status = "That watch is no longer known to Garmin Connect."
            return
        }

        runCatching {
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
                watchMessages()
            )

            Log.d(TAG, "sending text: $text")
            ciq.sendMessage(device, app, text, object : ConnectIQ.IQSendMessageListener {
                override fun onMessageStatus(
                    to: IQDevice,
                    app: IQApp,
                    messageStatus: ConnectIQ.IQMessageStatus
                ) {
                    Log.d(TAG, "send status: $messageStatus")
                    status = "Test message: $messageStatus"
                }
            })
        }.onFailure {
            Log.e(TAG, "sendText threw", it)
            status = "Sending failed: ${it.message}"
        }
    }

    /**
     * Size probe. Sends "L<declared>:<payload>" so the watch can report the length
     * it actually received against the length that was sent. That distinguishes
     * truncation from a parse failure without any parsing being involved.
     */
    fun sendSizeTest(deviceId: Long, size: Int) {
        val body = "x".repeat(size)
        sendText(deviceId, "L${size}:$body")
    }

    private companion object {
        const val TAG = "StriveWatch"
    }
}
