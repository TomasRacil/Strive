using Toybox.WatchUi as Ui;
using Toybox.Lang;

// Input for the set sheet. Buttons only: the sheet is opened mid-set with a bar
// in the other hand, and every row is one keypress away, so a touch shortcut
// would add a way to get it wrong without removing a way to get it right.
//
// BACK is intercepted here rather than left to the system, because the sheet is
// a question and BACK answers it: nothing is banked.
class SetSheetDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

    function onKey(evt) {
        var key = evt.getKey();
        var sheet = view.sheet;

        if (key == Ui.KEY_UP) {
            sheet.adjust(1);
            Ui.requestUpdate();
            return true;
        }

        if (key == Ui.KEY_DOWN) {
            sheet.adjust(-1);
            Ui.requestUpdate();
            return true;
        }

        if (key == Ui.KEY_ENTER) {
            // next() is false on the last row, and that press is the bank.
            if (sheet.next()) {
                Ui.requestUpdate();
            } else {
                view.bank();
            }
            return true;
        }

        return false;
    }

    // The back button, which is the sheet's cancel: nothing is banked.
    function onBack() as Lang.Boolean {
        view.cancel();
        return true;
    }
}
