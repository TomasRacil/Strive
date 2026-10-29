using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;

// One screen per exercise: the recommended load, the target reps, and how many
// sets you have logged in this session.
class StriveView extends Ui.View {

    var index;
    var weight;
    var sets;

    function initialize() {
        View.initialize();
        index = 0;
        sets = 0;
        weight = 20.0;
        loadExercise();
    }

    function currentExercise() {
        return Exercises.list()[index];
    }

    function loadExercise() {
        var exercise = currentExercise();
        weight = Progress.suggest(exercise[:id], 20.0);
        sets = 0;
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

    function logSet() {
        var exercise = currentExercise();
        sets = sets + 1;
        // Completing the target number of sets is what earns the load increase
        // next session. Editing reps on the wrist is not worth the button presses.
        var completed = sets >= 3;
        Progress.record(exercise[:id], weight, completed);
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
        dc.drawText(width / 2, height * 0.80, Gfx.FONT_XTINY, "sides: load   mid: pick", Gfx.TEXT_JUSTIFY_CENTER);
    }
}
