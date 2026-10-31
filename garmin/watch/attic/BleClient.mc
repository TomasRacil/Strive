using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Application as App;
using Toybox.Lang;
using Toybox.Timer as Timer;
using Toybox.WatchUi as Ui;

// Central-role BLE client: the watch connects out to the phone, which runs a
// GATT server and advertises. The direction is forced: the Connect IQ SDK has
// no peripheral mode at all (no advertising, no GATT server), so the phone has
// to be the peripheral. This path also avoids Garmin's companion message bus,
// which accepts transmit() and never delivers (CIQQA-4631).
//
// Probe only: scan, connect, read PLAN, write a fixed payload back to LOG.
// `status` is a single short string; the view draws it above the probe line.
class BleClient extends Ble.BleDelegate {

    // Scan window, following Garmin's own pattern in connectiq-apps
    // (BluetoothMeshBarrel/source/Network/MeshDelegate.mc, startScanning):
    //
    //     Ble.setScanState(SCAN_STATE_SCANNING);
    //     timer.start(method(:timerDone), 5000, false);   // one bounded window
    //
    // One setScanState call opens a window, a one-shot timer bounds it, and the
    // radio is closed again before any later window may open. The previous
    // version re-armed from a repeating 8 s timer that called setScanState
    // unconditionally, so it asked the platform to start scanning while a scan
    // was already running. That is the one thing the sample never does.
    const SCAN_WINDOW_MS = 5000;
    const SCAN_PAUSE_MS = 2000;

    // A matched device is not connected from inside onScanResults: the platform
    // is re-entered from a short timer instead, the same way MeshDelegate pairs
    // from timerDone rather than from its own scan callback.
    const PAIR_DELAY_MS = 250;

    // The platform reports a failed attempt as a disconnect, but a silent
    // failure would leave `connecting` true forever with the radio off, which
    // looks exactly like a dead scan. This bounds the attempt.
    const CONNECT_TIMEOUT_MS = 10000;

    // How often the pairing handle is asked whether the service is readable yet.
    // The platform gives no callback for "already connected", so this is the only
    // way to notice.
    const PROBE_INTERVAL_MS = 700;

    // requestWrite() throws InvalidRequestException above 20 bytes and the SDK
    // implements no long writes, so an outgoing log is chunked at 20 bytes and
    // streamed one acked write at a time.
    const WRITE_MAX = 20;

    var view;
    var status;
    var serviceUuid;
    var planUuid;
    var logUuid;
    var logChar;
    var device;
    var candidate;
    var attempt;
    var scanning;
    var connecting;
    var prepared;
    var bondsCleared;
    var windowTimer;
    var pauseTimer;
    var pairTimer;
    var connectTimer;
    var probeTimer;
    var probeTries;
    var outQueue;
    var outIndex;
    var writing;

    function initialize(v) {
        BleDelegate.initialize();

        view = v;
        status = "init";
        logChar = null;
        device = null;
        scanning = false;
        connecting = false;
        prepared = false;
        bondsCleared = false;
        windowTimer = null;
        pauseTimer = null;
        pairTimer = null;
        connectTimer = null;
        probeTimer = null;
        probeTries = 0;
        candidate = null;
        attempt = null;
        outQueue = null;
        outIndex = 0;
        writing = false;
        serviceUuid = null;
        planUuid = null;
        logUuid = null;

        // These strings must match the Android side character for character.
        try {
            serviceUuid = Ble.stringToUuid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");
            planUuid = Ble.stringToUuid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
            logUuid = Ble.stringToUuid("6e400003-b5a3-f393-e0a9-e50e24dcca9e");
        } catch (e) {
            setStatus("uuid err");
        }
    }

    // A single place to change the status string, so the view and the stored
    // copy can never disagree about what the last event was.
    function setStatus(text) {
        status = text;
        App.Storage.setValue("ble_status", text);
        Ui.requestUpdate();
    }

