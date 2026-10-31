using Toybox.Test;
using Toybox.Lang;
using Toybox.Application as App;

// The set log with RIR.
//
// Two shapes have to coexist: the four-field line the set sheet writes, and the
// three-field line every entry on a watch that has not been reflashed yet still
// holds. An old entry must read back with an unknown RIR - not 2, which would
// claim the user answered a question that was never asked, and not a crash,
// which would take the whole log with it.

(:test)
function testRatedSetRoundTrip(logger) as Lang.Boolean {
    Session.start();
    Session.addSetWithRir("bench_press", 100.0, 8, 1);

    var log = Session.logText();
    var entries = Session.entries();
    logger.debug("rated log: " + log);

    var ok = Text.same(log, "bench_press|1000|8|1;") &&
        entries.size() == 1 &&
        entries[0][:rir] == 1 &&
        entries[0][:reps] == 8 &&
        entries[0][:weight] > 99.9 && entries[0][:weight] < 100.1;

    Session.end();
    return ok;
}

// Zero is a real answer - a set taken to failure - and must not be mistaken for
// a missing value on the way back in.
(:test)
function testRirZeroSurvivesTheRoundTrip(logger) as Lang.Boolean {
    Session.start();
    Session.addSetWithRir("squats", 120.0, 5, 0);

    var entries = Session.entries();
    var ok = entries.size() == 1 && entries[0][:rir] != null && entries[0][:rir] == 0;

    logger.debug("rir zero: " + (entries.size() == 0 ? "no entry" : entries[0][:rir].toString()));
    Session.end();
    return ok;
}

// Exactly what the build before the sheet wrote.
(:test)
function testOldThreeFieldEntryHasUnknownRir(logger) as Lang.Boolean {
    App.Storage.setValue(Session.logKey(), "bench_press|1000|8;squats|1200|6;");

    var entries = Session.entries();
    logger.debug("legacy entries: " + entries.size().toString());

    var ok = entries.size() == 2 &&
        entries[0][:rir] == null &&
        entries[1][:rir] == null &&
        entries[1][:reps] == 6 &&
        entries[1][:weight] > 119.9 && entries[1][:weight] < 120.1;

    App.Storage.setValue(Session.logKey(), "");
    return ok;
}

// A watch mid-upgrade holds both shapes at once, and neither may hide the other.
(:test)
function testMixedLogKeepsBothShapes(logger) as Lang.Boolean {
    App.Storage.setValue(Session.logKey(), "bench_press|1000|8;squats|1200|6|3;");

    var entries = Session.entries();
    var ok = entries.size() == 2 &&
        entries[0][:rir] == null &&
        entries[1][:rir] == 3;

    logger.debug("mixed: " + entries.size().toString());
    App.Storage.setValue(Session.logKey(), "");
    return ok;
}

// A fourth field that does not parse costs the field, not the set.
(:test)
function testUnreadableRirKeepsTheSet(logger) as Lang.Boolean {
    App.Storage.setValue(Session.logKey(), "curls|250|10|x;");

    var entries = Session.entries();
    var ok = entries.size() == 1 &&
        entries[0][:rir] == null &&
        entries[0][:reps] == 10;

    logger.debug("junk rir: " + entries.size().toString());
    App.Storage.setValue(Session.logKey(), "");
    return ok;
}

// The training screen still logs without an RIR, and that line has to be the
// legacy shape rather than a four-field line with a hole in it.
(:test)
function testAddSetWithoutRirWritesThreeFields(logger) as Lang.Boolean {
    Session.start();
    Session.addSet("curls", 2.5, 10);

    var log = Session.logText();
    var entries = Session.entries();
    var ok = Text.same(log, "curls|25|10;") && entries.size() == 1 && entries[0][:rir] == null;

    logger.debug("unrated log: " + log);
    Session.end();
    return ok;
}

// Volume and set counts read the same log and must not change shape with it.
(:test)
function testRatedSetsStillCount(logger) as Lang.Boolean {
    Session.start();
    Session.addSetWithRir("bench_press", 100.0, 8, 2);
    Session.addSetWithRir("bench_press", 100.0, 8, 2);
    Session.addSet("squats", 120.0, 5);

    var volume = Session.volume();
    var ok = Session.setCount() == 3 &&
        Session.setsFor("bench_press") == 2 &&
        volume > 2199.9 && volume < 2200.1;

    logger.debug("volume: " + volume.format("%.1f"));
    Session.end();
    return ok;
}
