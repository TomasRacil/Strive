using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Timer as Timer;
using Toybox.Time as Time;
using Toybox.Lang;

// Rest.
//
// The countdown is the engine's rest for this exercise, extended in 15 s steps
// while the rate is still above 40% of heart-rate reserve and capped at 1.5x the
// base - all of that lives in Engine.rest and RestState. This screen counts it
// down, shows the rate, and buzzes twice: two pulses the first time the rate is
// back, three when the rest is over.
//
// With no heart rate there is no HR line, no target and no extension: the rest
// is exactly the base. That is the strap-off case, not an error.
class RestView extends Ui.View {

    var loop;
    var ticker;
    var visible;
    var finished;
    var readyAlerted;
    var hr;
    var restingHr;

    function initialize(model) {
        View.initialize();
        loop = model;
        ticker = null;
        visible = false;
        finished = false;
        readyAlerted = false;
        hr = null;
        restingHr = Library.profile("restHr", null);
    }

    // ---- the clock -------------------------------------------------------

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

    // One shot per second, rescheduled from its own callback: a repeating timer
    // whose stop() lands inside its callback keeps firing on this firmware.
    function onTick() as Void {
        if (!visible || finished) {
            return;
        }

        var now = Time.now().value();
        hr = HeartRate.read();
        loop.sampleHr(hr, now);

        if (loop.rest != null) {
            var advice = loop.rest.update(loop.peakHr(), hr, restingHr);
            // Buzz once on the transition, not on every tick that finds the rate
            // back: the countdown keeps running either way.
            if (advice[:ready] && !readyAlerted) {
                readyAlerted = true;
                Haptics.ready();
            }
        }

        if (loop.restRemaining(now) <= 0) {
            endRest(true);
            return;
        }

        Ui.requestUpdate();
        startTicker();
    }

    // `buzzed` is false when the user skipped: three pulses mean the rest ran
    // its course, and a rest the user cut short did not.
    function endRest(buzzed) as Void {
        if (finished) {
            return;
        }
        finished = true;
        stopTicker();

        if (buzzed) {
            Haptics.restOver();
        }

        loop.restFinished();
        Ui.popView(Ui.SLIDE_RIGHT);
    }

    function skip() as Void {
        endRest(false);
    }

    function onShow() as Void {
        visible = true;
        Ui.requestUpdate();
        startTicker();
    }

    function onHide() as Void {
        visible = false;
        stopTicker();
    }

    // ---- drawing ---------------------------------------------------------

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.14, Gfx.FONT_XTINY, "REST", Gfx.TEXT_JUSTIFY_CENTER);

        var remaining = loop.restRemaining(Time.now().value());
        dc.setColor(remaining > 0 ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.28, Gfx.FONT_LARGE, Text.clock(remaining), Gfx.TEXT_JUSTIFY_CENTER);

        if (loop.rest != null && loop.rest.isReady()) {
            dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.44, Gfx.FONT_TINY, "READY", Gfx.TEXT_JUSTIFY_CENTER);
        }

        // The rate that was reached during the set and the one now: the pair is
        // what says whether the rest is working, and one number alone does not.
        if (hr != null) {
            var peak = loop.peakHr();
            var from = peak == null ? "-" : peak.toString();
            dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.55, Gfx.FONT_XTINY, "HR " + from + " > " + hr.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        }

        var target = loop.readyTarget(restingHr);
        if (target != null) {
            dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 0.65, Gfx.FONT_XTINY, "ready at " + target.toString(), Gfx.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * 0.80, Gfx.FONT_XTINY, "START: skip", Gfx.TEXT_JUSTIFY_CENTER);
    }
}

class RestDelegate extends Ui.InputDelegate {

    var view;

    function initialize(targetView) {
        InputDelegate.initialize();
        view = targetView;
    }

    // START cuts the rest short. So does BACK: the two buttons both mean "I am
    // done resting", and trapping the user in a countdown would be the one thing
    // the button model forbids.
    function onKey(evt) {
        if (evt.getKey() == Ui.KEY_ENTER) {
            view.skip();
            return true;
        }
        return false;
    }

    function onBack() as Lang.Boolean {
        view.skip();
        return true;
    }
}
