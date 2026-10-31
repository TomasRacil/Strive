using Toybox.Test;
using Toybox.Lang;

// The rest clock and the peak tracker.
//
// The formula itself is Engine.rest, covered against the shared vectors in
// TestEngine.mc. What is tested here is the wiring around it, because that is
// where the rest can go wrong without any formula changing: the ceiling has to
// stay the original one, and a missing heart rate has to change nothing.

// No strap, or a strap that is off: the rest is exactly the base. Anything else
// would let a dead sensor shorten or delay a rest.
(:test)
function testRestStateWithoutHeartRateIsTheBase(logger) as Lang.Boolean {
    var rest = new RestState(150);
    var advice = rest.update(null, null, 60);

    logger.debug("no hr: " + rest.total().toString() + "s ready=" + rest.isReady().toString());
    return rest.total() == 150 && advice[:seconds] == 150 && !rest.isReady() && rest.ceiling() == 225;
}

// A peak but no current reading is the same case one step further in: half a
// heart rate must not extend anything either.
(:test)
function testRestStateWithOnlyAPeakIsTheBase(logger) as Lang.Boolean {
    var rest = new RestState(120);
    rest.update(190, null, 60);
    return rest.total() == 120 && !rest.isReady();
}

(:test)
function testRestStateExtendsInFifteenSecondSteps(logger) as Lang.Boolean {
    var rest = new RestState(120);

    var first = rest.update(190, 180, 60)[:seconds];
    var second = rest.update(190, 180, 60)[:seconds];

    logger.debug("steps: " + first.toString() + " then " + second.toString());
    return first == 135 && second == 150;
}

// The trap this class exists to avoid: feeding the extended length back as the
// base without the original ceiling raises the 1.5x cap with every step, so the
// rest grows for as long as the rate stays high.
(:test)
function testRestStateStopsAtTheOriginalCeiling(logger) as Lang.Boolean {
    var rest = new RestState(150);

    for (var i = 0; i < 20; i++) {
        rest.update(200, 195, 60);
    }

    logger.debug("ceiling: " + rest.total().toString() + " of " + rest.ceiling().toString());
    return rest.total() == 225 && rest.ceiling() == 225;
}

// Target is 60 + 0.4 * (180 - 60) = 108. At the target counts as back.
(:test)
function testRestStateReadyAtOrBelowTarget(logger) as Lang.Boolean {
    var rest = new RestState(150);

    var at = rest.update(180, 108, 60);
    var below = rest.update(180, 90, 60);

    logger.debug("ready: at=" + at[:ready].toString() + " below=" + below[:ready].toString());
    return at[:ready] && below[:ready] && rest.isReady() && rest.total() == 150;
}

(:test)
function testRestStateAboveTargetIsNotReady(logger) as Lang.Boolean {
    var rest = new RestState(150);
    var advice = rest.update(180, 109, 60);

    logger.debug("above target: " + advice[:seconds].toString() + " ready=" + advice[:ready].toString());
    return !advice[:ready] && rest.total() == 165;
}

// Ready does not cut the rest short: the user may want the full interval anyway,
// so the countdown keeps the length it had reached.
(:test)
function testRestStateKeepsItsLengthOnceReady(logger) as Lang.Boolean {
    var rest = new RestState(120);
    rest.update(190, 180, 60);

    var advice = rest.update(190, 100, 60);
    logger.debug("ready length: " + rest.total().toString() + " remaining " + rest.remaining(35).toString());

    return advice[:ready] && rest.total() == 135 && rest.remaining(35) == 100;
}

(:test)
function testRestStateRemainingStopsAtZero(logger) as Lang.Boolean {
    var rest = new RestState(150);

    return rest.remaining(0) == 150 && rest.remaining(150) == 0 && rest.remaining(400) == 0;
}

// ---- the peak --------------------------------------------------------------

// A null reading is a strap that is off, not a rate of zero.
(:test)
function testHrPeakIgnoresNull(logger) as Lang.Boolean {
    var peak = new HrPeak();
    peak.sample(null);
    var empty = peak.peak();

    peak.sample(150);
    peak.sample(null);
    peak.sample(140);

    logger.debug("peak: " + (empty == null ? "null" : empty.toString()) + " then " + peak.peak().toString());
    return empty == null && peak.peak() == 150;
}

(:test)
function testHrPeakDoesNotGoBackwards(logger) as Lang.Boolean {
    var peak = new HrPeak();
    peak.sample(170);
    peak.sample(120);
    peak.sample(169);

    return peak.peak() == 170;
}

(:test)
function testHrPeakReset(logger) as Lang.Boolean {
    var peak = new HrPeak();
    peak.sample(170);
    peak.reset();

    peak.sample(120);
    return peak.peak() == 120;
}

// The rate is still climbing when the bar goes down, so the 20 s after the set
// count - and a sample past that belongs to the next rest.
(:test)
function testHrPeakIgnoresSamplesPastTheTail(logger) as Lang.Boolean {
    var peak = new HrPeak();
    peak.sampleTail(150, 0);
    peak.sampleTail(160, HeartRate.TAIL_SECONDS);
    peak.sampleTail(200, HeartRate.TAIL_SECONDS + 1);

    logger.debug("tail peak: " + peak.peak().toString());
    return peak.peak() == 160;
}

// The simulator has no strap, so this asserts the shape rather than a value: the
// read must answer null instead of throwing mid-set.
(:test)
function testHeartRateReadIsNullable(logger) as Lang.Boolean {
    var hr = HeartRate.read();
    logger.debug("heart rate: " + (hr == null ? "null" : hr.toString()));
    return hr == null || (hr > 0 && hr < 260);
}
