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

    var view;
    var status;
    var serviceUuid;
    var planUuid;
    var logUuid;
    var logChar;
    var device;
    var scanning;
    var connecting;
    var rescanTimer;

    function initialize(v) {
        BleDelegate.initialize();

        view = v;
        status = "init";
        logChar = null;
        device = null;
        scanning = false;
        connecting = false;
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

    function start() {
        if (serviceUuid == null) {
            setStatus("no uuid");
            return;
        }

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
        }

        beginScan();
        startRescan();
    }

    // The platform stops scanning when the app loses foreground or the scan
    // window lapses, and the first scan usually runs before the phone is
    // advertising. Without this the client scans once, misses, and sits at 0/0
    // forever no matter what the phone does afterwards.
    function startRescan() {
        if (rescanTimer == null) {
            rescanTimer = new Timer.Timer();
        }
        rescanTimer.start(method(:onRescan), 8000, true);
    }

    function onRescan() as Void {
        if (device == null && !connecting) {
            beginScan();
        }
    }

    function beginScan() {
        scanning = true;
        setStatus("scan");
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
    }

    function stopScan() {
        if (!scanning) {
            return;
        }
        scanning = false;
        Ble.setScanState(Ble.SCAN_STATE_OFF);
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
                if (!connecting && device == null) {
                    stopScan();
                    connecting = true;
                    setStatus("found");
                    try {
                        Ble.pairDevice(scanResult);
                    } catch (e) {
                        connecting = false;
                        setStatus("pair err");
                    }
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

    function onConnectedStateChanged(dev, state) as Void {
        if (state == Ble.CONNECTION_STATE_CONNECTED) {
            device = dev;
            connecting = false;
            setStatus("conn");
            openService();
        } else if (state == Ble.CONNECTION_STATE_DISCONNECTED) {
            device = null;
            logChar = null;
            connecting = false;
            setStatus("disc");
        } else {
            setStatus("st " + state.toString());
        }
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

    // Reading PLAN proves phone -> watch. Writing LOG right after proves the
    // other direction on the same connection, so one run tests both.
    function onCharacteristicRead(characteristic, readStatus, value) as Void {
        if (readStatus != Ble.STATUS_SUCCESS || value == null) {
            setStatus("rd err " + readStatus.toString());
            return;
        }

        var text = value.toString();
        App.Storage.setValue("ble_plan", text);
        setStatus("rd ok");

        writeLog();
    }

    function writeLog() as Void {
        if (logChar == null) {
            setStatus("no log");
            return;
        }

        var payload = "{\"probe\":1}";
        try {
            logChar.requestWrite(payload.toUtf8Array(), {
                :writeType => Ble.WRITE_TYPE_WITH_RESPONSE
            });
        } catch (e) {
            setStatus("wr req err");
        }
    }

    function onCharacteristicWrite(characteristic, writeStatus) as Void {
        if (writeStatus == Ble.STATUS_SUCCESS) {
            setStatus("wr ok");
        } else {
            setStatus("wr err " + writeStatus.toString());
        }
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
            // Scanning is already running; this only records that the profile
            // is in place, which is what makes getService() work later.
            App.Storage.setValue("ble_prof", "ok");
        } else {
            setStatus("prof err " + registerStatus.toString());
        }
    }

    function onScanStateChange(scanState, scanStatus) as Void {
        if (scanStatus != Ble.STATUS_SUCCESS) {
            setStatus("scan err " + scanStatus.toString());
        }
    }
}
