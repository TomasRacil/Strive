using Toybox.Application as App;
using Toybox.Lang;

// Weights pushed from the phone, one entry per exercise id.
//
// Stored separately from Progress so a plan from the phone never overwrites the
// watch's own record of what was actually lifted.
//
// The phone sends a delimited string ("bench_press=27.5;squats=20.0") because
// sendMessage only reliably carries strings, booleans and numbers. A Dictionary
// is also accepted in case the transport ever delivers one.
module Plan {

    function key(id) {
        return "p_" + id;
    }

    // Toybox.StringUtil has no split(), so this walks the string with find().
    function splitOn(text, separator) {
        return Text.split(text, separator);
    }

    function replaceFromText(text) {
        if (text == null || text.length() == 0) {
            return;
        }

        var pairs = splitOn(text, ";");
        for (var i = 0; i < pairs.size(); i++) {
            var parts = splitOn(pairs[i], "=");
            if (parts.size() != 2) {
                continue;
            }
            App.Storage.setValue(key(parts[0]), parseNumber(parts[1]));
        }
    }

    function nameOf(rawKey) {
        if (rawKey instanceof Lang.String) {
            return rawKey;
        }
        return rawKey.toString();
    }

    function replaceFromDictionary(data) {
        if (data == null) {
            return;
        }

        var keys = data.keys();
        for (var i = 0; i < keys.size(); i++) {
            var rawKey = keys[i];
            var value = data[rawKey];

            if (value == null) {
                continue;
            }
            if (!(value instanceof Lang.Number) && !(value instanceof Lang.Float) && !(value instanceof Lang.Double)) {
                continue;
            }

            App.Storage.setValue(key(nameOf(rawKey)), value.toFloat());
        }
    }

    function weightFor(id) {
        return App.Storage.getValue(key(id));
    }

    // The framed bus carries the load in a `rec` message, which has nowhere else
    // to land; this keeps the existing screen reading from one place.
    function setWeight(id, kg) as Void {
        App.Storage.setValue(key(id), kg);
    }

    // Compact report of what the parser could see: pairs found, fields in the
    // first pair, cleaned id. "rd empty" says the result but not which stage
    // failed, and each stage needs a different fix.
    function parseDebug(text) as Lang.String {
        if (text == null || text.length() == 0) {
            return "e";
        }

        var pairs = splitOn(trimBraces(text), ",");
        var out = pairs.size().toString();

        if (pairs.size() > 0) {
            var parts = splitOn(pairs[0], ":");
            out = out + "/" + parts.size().toString();
            if (parts.size() > 0) {
                var id = clean(parts[0]);
                out = out + "/" + (id.length() > 5 ? id.substring(0, 5) : id);
            }
        }

        return out;
    }

    // The BLE path serves a small JSON object ({"bench_press":100.0}), not the
    // delimited string the companion message bus sends. Both land in the same
    // p_<id> keys, so the training screen never has to know which arrived.
    //
    // This parses a flat object of id -> number only: a nested or array payload
    // cannot fit in one ATT MTU anyway, so there is nothing else to parse yet.
    function replaceFromJson(text) as Lang.Number {
        if (text == null || text.length() == 0) {
            return 0;
        }

        var parsed = 0;
        var pairs = splitOn(trimBraces(text), ",");
        for (var i = 0; i < pairs.size(); i++) {
            var parts = splitOn(pairs[i], ":");
            if (parts.size() != 2) {
                continue;
            }

            var id = clean(parts[0]);
            var raw = clean(parts[1]);
            if (id.length() == 0 || raw.length() == 0) {
                continue;
            }

            var weight = parseNumber(raw);
            if (weight == null) {
                continue;
            }
            App.Storage.setValue(key(id), weight);
            parsed += 1;
        }

        return parsed;
    }

    // Built on Text.split() and String.toNumber(), both proven elsewhere in this
    // app, instead of walking characters. Char-literal comparison does not work
    // here: '0' is not a Char, so every digit tested as invalid and every weight
    // parsed as null.
    function parseNumber(text) as Lang.Float or Null {
        if (text == null || text.length() == 0) {
            return null;
        }

        var negative = false;
        var body = text;
        if (body.find("-") == 0) {
            negative = true;
            body = body.substring(1, body.length());
        }

        // Either separator: the phone writes "100.0", a Czech device would write
        // "100,0".
        var parts = Text.split(body, ".");
        if (parts.size() == 1) {
            parts = Text.split(body, ",");
        }
        if (parts.size() > 2) {
            return null;
        }

        var whole = parts[0].toNumber();
        if (whole == null) {
            return null;
        }

        var value = whole.toFloat();
        if (parts.size() == 2) {
            var fraction = parts[1].toNumber();
            if (fraction == null) {
                return null;
            }

            var scale = 1.0;
            for (var i = 0; i < parts[1].length(); i++) {
                scale = scale * 10.0;
            }
            value = value + fraction.toFloat() / scale;
        }

        return negative ? -value : value;
    }

    function trimBraces(text) {
        return Text.trimBraces(text);
    }

    function clean(text) {
        return Text.clean(text);
    }
}
