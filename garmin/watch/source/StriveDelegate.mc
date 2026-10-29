using Toybox.WatchUi as Ui;
using Toybox.System as Sys;

class StriveDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

    // BACK is deliberately not intercepted: it must exit the app like every
    // other watch app, otherwise there is no discoverable way out. Exercise
    // navigation lives on swipes.
    function onKey(evt) {
        var key = evt.getKey();

        if (key == Ui.KEY_UP) {
            view.adjustWeight(2.5);
            return true;
        }

        if (key == Ui.KEY_DOWN) {
            view.adjustWeight(-2.5);
            return true;
        }

        if (key == Ui.KEY_ENTER) {
            view.logSet();
            Ui.requestUpdate();
            return true;
        }

        return false;
    }

    // Touch: left third decreases, right third increases, middle opens the
    // weight wheel for an exact number. Buttons stay first-class because sweaty
    // hands and gloves make the screen unreliable exactly when logging a set.
    function onTap(evt) {
        var coords = evt.getCoordinates();
        var x = coords[0];
        var width = Sys.getDeviceSettings().screenWidth;

        if (x < width / 3) {
            view.adjustWeight(-2.5);
        } else if (x > (width * 2) / 3) {
            view.adjustWeight(2.5);
        } else {
            view.openWeightPicker();
        }

        return true;
    }

    function onSwipe(evt) {
        var direction = evt.getDirection();

        if (direction == Ui.SWIPE_UP) {
            view.logSet();
            Ui.requestUpdate();
            return true;
        }

        if (direction == Ui.SWIPE_LEFT) {
            view.nextExercise();
            return true;
        }

        if (direction == Ui.SWIPE_RIGHT) {
            view.previousExercise();
            return true;
        }

        return false;
    }
}
