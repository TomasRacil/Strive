using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer as Timer;
using Toybox.Attention as Attention;
using Toybox.Communications as Comm;

// One screen per exercise: the recommended load, the target reps, how many sets
// you have logged this session, and a rest countdown between sets.
class StriveView extends Ui.View {

    var index;
    var weight;
    var sets;
    var restRemaining;   // seconds left, 0 when not resting
    var timer;

    function initialize() {
        View.initialize();
        index = 0;
        sets = 0;
        weight = 20.0;
        restRemaining = 0;
        timer = null;
        loadExercise();
    }

    function currentExercise() {
        return Exercises.list()[index];
    }

    function loadExercise() {
        var exercise = currentExercise();
        // A weight pushed from the phone wins over the watch's own guess: the
        // phone has the whole history behind it, the watch only its own record.
        var planned = Plan.weightFor(exercise[:id]);
        if (planned != null) {
            weight = planned;
        } else {
            weight = Progress.suggest(exercise[:id], 20.0);
        }
        sets = 0;
        stopRest();
    }

    function reloadFromPlan() {
        var planned = Plan.weightFor(currentExercise()[:id]);
        if (planned != null) {
            weight = planned;
        }
    }

    function adjustWeight(delta) {
        weight = weight + delta;
        if (weight < 0.0) {
            weight = 0.0;
        }
        Ui.requestUpdate();
    }

    function setWeight(value) {
        weight = value.toFloat();
        if (weight < 0.0) {
            weight = 0.0;
        }
        Ui.requestUpdate();
    }

    function openWeightPicker() {
        Ui.pushView(new WeightPicker(weight), new WeightPickerDelegate(self), Ui.SLIDE_IMMEDIATE);
    }

    function isResting() {
        return restRemaining > 0;
    }

    function startRest(seconds) {
        restRemaining = seconds;
        if (timer == null) {
            timer = new Timer.Timer();
        }
        timer.start(method(:onRestTick), 1000, true);
        Ui.requestUpdate();
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
            stopRest();
            buzz();
        }
        Ui.requestUpdate();
    }

    // Rest is over: two short pulses, felt through a shirt and a strap.
    function buzz() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(60, 350),
                new Attention.VibeProfile(0, 150),
                new Attention.VibeProfile(60, 350)
            ]);
        }
    }

    // A running timer must not keep firing while the app is in the background.
    function onHide() {
        if (timer != null) {
            timer.stop();
        }
    }

    function onShow() {
        if (restRemaining > 0 && timer != null) {
            timer.start(method(:onRestTick), 1000, true);
        }
        Ui.requestUpdate();
    }

    function restText() {
        var minutes = restRemaining / 60;
        var seconds = restRemaining % 60;
        var pad = seconds < 10 ? "0" : "";
        return minutes.toString() + ":" + pad + seconds.toString();
    }

    function logSet() {
        var exercise = currentExercise();
        sets = sets + 1;
        // Completing the target number of sets is what earns the load increase
        // next session. Editing reps on the wrist is not worth the button presses.
        var completed = sets >= 3;
        Progress.record(exercise[:id], weight, completed);
        startRest(exercise[:rest]);
    }

    function nextExercise() {
        index = (index + 1) % Exercises.count();
        loadExercise();
        Ui.requestUpdate();
    }

    function previousExercise() {
        index = (index - 1 + Exercises.count()) % Exercises.count();
        loadExercise();
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var exercise = currentExercise();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.10, Gfx.FONT_SMALL, exercise[:name], Gfx.TEXT_JUSTIFY_CENTER);

        if (isResting()) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.30, Gfx.FONT_TINY, "REST", Gfx.TEXT_JUSTIFY_CENTER);

            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.42, Gfx.FONT_LARGE, restText(), Gfx.TEXT_JUSTIFY_CENTER);

            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.64, Gfx.FONT_SMALL, weight.format("%.1f") + " kg", Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(width / 2, height * 0.72, Gfx.FONT_TINY, "sets " + sets.toString(), Gfx.TEXT_JUSTIFY_CENTER);

            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.80, Gfx.FONT_XTINY, "start: skip rest", Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.34, Gfx.FONT_LARGE, weight.format("%.1f"), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.58, Gfx.FONT_SMALL, "kg", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(
            width / 2,
            height * 0.74,
            Gfx.FONT_TINY,
            exercise[:reps].toString() + " reps   sets " + sets.toString(),
            Gfx.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.80, Gfx.FONT_XTINY, "swipe: change lift", Gfx.TEXT_JUSTIFY_CENTER);
    }
}