    // Safe to call any number of times. onStart and the view's onShow both call
    // it, and a second call must not register a second profile or open a second
    // scan window.
    function start() {
        if (serviceUuid == null) {
            setStatus("no uuid");
            return;
        }

        if (!prepared) {
            prepare();
        }

        // The watch may already hold a connection to the phone from a previous
        // run: pairDevice leaves a bond behind, and the system reconnects to it.
        // In that case no CONNECTED event is ever delivered to this app
        // instance, so scanning would find the phone, pair it a second time
        // (which is the "unknown device" prompt on the wrist) and sit there
        // while the link it already has goes unused.
        if (adoptExisting()) {
            return;
        }

        // A bond left behind by a previous run is actively harmful: the system
        // reconnects to the phone on its own the moment the phone's server
        // exists, the app never sees a connection it did not create, and
        // pairDevice then hands back a handle that never becomes usable. Drop
        // those bonds once per run so the next pairing is a real one.
        clearStaleBonds();

        if (connecting) {
            // A suspend() during a connection attempt stops the watchdog.
            // Restart it so the attempt stays bounded across a view change
            // instead of leaving `connecting` true with no timer to clear it.
            startConnectTimer();
            return;
        }

        if (device != null) {
            return;
        }

        openWindow();
    }

    // Adopts a link that already exists at the system level. A device that
    // answers getService() for our UUID is connected and has our GATT profile
    // in place, which is exactly the state the app wants - without a rescan and
    // without a second pairing prompt.
    function adoptExisting() as Lang.Boolean {
        if (device != null) {
            return true;
        }

        var paired = null;
        try {
            paired = Ble.getPairedDevices();
        } catch (e) {
            return false;
        }
        if (paired == null) {
            return false;
        }

        var entry = paired.next();
        while (entry != null) {
            var dev = entry as Ble.Device;
            var service = null;
            try {
                service = dev.getService(serviceUuid);
            } catch (e) {
                service = null;
            }

            if (service != null) {
                device = dev;
                connecting = false;
                stopTimers();
                closeWindow();
                setStatus("conn");
                openService();
                return true;
            }

            entry = paired.next();
        }

        return false;
    }

    // Unpairs everything the app has a bond for, once. Not repeated on every
    // start: after this run creates a good bond, the next launch should adopt it
    // through adoptExisting(), not throw it away.
    function clearStaleBonds() as Void {
        if (bondsCleared) {
            return;
        }
        bondsCleared = true;

        var paired = null;
        try {
            paired = Ble.getPairedDevices();
        } catch (e) {
            return;
        }
        if (paired == null) {
            return;
        }

        var entry = paired.next();
        while (entry != null) {
            var dev = entry as Ble.Device;
            try {
                Ble.unpairDevice(dev);
            } catch (e) {
                // Already gone; nothing to do.
            }
            entry = paired.next();
        }
    }

    // Delegate and profile are registered once per app run. registerProfile has
    // a hard limit of three profiles for the whole application, so repeating it
    // on every onShow would eventually fail and take getService() down with it.
    function prepare() {
        prepared = true;

        Ble.setDelegate(self);

        // GATT operations only see services and characteristics that were
        // registered up front. Without this, device.getService() always
        // returns null even when the phone is advertising.
        var profile = {
            :uuid => serviceUuid,
            :characteristics => [
                { :uuid => planUuid },
                { :uuid => logUuid }
            ]
        };

        try {
            Ble.registerProfile(profile);
        } catch (e) {
            setStatus("prof err");
            // A failed registration makes getService() return null forever on a
            // live link, and the status line gets overwritten by the next scan
            // event, so the failure is recorded where the view can always show it.
            App.Storage.setValue("ble_prof", "err");
        }

        // The counters answer "does the radio see anything at all in this run".
        // A value carried over from a previous launch answers a different
        // question, so they start at zero.
        App.Storage.setValue("ble_n", 0);
        App.Storage.setValue("ble_m", 0);
        App.Storage.setValue("ble_conn", 0);
        App.Storage.setValue("ble_prof", "?");
    }

    // ---- bounded scan window ---------------------------------------------

    // Opens one window. The guard is the point: setScanState is only ever
    // reached from a state where no scan is running.
    function openWindow() {
        if (scanning || connecting || device != null) {
            return;
        }

        scanning = true;
        // A silent failure here would look exactly like "sees nothing", so the
        // exception text is surfaced instead of swallowed.
        try {
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
            setStatus("scan");
        } catch (e) {
            scanning = false;
            setStatus("scan err " + e.getErrorMessage());
        }

        startWindowTimer();
    }

    function startWindowTimer() {
        if (windowTimer == null) {
            windowTimer = new Timer.Timer();
        }
        windowTimer.start(method(:onWindowEnd), SCAN_WINDOW_MS, false);
    }

