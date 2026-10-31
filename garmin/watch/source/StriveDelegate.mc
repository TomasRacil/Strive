using Toybox.WatchUi as Ui;

// Input for the training screen. Buttons are first-class: gloves and sweaty hands
// make the touchscreen unreliable exactly when a set needs logging. BACK is left
// to the system so the app can always be exited.
class StriveDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

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
            // While resting, START cuts the rest short instead of logging a set.
            if (view.isResting()) {
                view.skipRest();
            } else {
                view.logSet();
            }
            Ui.requestUpdate();
            return true;
        }

        return false;
    }

    // Touch: left third decreases, right third increases.
    function onTap(evt) {
        var coords = evt.getCoordinates();
        var x = coords[0];
        var width = Toybox.System.getDeviceSettings().screenWidth;

        if (x < width / 3) {
            view.adjustWeight(-2.5);
        } else if (x > (width * 2) / 3) {
            view.adjustWeight(2.5);
        } else {
            view.logSet();
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

        // Finishing is armed by the first downward swipe and confirmed by the
        // second, so a wet screen cannot end a session by accident.
        if (direction == Ui.SWIPE_DOWN) {
            view.requestFinish();
            return true;
        }

        return false;
    }
}
