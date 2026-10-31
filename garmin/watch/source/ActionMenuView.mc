using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Time as Time;
using Toybox.Lang;

// The action menu BACK opens on the exercise screen.
//
// Two rows, both of which do something. docs/watch-ux.md also lists "Add
// exercise here", which inserts a lift at a position in a plan; free training
// has no positions, so it would be a row that does nothing. It lands with
// workout mode, which is where it means something.
//
// Finishing asks once and takes a second press within five seconds. A session is
// the one thing on this watch that cannot be rebuilt, so it is never one
// keypress away from being thrown away.
class ActionMenuView extends Ui.View {

    const END_EXERCISE = 0;
    const FINISH = 1;
    const ROWS = 2;
    const CONFIRM_SECONDS = 5;

    var loop;
    var cursor;
    var armedAt;

    function initialize(model) {
        View.initialize();
        loop = model;
        cursor = 0;
        armedAt = 0;
    }

    function move(direction) as Void {
        var moved = cursor + direction;
        if (moved < 0) {
            moved = 0;
        }
        if (moved > ROWS - 1) {
            moved = ROWS - 1;
        }
        cursor = moved;

        // Moving off the row disarms it: the confirmation belongs to the press
        // the user is about to repeat, not to the menu.
        armedAt = 0;
        Ui.requestUpdate();
    }

    function take() as Void {
        if (cursor == END_EXERCISE) {
            // The sets are already banked; this only changes the screen. The
            // exercise view below pops itself when it sees the picker state.
            loop.chooseDifferent();
            Ui.popView(Ui.SLIDE_DOWN);
            return;
        }

        var now = Time.now().value();
        if (armedAt > 0 && now - armedAt <= CONFIRM_SECONDS) {
            armedAt = 0;
            StriveApp.endSession();
            loop.finish();
            Ui.popView(Ui.SLIDE_DOWN);
            return;
        }

        armedAt = now;
        Ui.requestUpdate();
    }

    function isArmed() as Lang.Boolean {
        return armedAt > 0 && Time.now().value() - armedAt <= CONFIRM_SECONDS;
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.16, Gfx.FONT_SMALL, Text.fit(loop.name(), 12), Gfx.TEXT_JUSTIFY_CENTER);

        drawRow(dc, width, height * 0.42, END_EXERCISE, "End exercise");
        drawRow(dc, width, height * 0.56, FINISH, isArmed() ? "Press again to finish" : "Finish workout");

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.80, Gfx.FONT_XTINY, "BACK: cancel", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function drawRow(dc, width, y, row, label) {
        var selected = cursor == row;

        if (selected) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width * 0.12, y, Gfx.FONT_XTINY, ">", Gfx.TEXT_JUSTIFY_LEFT);
        }

        // Armed is not green: it is a warning, and the rest of the app uses green
        // for "this is what START does", not for "this cannot be undone".
        var colour = selected ? (isArmed() && row == FINISH ? Gfx.COLOR_ORANGE : Gfx.COLOR_GREEN) : Gfx.COLOR_LT_GRAY;
        dc.setColor(colour, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);
    }
}

class ActionMenuDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

    function onKey(evt) {
        var key = evt.getKey();

        if (key == Ui.KEY_UP) {
            view.move(-1);
            return true;
        }

        if (key == Ui.KEY_DOWN) {
            view.move(1);
            return true;
        }

        if (key == Ui.KEY_ENTER) {
            view.take();
            return true;
        }

        return false;
    }

    function onBack() as Lang.Boolean {
        Ui.popView(Ui.SLIDE_DOWN);
        return true;
    }
}