    // End of the window: close the radio, then wait before the next one. The
    // first scan usually runs before the phone is advertising, so one window is
    // not enough — but the retry has to start from the closed state.
    function onWindowEnd() {
        if (device != null || connecting) {
            return;
        }
        closeWindow();
        scheduleNextWindow();
    }

    function closeWindow() {
        if (!scanning) {
            return;
        }
        scanning = false;
        try {
            Ble.setScanState(Ble.SCAN_STATE_OFF);
        } catch (e) {
            setStatus("off err");
        }
    }

    function scheduleNextWindow() {
        if (pauseTimer == null) {
            pauseTimer = new Timer.Timer();
        }
        pauseTimer.start(method(:onPauseEnd), SCAN_PAUSE_MS, false);
    }

    function onPauseEnd() {
        openWindow();
    }

    function stopTimers() {
        if (windowTimer != null) {
            windowTimer.stop();
        }
        if (pauseTimer != null) {
            pauseTimer.stop();
        }
        if (pairTimer != null) {
            pairTimer.stop();
        }
        if (connectTimer != null) {
            connectTimer.stop();
        }
        if (probeTimer != null) {
            probeTimer.stop();
        }
    }

    // Called when the view goes away. The platform stops scanning in the
    // background anyway, so the window is torn down here rather than leaving a
    // timer to fire against a radio the app no longer owns.
    function suspend() {
        stopTimers();
        candidate = null;
        closeWindow();
    }

    // Advertisements arrive in batches. Count everything seen, not just matches:
    // "the watch sees no devices at all" and "it sees devices but none carry our
    // service UUID" are completely different problems and need different fixes.
    function onScanResults(scanResults) as Void {
        if (scanResults == null) {
            return;
        }

        var seen = 0;
        var matched = 0;
        var result = scanResults.next();
        while (result != null) {
            var scanResult = result as Ble.ScanResult;
            seen += 1;
            if (advertisesService(scanResult)) {
                matched += 1;
                if (!connecting && device == null && candidate == null) {
                    // Remember the device and leave the rest of the window to
                    // the timer: pairing and closing the scan from inside this
                    // callback would re-enter the platform while it is still
                    // delivering results.
                    candidate = scanResult;
                    setStatus("found");
                    startPairTimer();
                }
            }
            result = scanResults.next();
        }

        bump("ble_n", seen);
        bump("ble_m", matched);
        if (view != null) {
            Ui.requestUpdate();
        }
    }

    function startPairTimer() {
        if (pairTimer == null) {
            pairTimer = new Timer.Timer();
        }
        pairTimer.start(method(:onPairReady), PAIR_DELAY_MS, false);
    }

    // Runs outside the scan callback: close the window first, then let the
    // platform take the device over. The scan is never left running underneath
    // a connection attempt.
    function onPairReady() {
        if (candidate == null || device != null || connecting) {
            return;
        }
        var scanResult = candidate;
        candidate = null;
        stopTimers();
        closeWindow();
        pair(scanResult);
    }

    function pair(scanResult) {
        connecting = true;
        setStatus("found");

        try {
            var paired = Ble.pairDevice(scanResult);
            // pairDevice returns null when the system refuses the device.
            // Without this the client would sit at "found" forever with the
            // radio off, which reads exactly like a failed scan.
            if (paired == null) {
                connecting = false;
                setStatus("pair null");
                scheduleNextWindow();
                return;
            }
            attempt = paired;
            probeTries = 0;
            // The platform reports state *changes*, so a link that is already up
            // produces no CONNECTED event and this would wait forever. Asking
            // the returned device for our service is the direct question.
            probe();
            startProbeTimer();
            startConnectTimer();
        } catch (e) {
            connecting = false;
            setStatus("pair err");
            scheduleNextWindow();
        }
    }

    // Polls the pairing handle until the service answers. getService() returns
    // null while the link is still being established and a service once the GATT
    // profile is readable, so this doubles as the connected check.
    function probe() as Void {
        if (device != null || attempt == null) {
            return;
        }

        var service = null;
        try {
            service = attempt.getService(serviceUuid);
        } catch (e) {
            service = null;
        }

        if (service != null) {
            device = attempt;
            attempt = null;
            connecting = false;
            stopTimers();
            closeWindow();
            setStatus("conn");
            openService();
        }
    }

