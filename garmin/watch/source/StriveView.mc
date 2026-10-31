using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer as Timer;
using Toybox.Attention as Attention;
using Toybox.Application as App;
using Toybox.Time as Time;
using Toybox.Lang;

// The training screen: one lift at a time, with the load the phone recommends,
// the rep target, and the sets banked this session.
//
// The plan arrives over the companion message bus (phone -> watch) and the
// finished session leaves the same way, so nothing here touches Bluetooth
// directly. Session state lives in Session.mc and is written on every set, so a
// killed app resumes rather than losing the workout.
class StriveView extends Ui.View {

    // Bumped by hand on every build that goes to the watch.
    const BUILD_TAG = "t1";

    const TARGET_SETS = 3;

    var index;
    var weight;
    var reps;
    var restRemaining;
    var restAlerted;
    var finishArmed;
    var timer;

    function initialize() {
        View.initialize();
        index = Session.active() ? Session.index() : 0;
        weight = 20.0;
        reps = 8;
        restRemaining = 0;
        restAlerted = false;
        finishArmed = 0;
        timer = null;
        loadExercise();
    }

    function currentExercise() {
        return Exercises.list()[index];
    }

    function loadExercise() {
        var exercise = currentExercise();
        // A weight from the phone wins: it has the whole history behind it.
        var planned = Plan.weightFor(exercise[:id]);
        if (planned != null) {
            weight = planned;
        } else {
            weight = Progress.suggest(exercise[:id], 20.0);
        }
        reps = exercise[:reps];
        stopRest();
    }

    // Called when a plan message lands, so the screen reflects it without a
    // restart.
    function reloadFromPlan() {
        var planned = Plan.weightFor(currentExercise()[:id]);
        if (planned != null) {
            weight = planned;
        }
        Ui.requestUpdate();
    }

    function setsLogged() {
        return Session.setsFor(currentExercise()[:id]);
    }

    // ---- session ---------------------------------------------------------

    function startSession() {
        Session.start();
        Session.setIndex(index);
        // Tells the phone a workout began. Queued, not sent: it waits its turn
        // behind anything already in the outbox and is retried until acked.
        StriveApp.syncStart();
        Ui.requestUpdate();
    }

    function logSet() {
        // First press starts the session; the set itself is the next press, so a
        // stray tap cannot bank work that was not done.
        if (!Session.active()) {
            startSession();
            return;
        }

        var exercise = currentExercise();
        Session.addSet(exercise[:id], weight, reps);
        Progress.record(exercise[:id], weight, setsLogged() >= TARGET_SETS);
        StriveApp.syncSet();
        startRest(exercise[:rest]);
    }

    function requestFinish() {
        if (!Session.active()) {
            return;
        }

        var now = Time.now().value();
        if (finishArmed > 0 && now - finishArmed <= 5) {
            finishArmed = 0;
            finishSession();
            return;
        }

        finishArmed = now;
        Ui.requestUpdate();
    }

    function finishSession() {
        var summary = Session.summary();
        // One message, one payload: the log is a snapshot, so a resend is
        // harmless and the phone can ignore duplicates.
        StriveApp.syncLog(summary[:log]);
        Session.end();
        Ui.pushView(new SummaryView(summary), new SummaryDelegate(), Ui.SLIDE_LEFT);
    }

    // ---- load ------------------------------------------------------------

    function adjustWeight(delta) {
        weight = weight + delta;
        if (weight < 0.0) {
            weight = 0.0;
        }
        Ui.requestUpdate();
    }

    // ---- rest ------------------------------------------------------------

    function isResting() {
        return restRemaining > 0;
    }

    function startRest(seconds) {
        restRemaining = seconds;
        restAlerted = false;
        scheduleRestTick();
        Ui.requestUpdate();
    }

    // One-shot per second. A repeating timer whose stop() lands in its own
    // callback keeps firing, which makes restRemaining negative and re-buzzes
    // every second until the watch appears frozen.
    function scheduleRestTick() {
        if (timer == null) {
            timer = new Timer.Timer();
        }
        timer.start(method(:onRestTick), 1000, false);
    }

    function stopRest() {
        restRemaining = 0;
        if (timer != null) {
            timer.stop();
        }
    }

    function skipRest() {
        stopRest();
        Ui.requestUpdate();
    }

    function onRestTick() {
        if (restRemaining > 0) {
            restRemaining = restRemaining - 1;
        }

        if (restRemaining <= 0) {
            if (!restAlerted) {
                restAlerted = true;
                stopRest();
                buzz();
            }
        } else {
            scheduleRestTick();
        }

        Ui.requestUpdate();
    }

