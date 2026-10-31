using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Timer as Timer;
using Toybox.Lang;

class StriveApp extends App.AppBase {

    var view;

    // Outbound queue, owned by an instance: Monkey C cannot take a method
    // reference from a static function, so the pacing timer needs an object.
    static var outbox = new Outbox();

    static function enqueue(text) as Void {
        outbox.enqueue(text);
    }

    static function onSent() as Void {
        outbox.onSent();
    }

    // Hands the finished session's log to the outbox. One message, queued and
    // paced: the bus drops bursts silently, and a lost log is a lost workout.
    static function syncLog(text) as Void {
        outbox.enqueue(text);
    }

    function initialize() {
        AppBase.initialize();
        view = null;
    }

    function getInitialView() {
        view = new StriveView();
        return [ view, new StriveDelegate(view) ];
    }

    function onStart(state) {
        Comm.registerForPhoneAppMessages(method(:onPhoneAppMessage));
        probeNetwork();
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
            var text = data;

            // Size probe: "L<declared>:<payload>". The watch reports what actually
            // arrived against what was declared, so truncation is visible instead
            // of being mistaken for a parse failure.
            if (text.find("L") == 0) {
                var parts = Text.split(text, ":");
                if (parts.size() == 2) {
                    var declared = parts[0].substring(1, parts[0].length());
                    App.Storage.setValue(
                        "ble_dbg",
                        "rx " + parts[1].length().toString() + "/" + declared
                    );
                }
            } else {
                App.Storage.setValue(
                    "ble_dbg",
                    "msg " + (text.length() > 12 ? text.substring(0, 12) : text)
                );
            }

            Plan.replaceFromText(data);
        } else if (data instanceof Lang.Dictionary) {
            App.Storage.setValue("ble_dbg", "msg dict");
            Plan.replaceFromDictionary(data);
        } else {
            return;
        }

        if (view != null) {
            // A plan can change the load on screen, so the view re-reads it
            // rather than waiting for the next launch.
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

    // Both outcomes release the outbox: a failed send must not stop the queue,
    // and success is the signal that the next message may go.
    function onComplete() as Void {
        StriveApp.onSent();
    }

    function onError() as Void {
        StriveApp.onSent();
    }

    function onResponse(responseCode as Lang.Number, data) as Void {
    }
}
