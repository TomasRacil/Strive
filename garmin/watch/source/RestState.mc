using Toybox.Lang;

// The rest clock, as state only.
//
// Engine.rest decides one step at a time and has no elapsed time of its own, so
// something has to hold the running length and ask again on every tick. That is
// this class: `update` is called while the clock runs and answers how long the
// rest now is and whether the rate is back.
//
// The ceiling is computed once, from the base, and passed to every call. Feeding
// the extended length back as the base without it would raise the 1.5x cap along
// with the length, so the extension would never converge.
class RestState {

    const EXTENSION_CAP = 1.5;

    var baseSeconds;
    var ceilingSeconds;
    var lengthSeconds;
    var ready;

    function initialize(base) {
        var start = base == null ? 0 : base;
        if (start < 0) {
            start = 0;
        }

        baseSeconds = start;
        ceilingSeconds = (start * EXTENSION_CAP).toNumber();
        lengthSeconds = start;
        ready = false;
    }

    // One evaluation. Returns Engine.rest's answer so the caller can buzz on the
    // transition into ready instead of polling isReady().
    function update(peakHr, currentHr, restingHr) {
        var advice = Engine.rest(lengthSeconds, peakHr, currentHr, restingHr, ceilingSeconds);
        lengthSeconds = advice[:seconds];
        ready = advice[:ready];
        return advice;
    }

    // What the screen counts down. Elapsed time is passed in rather than read
    // from a clock, so a test can pin it.
    function remaining(elapsedSeconds) as Lang.Number {
        var left = lengthSeconds - elapsedSeconds;
        return left > 0 ? left : 0;
    }

    function total() as Lang.Number {
        return lengthSeconds;
    }

    function base() as Lang.Number {
        return baseSeconds;
    }

    function ceiling() as Lang.Number {
        return ceilingSeconds;
    }

    // Not sticky: a rate that climbs again clears it, and the caller's buzz-once
    // flag is what stops a second alert. The countdown keeps running either way.
    function isReady() as Lang.Boolean {
        return ready;
    }
}
