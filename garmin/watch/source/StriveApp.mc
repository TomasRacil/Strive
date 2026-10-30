using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Lang;

class StriveApp extends App.AppBase {

    var view;
    static var ble;

    // Connect IQ may only honour a scan request once the view is actually on
    // screen, so the view calls back here from onShow rather than relying on
    // onStart alone.
    static function resumeBle() as Void {
        if (ble != null) {
            ble.start();
        }
    }

    function initialize() {
        AppBase.initialize();
        view = null;
        ble = null;
    }

    function getInitialView() {
        view = new StriveView();
        // The BLE client needs the view so it can trigger a redraw when a
        // connection or a read lands while the screen is idle.
        ble = new BleClient(view);
        return [ view, new StriveDelegate(view) ];
    }

    function onStart(state) {
        Comm.registerForPhoneAppMessages(method(:onPhoneAppMessage));
        // Proves the channel in the other direction: if the phone logs this, the
        // watch can reach it and only sendMessage is at fault.
        sendToPhone("hello-from-watch");
        probeNetwork();
        // The real transport: central-role BLE straight to the phone app.
        if (ble != null) {
            ble.start();
        }
    }

    // Decisive experiment for sync. Garmin Connect's companion message bus is
    // broken (CIQQA-4631), but a plain HTTPS request goes through a different
    // Garmin service. A status code here means the watch can reach a server and
    // we have a working channel that does not depend on that bus.
    // Two hosts are probed because a 4xx from one says nothing about the other.
    function probeNetwork() {
        request("https://httpbin.org/status/200", :onProbeA);
        request("https://postman-echo.com/status/200", :onProbeB);
    }

    function request(url, callback) {
        var options = {
            :method => Comm.HTTP_REQUEST_METHOD_GET,
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
        };
        Comm.makeWebRequest(url, null, options, method(callback));
    }

    function onProbeA(responseCode as Lang.Number, data as Lang.String or Null) as Void {
        App.Storage.setValue("net_a", responseCode);
        if (view != null) {
            Ui.requestUpdate();
        }
    }

    function onProbeB(responseCode as Lang.Number, data as Lang.String or Null) as Void {
        App.Storage.setValue("net_b", responseCode);
        if (view != null) {
            Ui.requestUpdate();
        }
    }

    function sendToPhone(text) {
        Comm.transmit(text, null, new PhoneListener());
    }

    // The phone sends a delimited string of exercise id -> weight. A Dictionary
    // is also handled in case the transport ever delivers one.
    function onPhoneAppMessage(msg as Comm.PhoneAppMessage) as Void {
        // Receipt counter, shown on screen. It separates "the message never
        // arrived" from "it arrived and the parsing is wrong".
        var count = App.Storage.getValue("msg_count");
        if (count == null) {
            count = 0;
        }
        App.Storage.setValue("msg_count", count + 1);

        var data = msg.data;
        if (data == null) {
            return;
        }

        if (data instanceof Lang.String) {
            Plan.replaceFromText(data);
        } else if (data instanceof Lang.Dictionary) {
            Plan.replaceFromDictionary(data);
        } else {
            return;
        }

        if (view != null) {
            view.reloadFromPlan();
            Ui.requestUpdate();
        }
    }
}

// transmit() needs a real listener class; Monkey C has no anonymous objects.
class PhoneListener extends Comm.ConnectionListener {

    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
    }

    function onError() as Void {
    }

    function onResponse(responseCode as Lang.Number, data) as Void {
    }
}
