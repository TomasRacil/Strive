using Toybox.WatchUi as Ui;

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
            view.logSet();
            Ui.requestUpdate();
            return true;
        }

        if (key == Ui.KEY_ESC) {
            view.nextExercise();
            return true;
        }

        return false;
    }
}