    function startProbeTimer() {
        if (probeTimer == null) {
            probeTimer = new Timer.Timer();
        }
        probeTimer.start(method(:onProbeTick), PROBE_INTERVAL_MS, true);
    }

    function onProbeTick() {
        if (device != null || attempt == null) {
            return;
        }
        probeTries += 1;
        probe();
    }

    function startConnectTimer() {
        if (connectTimer == null) {
            connectTimer = new Timer.Timer();
        }
        connectTimer.start(method(:onConnectTimeout), CONNECT_TIMEOUT_MS, false);
    }

    // No CONNECTED arrived in time. Release the half-open pair so the device
    // slot is not leaked, and go back to scanning from a closed radio.
    function onConnectTimeout() {
        if (device != null || !connecting) {
            return;
        }
        connecting = false;
        stopTimers();
        setStatus("conn t/o");
        if (attempt != null) {
            try {
                Ble.unpairDevice(attempt);
            } catch (e) {
                setStatus("unpair err");
            }
            attempt = null;
        }
        scheduleNextWindow();
    }

    function bump(key, amount) {
        var current = App.Storage.getValue(key);
        if (current == null) {
            current = 0;
        }
        App.Storage.setValue(key, current + amount);
    }

    function advertisesService(result as Ble.ScanResult) as Lang.Boolean {
        var uuids = result.getServiceUuids();
        if (uuids == null) {
            return false;
        }
        var uuid = uuids.next();
        while (uuid != null) {
            if (uuid.equals(serviceUuid)) {
                return true;
            }
            uuid = uuids.next();
        }
        return false;
    }

    // ---- connection ------------------------------------------------------

    function onConnectedStateChanged(dev, state) as Void {
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            // Counted so the screen can distinguish "the delegate never heard
            // about the connection" from "it heard and the service lookup failed".
            var seen = App.Storage.getValue("ble_conn");
            if (seen == null) {
                seen = 0;
            }
            App.Storage.setValue("ble_conn", seen + 1);

            device = dev;
            connecting = false;
            candidate = null;
            attempt = null;
            stopTimers();
            closeWindow();
            setStatus("conn");
            openService();
            return;
        }