    function buzz() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(60, 350),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(60, 350)
            ]);
        }
    }

    // ---- exercises -------------------------------------------------------

    function nextExercise() {
        index = (index + 1) % Exercises.count();
        Session.setIndex(index);
        loadExercise();
        Ui.requestUpdate();
    }

    function previousExercise() {
        index = (index - 1 + Exercises.count()) % Exercises.count();
        Session.setIndex(index);
        loadExercise();
        Ui.requestUpdate();
    }

    function onShow() {
        if (restRemaining > 0) {
            scheduleRestTick();
        }
        StriveApp.drain();
        reloadFromPlan();
    }

    function onHide() {
        if (timer != null) {
            timer.stop();
        }
    }

    // ---- drawing ---------------------------------------------------------

    function clockText(seconds) {
        var minutes = seconds / 60;
        var secs = seconds % 60;
        var pad = secs < 10 ? "0" : "";
        return minutes.toString() + ":" + pad + secs.toString();
    }

    function nameText(name) {
        // FONT_SMALL is wide on a round face; the long exercise names lose their
        // ends otherwise.
        var text = name.toString();
        return text.length() > 12 ? text.substring(0, 12) : text;
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.075, Gfx.FONT_SMALL, nameText(currentExercise()[:name]), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            width / 2,
            height * 0.165,
            Gfx.FONT_XTINY,
            (index + 1).toString() + "/" + Exercises.count().toString() + "  " + clockText(Session.elapsedSeconds()),
            Gfx.TEXT_JUSTIFY_CENTER
        );

        if (!Session.active()) {
            drawIdle(dc, width, height);
            return;
        }

        if (isResting()) {
            drawRest(dc, width, height);
        } else {
            drawWorking(dc, width, height);
        }

        drawPips(dc, width, height);
        drawBusLine(dc, width, height);
    }

    function drawIdle(dc, width, height) {
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.34, Gfx.FONT_LARGE, weight.format("%.1f"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.47, Gfx.FONT_TINY, "kg", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, height * 0.58, Gfx.FONT_TINY, reps.toString() + " reps", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.70, Gfx.FONT_XTINY, "START to begin", Gfx.TEXT_JUSTIFY_CENTER);

        drawBusLine(dc, width, height);
    }

    function drawWorking(dc, width, height) {
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.32, Gfx.FONT_LARGE, weight.format("%.1f"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.45, Gfx.FONT_TINY, "kg", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            width / 2,
            height * 0.55,
            Gfx.FONT_TINY,
            reps.toString() + " x " + setsLogged().toString() + "/" + TARGET_SETS.toString(),
            Gfx.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.74, Gfx.FONT_XTINY, finishHint(), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawRest(dc, width, height) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.28, Gfx.FONT_TINY, "REST", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.40, Gfx.FONT_LARGE, clockText(restRemaining), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(
            width / 2,
            height * 0.55,
            Gfx.FONT_TINY,
            weight.format("%.1f") + " kg " + reps.toString() + "r",
            Gfx.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.74, Gfx.FONT_XTINY, "START: skip", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function finishHint() {
        if (finishArmed > 0 && Time.now().value() - finishArmed <= 5) {
            return "swipe again";
        }
        return "swipe down";
    }

    // One pip per target set: filled means banked.
    function drawPips(dc, width, height) {
        var done = setsLogged();
        var spacing = width * 0.075;
        var radius = width * 0.018;
        var y = height * 0.65;
        var startX = (width / 2) - (spacing * (TARGET_SETS - 1)) / 2;

        for (var i = 0; i < TARGET_SETS; i++) {
            var x = startX + spacing * i;
            if (i < done) {
                dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, radius);
            } else {
                dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
                dc.drawCircle(x, y, radius);
            }
        }
    }

    // One short line for the message bus, and only what a glance needs: the last
    // thing the phone sent, or the build tag when nothing has arrived.
    function drawBusLine(dc, width, height) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.86, Gfx.FONT_XTINY, busText(), Gfx.TEXT_JUSTIFY_CENTER);
    }

    function busText() as Lang.String {
        var text = App.Storage.getValue("ble_dbg");
        if (text == null) {
            return BUILD_TAG;
        }

        var value = text.toString();
        if (value.length() > 16) {
            return value.substring(0, 16);
        }
        return value;
    }
}
