using Toybox.Test;
using Toybox.Lang;

// Unit tests for the JSON reader and writer the bus depends on.
//
// There is no JSON library on the watch, so this parser is the thing standing
// between a phone message and a wrong weight on screen. Every test here is a
// shape the phone actually sends, or a shape it must refuse instead of
// half-parsing.

function near(value, expected) as Lang.Boolean {
    if (value == null) {
        return false;
    }
    var delta = value - expected;
    return delta < 0.0001 && delta > -0.0001;
}

(:test)
function testJsonParseObject(logger) as Lang.Boolean {
    var doc = Json.parse("{\"k\":\"plan\",\"n\":3,\"t\":1700000000}");

    if (doc == null || !(doc instanceof Lang.Dictionary)) {
        logger.debug("object did not parse");
        return false;
    }

    var ok = Text.same(doc["k"], "plan") && near(doc["n"], 3.0);
    logger.debug("k=" + doc["k"].toString() + " n=" + doc["n"].toString());
    return ok;
}

(:test)
function testJsonParseNested(logger) as Lang.Boolean {
    var text = "{\"v\":3,\"ex\":[{\"id\":\"bench_press\",\"mus\":[[\"chest\",0.8],[\"triceps\",0.3]],\"hi\":10}]}";
    var doc = Json.parse(text);

    if (doc == null || !(doc instanceof Lang.Dictionary)) {
        logger.debug("nested did not parse");
        return false;
    }

    var list = doc["ex"];
    if (list == null || !(list instanceof Lang.Array) || list.size() != 1) {
        logger.debug("ex is not a one-element array");
        return false;
    }

    var first = list[0];
    var mus = first["mus"];
    var ok = Text.same(first["id"], "bench_press") &&
        near(first["hi"], 10.0) &&
        mus instanceof Lang.Array &&
        mus.size() == 2 &&
        Text.same(mus[0][0], "chest") &&
        near(mus[0][1], 0.8);

    logger.debug("nested ok=" + ok.toString());
    return ok;
}

// "82.5".toNumber() is 82 on this firmware, so every decimal in the protocol has
// to survive the hand-rolled path.
(:test)
function testJsonDecimals(logger) as Lang.Boolean {
    var doc = Json.parse("{\"a\":82.5,\"b\":-1.25,\"c\":0.1}");

    if (doc == null) {
        logger.debug("decimals did not parse");
        return false;
    }

    var ok = near(doc["a"], 82.5) && near(doc["b"], -1.25) && near(doc["c"], 0.1);
    logger.debug("a=" + doc["a"].toString() + " b=" + doc["b"].toString());
    return ok;
}

(:test)
function testJsonExponent(logger) as Lang.Boolean {
    var doc = Json.parse("{\"a\":1e2,\"b\":2.5e-1}");
    return doc != null && near(doc["a"], 100.0) && near(doc["b"], 0.25);
}

(:test)
function testJsonEscapes(logger) as Lang.Boolean {
    // A Czech name arrives as \u escapes from the phone's JSON writer.
    var doc = Json.parse("{\"name\":\"P\\u0159edklon\",\"q\":\"a\\\"b\",\"n\":\"a\\nb\"}");

    if (doc == null) {
        logger.debug("escapes did not parse");
        return false;
    }

    var name = doc["name"];
    var ok = name != null &&
        name.length() == 8 &&
        name.substring(0, 1).toCharArray()[0].toNumber() == 80 &&
        name.substring(1, 2).toCharArray()[0].toNumber() == 345 &&
        Text.same(doc["q"], "a\"b") &&
        doc["n"].length() == 3;

    logger.debug("name length=" + name.length().toString());
    return ok;
}

(:test)
function testJsonMalformed(logger) as Lang.Boolean {
    var bad = [
        "",
        "{",
        "}",
        "{\"a\":}",
        "{\"a\" 1}",
        "{\"a\":1,}",
        "[1,]",
        "nul",
        "\"unterminated",
        "{\"a\":01x}",
        "{\"a\":1} trailing",
        "{\"a\":tru}"
    ];

    var ok = true;
    for (var i = 0; i < bad.size(); i++) {
        if (Json.parse(bad[i]) != null) {
            logger.debug("accepted bad input: " + bad[i]);
            ok = false;
        }
    }
    return ok;
}

// A lib snapshot nests object -> array -> object -> array. Ten levels is a
// broken or hostile document, and the parser must refuse it rather than recurse
// until the app dies.
(:test)
function testJsonDepthLimit(logger) as Lang.Boolean {
    var text = "";
    for (var i = 0; i < 10; i++) {
        text = text + "[";
    }
    text = text + "1";
    for (var i = 0; i < 10; i++) {
        text = text + "]";
    }

    var parsed = Json.parse(text);
    logger.debug("deep parse null=" + (parsed == null).toString());
    return parsed == null;
}

(:test)
function testJsonWriteRoundTrip(logger) as Lang.Boolean {
    var original = {
        "k" => "set",
        "n" => 7,
        "p" => {
            "ex" => "bench_press",
            "w" => 82.5,
            "reps" => 8,
            "ok" => true,
            "log" => [["squats", 120.0, 5, -1], ["curls", 20.0, 10, -1]]
        }
    };

    var text = Json.write(original);
    logger.debug("written: " + text);

    var back = Json.parse(text);
    if (back == null) {
        return false;
    }

    var ok = Text.same(back["k"], "set") &&
        near(back["n"], 7.0) &&
        Text.same(back["p"]["ex"], "bench_press") &&
        near(back["p"]["w"], 82.5) &&
        back["p"]["ok"] == true &&
        back["p"]["log"].size() == 2 &&
        near(back["p"]["log"][0][1], 120.0);

    return ok;
}

// Float.format() follows the device locale, so a Czech watch would write "82,50"
// and the phone would reject the body. The writer must not go through it.
(:test)
function testJsonWriteFloatIsLocaleFree(logger) as Lang.Boolean {
    var text = Json.fixed(82.5);
    logger.debug("fixed=" + text);
    return Text.same(text, "82.50") && Text.same(Json.fixed(-2.25), "-2.25");
}

(:test)
function testJsonQuotesNonAscii(logger) as Lang.Boolean {
    var text = Json.write("Předklon");
    logger.debug("quoted: " + text);

    // Escaped, so the wire stays ASCII whatever the transport does with
    // encodings, and the phone's parser turns it back into the same name.
    var ok = Text.same(text, "\"P\\u0159edklon\"");
    var back = Json.parse(text);
    return ok && Text.same(back, "Předklon");
}

// Documents the firmware fact the whole parser is built on: a quoted single
// character is not a Char here, so characters are compared by code point.
(:test)
function testCharCodes(logger) as Lang.Boolean {
    var chars = "0A{".toCharArray();
    logger.debug("codes: " + chars[0].toNumber().toString() + "," + chars[1].toNumber().toString());
    return chars[0].toNumber() == 48 && chars[1].toNumber() == 65 && chars[2].toNumber() == 123;
}
