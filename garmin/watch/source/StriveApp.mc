using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Time as Time;
using Toybox.Lang;

// Entry point. Everything that crosses to the phone goes through Bus, and
// everything Bus emits goes through the persistent outbox, so nothing here has
// to know how the transport behaves.
//
// This is also the one place that owns the training loop. The loop is pure - no
// Storage, no clock, no Graphics - so the wiring lives here: build it from what
// the phone has sent, hand it to the views, and write the sets it accepts.
class StriveApp extends App.AppBase {

    // Outbound queue, owned by an instance: Monkey C cannot take a method
    // reference from a static function, so the pacing timer needs an object.
    static var outbox = new Outbox();

    // One loop for the app's lifetime. The views hold a reference to it, so it is
    // never replaced, only reloaded when the phone sends something newer.
    static var loop = null;

    // The finished session, waiting for Home to be on screen to show it. The
    // finish cascade pops three views before it gets there, and the summary has
    // to survive the trip.
    static var finished = null;

    // ---- the loop --------------------------------------------------------

    static function trainingLoop() {
        if (loop == null) {
            loop = newLoop();
        }
        return loop;
    }

    static function newLoop() {
        var now = Time.now().value();
        // No seeds: calibration is a separate milestone, so every lift starts
        // from Engine's fallback seed and its own floor. That is the documented
        // behaviour before the first calibration, not a missing wire.
        return new TrainingLoop(
            TrainingLoop.specsFrom(Library.exercises()),
            Library.historySets(now),
            {},
            Library.profile("bodyKg", null),
            Library.recWeights()
        );
    }

    // A library, history or recommendation arrived. The catalogue is swapped in
    // place rather than the loop rebuilt: the loop holds the session's tallies
    // and the view on screen holds the loop.
    static function refreshLoop() as Void {
        if (loop == null) {
            return;
        }
        var now = Time.now().value();
        loop.reload(
            TrainingLoop.specsFrom(Library.exercises()),
            Library.historySets(now),
            null,
            Library.profile("bodyKg", null),
            Library.recWeights()
        );
    }

    // ---- the session -----------------------------------------------------

    // One accepted set, in the order that matters: the session exists, the set is
    // in Storage with the RIR the user confirmed, and only then does it go on the
    // wire. A set that never reaches the phone is still a set that happened.
    static function recordSet(loopRef, set) as Void {
        if (!Session.active()) {
            Session.start();
            Bus.sendStart();
        }

        Session.addSetWithRir(loopRef.exerciseId, set[:weight], set[:reps], set[:rir]);
        Bus.sendSet(Session.setCount() - 1);
    }

    // Finishes the session: the log is read out before anything is cleared, and
    // the summary is held for Home to draw. An empty session sends nothing - the
    // phone has no use for an `end` with no sets in it.
    static function endSession() as Void {
        var summary = Session.summary();
        if (summary[:sets] > 0) {
            Bus.sendEnd(summary[:log]);
        }
        Session.end();
        finished = summary;
    }

    static function pendingSummary() {
        return finished;
    }

    static function takeSummary() {
        var summary = finished;
        finished = null;
        return summary;
    }

    // ---- bus plumbing ----------------------------------------------------

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

    static function rejected(id) as Void {
        outbox.failed(id);
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

    // ---- lifecycle -------------------------------------------------------

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var home = new HomeView(trainingLoop());
        return [ home, new HomeDelegate(home) ];
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

        // A library, a recommendation or a history can change what the picker
        // offers and what the next set is loaded to, so the loop re-reads them
        // rather than waiting for the next launch.
        if (Text.same(applied, "lib") || Text.same(applied, "rec") ||
            Text.same(applied, "hist") || Text.same(applied, "profile")) {
            refreshLoop();
        }
        Ui.requestUpdate();
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
