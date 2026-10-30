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
        var parts = [] as Lang.Array<Lang.String>;
        var start = 0;
        var index = text.find(separator, start);

        while (index != null) {
            parts.add(text.substring(start, index));
            start = index + separator.length();
            index = text.find(separator, start);
        }
        parts.add(text.substring(start, text.length()));

        return parts;
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
            App.Storage.setValue(key(parts[0]), parts[1].toFloat());
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
}