        // Disconnected or rejected: either way there is no link, so drop
        // everything and start looking again from a closed radio. The state
        // number stays in the status because "the phone refused us" and "the
        // phone went out of range" need different fixes.
        device = null;
        logChar = null;
        connecting = false;
        candidate = null;
        attempt = null;
        setStatus("disc " + state.toString());
        scheduleNextWindow();
    }

    function openService() as Void {
        if (device == null) {
            return;
        }

        var service = device.getService(serviceUuid);
        if (service == null) {
            setStatus("no svc");
            return;
        }
        setStatus("svc");

        var planChar = null;
        var characteristics = service.getCharacteristics();
        var characteristic = characteristics.next();
        while (characteristic != null) {
            var uuid = characteristic.getUuid();
            if (uuid.equals(planUuid)) {
                planChar = characteristic;
            } else if (uuid.equals(logUuid)) {
                logChar = characteristic;
            }
            characteristic = characteristics.next();
        }

        if (planChar == null) {
            setStatus("no plan");
            return;
        }

        planChar.requestRead();
    }

    // Reading PLAN proves phone -> watch. The payload is a small JSON object of
    // exercise id -> weight, which is what the phone serves today; anything
    // larger than one ATT MTU cannot arrive this way, because the SDK has no
    // long reads.
    function onCharacteristicRead(characteristic, readStatus, value) as Void {
        if (readStatus != Ble.STATUS_SUCCESS || value == null) {
            setStatus("rd err " + readStatus.toString());
            return;
        }

        // Handle both shapes: the delegate is documented to hand back a ByteArray,
        // but a String would silently produce an unparseable plan through the byte
        // path, so the type is checked instead of assumed.
        var text = "";
        if (value instanceof Lang.ByteArray) {
            text = Text.fromBytes(value);
        } else {
            text = value.toString();
        }

        // Decode is proven (the preview read back as {"bench_), so this line now
        // reports the parse stages instead: byte count, then
        // <pairs>/<fields in first pair>/<cleaned id>.
        App.Storage.setValue("ble_dbg", text.length().toString() + " " + Plan.parseDebug(text));

        App.Storage.setValue("ble_plan", text);
        var parsed = Plan.replaceFromJson(text);
        // "rd ok" only ever meant "the read returned"; the count is what says the
        // payload actually parsed into plan entries.
        setStatus(parsed > 0 ? "rd ok" : "rd empty");

        // The screen seeded its load at startup, so a plan that arrives later has
        // to be pushed into the view explicitly or the read is invisible.
        if (view != null) {
            view.reloadFromPlan();
            Ui.requestUpdate();
        }
    }

    // Streams a finished session's log to the phone: 20 bytes at a time, one
    // write in flight, each acked before the next is requested. A zero-length
    // write closes the stream, so the phone can tell a finished log from one
    // that stopped mid-way even when the length is a multiple of 20.
    function sendLog(text) as Void {
        if (logChar == null) {
            setStatus("no log");
            return;
        }

        var bytes = text.toUtf8Array();
        var queue = [] as Lang.Array<Lang.ByteArray>;
        var offset = 0;
        while (offset < bytes.size()) {
            var end = offset + WRITE_MAX;
            if (end > bytes.size()) {
                end = bytes.size();
            }
            queue.add(bytes.slice(offset, end));
            offset = end;
        }
        queue.add([]b);

        outQueue = queue;
        outIndex = 0;
        writing = false;
        writeNext();
    }

    function writeNext() as Void {
        if (writing || outQueue == null || outIndex >= outQueue.size()) {
            return;
        }
        writing = true;
        var chunk = outQueue[outIndex];
        try {
            logChar.requestWrite(chunk, { :writeType => Ble.WRITE_TYPE_WITH_RESPONSE });
        } catch (e) {
            writing = false;
            outQueue = null;
            setStatus("wr req err");
        }
    }

    // Advances the outgoing log stream. A failed chunk abandons the rest rather
    // than sending a log with a hole in it.
    function onCharacteristicWrite(characteristic, writeStatus) as Void {
        if (outQueue == null) {
            if (writeStatus == Ble.STATUS_SUCCESS) {
                setStatus("wr ok");
            } else {
                setStatus("wr err " + writeStatus.toString());
            }
            return;
        }

        if (writeStatus != Ble.STATUS_SUCCESS) {
            writing = false;
            outQueue = null;
            setStatus("wr err " + writeStatus.toString());
            return;
        }

        writing = false;
        outIndex += 1;
        if (outIndex >= outQueue.size()) {
            outQueue = null;
            setStatus("synced");
            return;
        }
        writeNext();
    }

    // Not used by the probe, but every BleDelegate callback is implemented so
    // a stray event can never land on an unimplemented base method.
    function onCharacteristicChanged(characteristic, value) as Void {
        setStatus("notif");
    }

    function onDescriptorRead(descriptor, readStatus, value) as Void {
        if (readStatus == Ble.STATUS_SUCCESS) {
            setStatus("dsc rd");
        } else {
            setStatus("dsc err");
        }
    }

    function onDescriptorWrite(descriptor, writeStatus) as Void {
        if (writeStatus == Ble.STATUS_SUCCESS) {
            setStatus("dsc wr");
        } else {
            setStatus("dsc err");
        }
    }

    function onEncryptionStatus(dev, encStatus) as Void {
        if (encStatus == Ble.STATUS_SUCCESS) {
            setStatus("enc");
        } else {
            setStatus("enc err");
        }
    }

    function onProfileRegister(uuid, registerStatus) as Void {
        if (registerStatus == Ble.STATUS_SUCCESS) {
            // The profile is in place, which is what makes getService() work
            // once a connection lands.
            App.Storage.setValue("ble_prof", "ok");
        } else {
            setStatus("prof err " + registerStatus.toString());
        }
    }

    // The platform is the authority on whether a scan is still running: it stops
    // scanning on its own, so this callback is what clears the flag. It never
    // sets it, because only openWindow starts a scan, and a stale "SCANNING"
    // report would otherwise leave the flag stuck true with no window timer to
    // clear it — and a stuck flag blocks every future window.
    function onScanStateChange(scanState, scanStatus) as Void {
        if (scanStatus != Ble.STATUS_SUCCESS) {
            scanning = false;
            setStatus("scan err " + scanStatus.toString());
            return;
        }

        if (scanState == Ble.SCAN_STATE_OFF) {
            scanning = false;
        }
    }
}
