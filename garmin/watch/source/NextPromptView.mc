using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Continue or change.
//
// The engine's answer is the highlight: Yes while the recommended set count is
// not reached, Different exercise once it is. The user only moves the highlight
// when they disagree, and nothing times out - the session stays open as long as
// the watch does.
class NextPromptView extends Ui.View {

    var loop;

    function initialize(model) {
        View.initialize();
        loop = model;
    }

    function take() as Void {
        if (loop.prompt() == PromptRow.SAME) {
            loop.continueSame();
        } else {
            loop.chooseDifferent();
        }

        // The exercise screen below decides what comes next: redraw for the next
        // set, or drop itself back to the picker.
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    function move(direction) as Void {
        loop.movePrompt(direction);
        Ui.requestUpdate();
    }

    // BACK: back to the same lift, without answering the question.
    function stay() as Void {
        loop.continueSame();
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    function onShow() as Void {
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.20, Gfx.FONT_SMALL, "Continue " + Text.fit(loop.name(), 10) + "?", Gfx.TEXT_JUSTIFY_CENTER);

        drawRow(dc, width, height * 0.44, PromptRow.SAME, "Yes, next set");
        drawRow(dc, width, height * 0.58, PromptRow.DIFFERENT, "Different exercise");

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.80, Gfx.FONT_XTINY, "START: take", Gfx.TEXT_JUSTIFY_CENTER);
    }

    // The caret as well as the colour: mid-set, with a sleeve over the watch, the
    // shape is what is read first.
    function drawRow(dc, width, y, row, label) {
        var selected = loop.prompt() == row;

        if (selected) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width * 0.16, y, Gfx.FONT_TINY, ">", Gfx.TEXT_JUSTIFY_LEFT);
        }

        dc.setColor(selected ? Gfx.COLOR_GREEN : Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y, Gfx.FONT_TINY, label, Gfx.TEXT_JUSTIFY_CENTER);
    }
}

class NextPromptDelegate extends Ui.InputDelegate {

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

    // BACK is "not yet": it returns to the lift without answering, which keeps
    // the session open and the next set one START away. It must not be a fourth
    // option the screen does not show, and it must not take the highlight -
    // once the recommended count is reached that highlight is "leave".
    function onBack() as Lang.Boolean {
        view.stay();
        return true;
    }
}
