using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Home.
//
// One row, because free training is the only flow that exists on the watch yet.
// Workout mode needs a plan the phone has pushed and calibration needs its own
// three screens; a row that opens nothing is worse than a row that is not there,
// so both land in the same PR as the thing they open.
class HomeView extends Ui.View {

    var loop;

    function initialize(model) {
        View.initialize();
        loop = model;
    }

    function open() as Void {
        loop.start();
        Ui.pushView(new PickerView(loop), new PickerDelegate(loop), Ui.SLIDE_LEFT);
    }

    // The end of the finish cascade: the action menu popped, the exercise popped,
    // the picker popped, and this is the screen left holding the finished
    // session. closeSummary() first, or coming back from the summary would push
    // it a second time.
    function onShow() as Void {
        StriveApp.drain();

        if (loop.state == LoopState.SUMMARY && StriveApp.pendingSummary() != null) {
            var summary = StriveApp.takeSummary();
            loop.closeSummary();
            Ui.pushView(new SummaryView(summary), new SummaryDelegate(), Ui.SLIDE_LEFT);
        }
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.16, Gfx.FONT_SMALL, "Strive", Gfx.TEXT_JUSTIFY_CENTER);

        // The only row is the highlighted one, and it keeps the caret and the
        // colour the rest of the app uses for "this is what START does".
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width * 0.22, height * 0.42, Gfx.FONT_TINY, ">", Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(width / 2, height * 0.42, Gfx.FONT_TINY, "Free training", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.78, Gfx.FONT_XTINY, "START: open", Gfx.TEXT_JUSTIFY_CENTER);

        // The last breadcrumb, so a crash on another screen leaves a trace that
        // survives it.
        var crumb = Crumb.last();
        if (crumb != null) {
            dc.setColor(Gfx.COLOR_ORANGE, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.90, Gfx.FONT_XTINY, Text.fit(crumb, 20), Gfx.TEXT_JUSTIFY_CENTER);
        }
    }
}

class HomeDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

    function onKey(evt) {
        if (evt.getKey() == Ui.KEY_ENTER) {
            view.open();
            return true;
        }
        return false;
    }

    // BACK is left to the system: on the first screen it is the only way out of
    // the app, and a watch user already knows what it does.
    function onBack() as Lang.Boolean {
        return false;
    }
}
