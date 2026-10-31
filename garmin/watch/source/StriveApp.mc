using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Lang;

// Entry point. Everything that crosses to the phone goes through Bus, and
// everything Bus emits goes through the persistent outbox, so nothing here has
// to know how the transport behaves.
class StriveApp extends App.AppBase {

    var view;

    // Outbound queue, owned by an instance: Monkey C cannot take a method
    // reference from a static function, so the pacing timer needs an object.
    static var outbox = new Outbox();

    static function enqueue(id, body) as Void {
        outbox.add(id, body);
    }

    // Acks and rejections, which are sent once and never persisted.
    static function enqueueRaw(text) as Void {
        outbox.addRaw(text);
    }

    static function acked(id) as Void {
        outbox.acked(id);
    }

    static function onSent() as Void {
        outbox.onSent();
    }

    // Called from onShow: a screen the user opened is the best evidence the
    // phone may be back, and a queue that only drained at launch would hold a
    // workout until the next reboot.
    static function drain() as Void {
        outbox.pump();
    }

    // Hands the finished session to the bus. One message, queued and acked: a
    // lost log is a lost workout, so it is never sent and forgotten.
    static function syncLog(logText) as Void {
        Bus.sendEnd(logText);
    }

    static function syncStart() as Void {
        Bus.sendStart();
    }

    static function syncSet() as Void {
        Bus.sendSet(Session.setCount() - 1);
    }

    function initialize() {
        AppBase.initialize();
        view = null;
    }

    function getInitialView() {
        view = new StriveView();
        return [ view, new StriveDelegate(view) ];
    }

    // The bus is the only transport: the HTTP probes that used to fire here were
    // an experiment from before the companion message bus was proven, and they
    // cost two requests per launch.
    function onStart(state) {
        Comm.registerForPhoneAppMessages(method(:onPhoneAppMessage));

        // Anything half-arrived before the app died is either finished by the
        // next chunk or expired; either way it must not sit in Storage for ever.
        Bus.expirePartials();

        // The queue is drained on start, not when the user opens a screen: a
        // session logged offline yesterday goes out as soon as the app is up.
        outbox.load();
        Bus.sendReady();
    }

    // The phone's whole side of the protocol arrives here as one raw string.
    // Parsing, chunking, dedupe and acking all happen in Bus; this only reports
    // what was applied so the screen can redraw.
    function onPhoneAppMessage(msg as Comm.PhoneAppMessage) as Void {
        // Receipt counter, shown on screen. It separates "the message never
        // arrived" from "it arrived and the parsing is wrong".
        var count = App.Storage.getValue("msg_count");
        if (count == null) {
            count = 0;
        }
        App.Storage.setValue("msg_count", count + 1);

        var data = msg.data;
        if (!(data instanceof Lang.String)) {
            return;
        }

        var applied = Bus.receive(data);
        if (applied == null) {
            return;
        }

        // A plan, a library or a recommendation can change the load on screen,
        // so the view re-reads it rather than waiting for the next launch.
        if (view != null) {
            if (Text.same(applied, "plan") || Text.same(applied, "lib") || Text.same(applied, "rec")) {
                view.reloadFromPlan();
            }
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
    // and the gap to the next message is measured from the send, not the ack.
    function onComplete() as Void {
        StriveApp.onSent();
    }

    function onError() as Void {
        StriveApp.onSent();
    }

    function onResponse(responseCode as Lang.Number, data) as Void {
    }
}
