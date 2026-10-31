using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer as Timer;
using Toybox.Time as Time;
using Toybox.Application as App;
using Toybox.Lang;

// One lift.
//
// The advised load, the rep target, one pip per set the engine wants and how
// many are banked. UP/DOWN move the load by the exercise's own increment, START
// opens the confirm sheet, BACK opens the action menu.
//
// This view is also the hub the rest of the loop hangs off: the sheet pops back
// onto it, and it decides what to show next from the state the loop is in. That
// keeps the push/pop count to one per transition, which is all the runtime
// guarantees - two pops from one keypress drop one of them on this firmware.
class ExerciseView extends Ui.View {

    var loop;
    var ticker;
    var visible;

    function initialize(model) {
        View.initialize();
        loop = model;
        ticker = null;
        visible = false;
    }

    // ---- heart rate ------------------------------------------------------

    // One sample per second while a set is being done: the peak from the start
    // of the set is what the rest is computed from, and the rate is still
    // climbing when the bar goes down.
    function startTicker() as Void {
        if (ticker == null) {
            ticker = new Timer.Timer();
        }
        ticker.start(method(:onTick), 1000, false);
    }

    function stopTicker() as Void {
        if (ticker != null) {
            ticker.stop();
        }
    }

    function onTick() as Void {
        if (!visible) {
            return;
        }
        loop.sampleHr(HeartRate.read(), Time.now().value());
        startTicker();
    }

    // ---- input -----------------------------------------------------------

    function adjust(direction) as Void {
        loop.adjustWeight(direction);
        Ui.requestUpdate();
    }

    function logSet() as Void {
        loop.openSheet();
        var sheet = new SetSheetView(loop.sheet, loop, Text.fit(loop.name(), 12));
        Ui.pushView(sheet, new SetSheetDelegate(sheet), Ui.SLIDE_UP);
    }

    function menu() as Void {
        Ui.pushView(new ActionMenuView(loop), new ActionMenuDelegate(loop), Ui.SLIDE_UP);
    }

    // ---- the transition hub ---------------------------------------------

    // Called every time this view is revealed: after the sheet banks a set,
    // after the rest ends, after the prompt is answered, and after the action
    // menu closes. The loop already holds the answer, so this only has to draw
    // it or hand over to the next screen.
    function onShow() as Void {
        StriveApp.drain();

        if (loop.state == LoopState.REST) {
            Ui.pushView(new RestView(loop), new RestDelegate(loop), Ui.SLIDE_LEFT);
            return;
        }

        if (loop.state == LoopState.NEXT_PROMPT) {
            Ui.pushView(new NextPromptView(loop), new NextPromptDelegate(loop), Ui.SLIDE_LEFT);
            return;
        }

        // The lift is over or the session is: drop this screen and let the
        // picker (or Home) below it decide what comes next.
        if (loop.state == LoopState.PICK || loop.state == LoopState.SUMMARY) {
            Ui.popView(Ui.SLIDE_RIGHT);
            return;
        }

        visible = true;
        startTicker();
        Ui.requestUpdate();
    }

    function onHide() as Void {
        visible = false;
        stopTicker();
    }

    // ---- drawing ---------------------------------------------------------

    // Guarded for the same reason as the picker: an exception while drawing
    // must not take the session down, and the message is the only stack a wrist
    // can show.
    function onUpdate(dc) {
        var stored = App.Storage.getValue("crash");
        if (stored != null) {
            showMessage(dc, stored.toString());
            return;
        }

        try {
            paint(dc);
        } catch (e) {
            var message = e.getErrorMessage();
            if (message == null) {
                message = "unreadable";
            }
            App.Storage.setValue("crash", message);
            showMessage(dc, message);
        }
    }

    function showMessage(dc, message) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.26, Gfx.FONT_XTINY, "EXERCISE", Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.42, Gfx.FONT_XTINY, Text.fit(message, 24), Gfx.TEXT_JUSTIFY_CENTER);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.60, Gfx.FONT_XTINY, "BACK to leave", Gfx.TEXT_JUSTIFY_CENTER);
    }

    function paint(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.10, Gfx.FONT_SMALL, Text.fit(loop.name(), 12), Gfx.TEXT_JUSTIFY_CENTER);

        // The load is the biggest thing on the screen: it is what the bar is
        // loaded to, and "BW" is a load, not an empty field.
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.30, Gfx.FONT_LARGE, loop.loadLabel(), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.44, Gfx.FONT_TINY, loop.reps.toString() + " reps", Gfx.TEXT_JUSTIFY_CENTER);

        drawPips(dc, width, height);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.66, Gfx.FONT_TINY, loop.setLabel(), Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.78, Gfx.FONT_XTINY, "START: log set", Gfx.TEXT_JUSTIFY_CENTER);

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.87, Gfx.FONT_XTINY, "BACK: menu", Gfx.TEXT_JUSTIFY_CENTER);
    }

    // One pip per recommended set, filled for banked. The count is the engine's
    // (2 to 5), and the spacing is set so five fit inside the round face without
    // touching the bezel.
    function drawPips(dc, width, height) {
        var total = loop.recommended;
        if (total <= 0) {
            return;
        }

        var spacing = width * 0.075;
        var radius = width * 0.016;
        var y = height * 0.56;
        var startX = (width / 2) - (spacing * (total - 1)) / 2;

        for (var i = 0; i < total; i++) {
            var x = startX + spacing * i;
            if (i < loop.done) {
                dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, radius);
            } else {
                dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
                dc.drawCircle(x, y, radius);
            }
        }
    }
}

class ExerciseDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

    function onKey(evt) {
        var key = evt.getKey();

        if (key == Ui.KEY_UP) {
            view.adjust(1);
            return true;
        }

        if (key == Ui.KEY_DOWN) {
            view.adjust(-1);
            return true;
        }

        if (key == Ui.KEY_ENTER) {
            view.logSet();
            return true;
        }

        return false;
    }

    // BACK opens the action menu rather than leaving the lift, because ending the
    // session is an action and a stray BACK mid-set must not throw the session
    // away.
    function onBack() as Lang.Boolean {
        view.menu();
        return true;
    }
}
