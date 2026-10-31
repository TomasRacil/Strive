using Toybox.Test;
using Toybox.Lang;

// Scratch probes for language behaviour the rest of the app depends on. These
// are not shipped behaviour tests: they exist to answer "what does this firmware
// actually do" with the simulator rather than with a guess.

(:test)
function probeStringEquality(logger) as Lang.Boolean {
    var a = "bench";
    var b = "bench";
    logger.debug("literal == literal: " + (a == b).toString());
    logger.debug("literal equals: " + a.equals(b).toString());

    var joined = "bench" + "_press";
    var built = "bench_press";
    logger.debug("concat == literal: " + (joined == built).toString());
    logger.debug("concat equals literal: " + joined.equals(built).toString());

    var parts = Text.split("a|b|c", "|");
    logger.debug("split[0] == a: " + (parts[0] == "a").toString());
    logger.debug("split[0] equals a: " + parts[0].equals("a").toString());
    logger.debug("split[0] len: " + parts[0].length().toString());

    return true;
}

(:test)
function probeStringFind(logger) as Lang.Boolean {
    var text = "a|b|c";

    try {
        logger.debug("find(needle): " + text.find("|").toString());
    } catch (e) {
        logger.debug("find(needle) threw: " + e.getErrorMessage());
    }

    try {
        logger.debug("Text.indexOf from 0: " + Text.indexOf(text, "|", 0).toString());
        logger.debug("Text.indexOf from 2: " + Text.indexOf(text, "|", 2).toString());
        logger.debug("Text.indexOf missing: " + Text.indexOf(text, "z", 0));
    } catch (e) {
        logger.debug("Text.indexOf threw: " + e.getErrorMessage());
    }

    return true;
}

(:test)
function probeNumberParse(logger) as Lang.Boolean {
    var whole = "100".toNumber();
    logger.debug("toNumber 100: " + (whole == null ? "null" : whole.toString()));

    var dec = "82.5".toNumber();
    logger.debug("toNumber 82.5: " + (dec == null ? "null" : dec.toString()));

    var comma = "82,5".toNumber();
    logger.debug("toNumber 82,5: " + (comma == null ? "null" : comma.toString()));

    return true;
}

(:test)
function probeCharCompare(logger) as Lang.Boolean {
    var chars = "a|b".toCharArray();
    logger.debug("chars: " + chars.size().toString());
    logger.debug("chars[1] == '|': " + (chars[1] == '|').toString());
    return true;
}

(:test)
function probeSensorInfo(logger) as Lang.Boolean {
    // Does a watch-app context expose heart rate at all? null means no.
    try {
        var info = Toybox.Sensor.getInfo();
        logger.debug("sensor info: " + (info == null ? "null" : "present"));
        if (info != null) {
            logger.debug("heartRate: " + (info.heartRate == null ? "null" : info.heartRate.toString()));
        }
    } catch (e) {
        logger.debug("Sensor.getInfo threw: " + e.getErrorMessage());
    }
    return true;
}
