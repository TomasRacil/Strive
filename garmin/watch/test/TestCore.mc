using Toybox.Test;
using Toybox.Lang;

// Unit tests for the pure logic the training screen depends on. Run with:
//
//   java -jar <sdk>/bin/monkeybrains.jar -f test.jungle -d fenix847mm \
//        -o build/Strive-test.prg -y keys/developer_key.der --unit-test
//   <sdk>/bin/monkeydo.bat build/Strive-test.prg fenix847mm
//
// These cover parsing, not radio behaviour: BLE needs a real watch and a real
// phone, so nothing here claims anything about the link.

(:test)
function testSplit(logger) as Lang.Boolean {
    var parts = Text.split("a|b|c", "|");
    logger.debug("split: " + parts.size().toString());
    return parts.size() == 3 && Text.same(parts[0], "a") && Text.same(parts[2], "c");
}

(:test)
function testSplitKeepsEmptyTail(logger) as Lang.Boolean {
    var parts = Text.split("a;b;", ";");
    logger.debug("split tail: " + parts.size().toString());
    return parts.size() == 3 && parts[2].length() == 0;
}

(:test)
function testIndexOfFromOffset(logger) as Lang.Boolean {
    var text = "a|b|c";
    var first = Text.indexOf(text, "|", 0);
    var second = Text.indexOf(text, "|", first + 1);
    logger.debug("indexes: " + first.toString() + "," + second.toString());
    return first == 1 && second == 3;
}

(:test)
function testIndexOfMissing(logger) as Lang.Boolean {
    return Text.indexOf("abc", "|", 0) == null;
}

(:test)
function testSessionLogRoundTrip(logger) as Lang.Boolean {
    Session.start();
    Session.addSet("bench_press", 100.0, 8);
    Session.addSet("bench_press", 102.5, 6);
    Session.addSet("squats", 120.0, 5);

    var log = Session.logText();
    logger.debug("log: " + log);

    var entries = Session.entries();
    var ok = entries.size() == 3 &&
        Session.setsFor("bench_press") == 2 &&
        Session.setsFor("squats") == 1;

    // 100*8 + 102.5*6 + 120*5 = 800 + 615 + 600
    var volume = Session.volume();
    logger.debug("volume: " + volume.format("%.1f"));
    ok = ok && volume > 2014.9 && volume < 2015.1;

    Session.end();
    ok = ok && !Session.active() && Session.setCount() == 0;
    return ok;
}

// 2.5 * 10 is not exactly 25.0 in binary; without rounding the tenths value
// truncates to 24 and the phone imports 2.4 kg.
(:test)
function testTenthsRounding(logger) as Lang.Boolean {
    Session.start();
    Session.addSet("curls", 2.5, 10);
    var text = Session.logText();
    Session.end();
    logger.debug("tenths: " + text);
    return Text.same(text, "curls|25|10;");
}

(:test)
function testPlanJson(logger) as Lang.Boolean {
    Plan.replaceFromJson("{\"bench_press\":100.0,\"squats\":82.5}");
    var bench = Plan.weightFor("bench_press");
    var squats = Plan.weightFor("squats");
    logger.debug("plan: " + bench.toString() + "," + squats.toString());
    return bench != null && bench > 99.9 && bench < 100.1 &&
        squats != null && squats > 82.4 && squats < 82.6;
}

(:test)
function testPlanJsonIgnoresJunk(logger) as Lang.Boolean {
    Plan.replaceFromJson("{}");
    Plan.replaceFromJson("");
    return true;
}

(:test)
function testClockFormatting(logger) as Lang.Boolean {
    return Text.same(Text.clock(0), "0:00") && Text.same(Text.clock(65), "1:05") && Text.same(Text.clock(600), "10:00");
}
