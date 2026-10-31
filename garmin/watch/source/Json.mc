using Toybox.Lang;

// A JSON reader and writer small enough to live on a watch.
//
// The SDK has no JSON library and the bus carries JSON in both directions, so
// this is the smallest thing that round-trips what the phone sends. Every
// failure path returns null instead of raising: an exception thrown inside
// onPhoneAppMessage kills the app, and one malformed message must not be able to
// do that.
module Json {

    // A `lib` snapshot nests four deep (object -> array -> object -> array).
    // Eight leaves room and still stops a hostile document from eating the stack.
    const MAX_DEPTH = 8;

    // The bus refuses bodies over 6000 code units, so anything longer than that
    // arrived broken; parsing it would only waste the watch's time.
    const MAX_INPUT = 6000;

    // Characters are compared by code point, never against a quoted literal. On
    // this firmware a single-quoted character is not a Char, so `chars[i] == '0'`
    // is silently false for every digit - the same trap that made every weight
    // parse as null in Plan.mc.
    const C_QUOTE = 34;
    const C_BACKSLASH = 92;
    const C_SLASH = 47;
    const C_OBRACE = 123;
    const C_CBRACE = 125;
    const C_OBRACKET = 91;
    const C_CBRACKET = 93;
    const C_COLON = 58;
    const C_COMMA = 44;
    const C_MINUS = 45;
    const C_PLUS = 43;
    const C_DOT = 46;
    const C_ZERO = 48;
    const C_NINE = 57;
    const C_LOWER_E = 101;
    const C_UPPER_E = 69;
    const C_SPACE = 32;
    const C_TAB = 9;
    const C_LF = 10;
    const C_CR = 13;

    const HEX_DIGITS = "0123456789abcdef";

    // ---- reading ---------------------------------------------------------

    // Returns the parsed document, or null for anything that is not one whole
    // well-formed JSON value. Numbers come back as Float, because the watch only
    // ever reads weights and counts and Float survives both.
    function parse(text) as Lang.Object or Null {
        if (text == null || text.length() == 0 || text.length() > MAX_INPUT) {
            return null;
        }

        var chars = text.toCharArray();
        var pair = readValue(text, chars, skipSpace(chars, 0), 0);
        if (pair == null) {
            return null;
        }

        // Anything but whitespace after the value means the document is not what
        // it claims to be. Half a message accepted as a whole is worse than none.
        if (skipSpace(chars, pair[1]) != chars.size()) {
            return null;
        }
        return pair[0];
    }

    function skipSpace(chars, pos) as Lang.Number {
        var i = pos;
        var size = chars.size();
        while (i < size) {
            var c = chars[i].toNumber();
            if (c != C_SPACE && c != C_TAB && c != C_LF && c != C_CR) {
                break;
            }
            i += 1;
        }
        return i;
    }

    function isDigit(c) as Lang.Boolean {
        return c >= C_ZERO && c <= C_NINE;
    }

    // Every reader returns [value, nextPos] so a failure (null) is distinct from
    // a JSON null, which is a legitimate value.
    function readValue(text, chars, pos, depth) as Lang.Array or Null {
        if (depth > MAX_DEPTH || pos >= chars.size()) {
            return null;
        }

        var c = chars[pos].toNumber();
        if (c == C_OBRACE) {
            return readObject(text, chars, pos + 1, depth + 1);
        }
        if (c == C_OBRACKET) {
            return readArray(text, chars, pos + 1, depth + 1);
        }
        if (c == C_QUOTE) {
            return readString(chars, pos + 1);
        }
        if (c == 116) { // t
            return readLiteral(chars, pos, "true", true);
        }
        if (c == 102) { // f
            return readLiteral(chars, pos, "false", false);
        }
        if (c == 110) { // n
            return readLiteral(chars, pos, "null", null);
        }
        if (c == C_MINUS || isDigit(c)) {
            return readNumber(text, chars, pos);
        }
        return null;
    }

    function readLiteral(chars, pos, word, value) as Lang.Array or Null {
        var size = chars.size();
        var end = pos + word.length();
        if (end > size) {
            return null;
        }

        var actual = "";
        for (var i = pos; i < end; i++) {
            actual = actual + chars[i].toString();
        }
        if (!Text.same(actual, word)) {
            return null;
        }
        return [value, end];
    }

    function readObject(text, chars, pos, depth) as Lang.Array or Null {
        var out = {} as Lang.Dictionary;
        var size = chars.size();
        var i = skipSpace(chars, pos);

        if (i < size && chars[i].toNumber() == C_CBRACE) {
            return [out, i + 1];
        }

        var done = false;
        while (!done) {
            i = skipSpace(chars, i);
            if (i >= size || chars[i].toNumber() != C_QUOTE) {
                return null;
            }

            var keyPair = readString(chars, i + 1);
            if (keyPair == null) {
                return null;
            }

            i = skipSpace(chars, keyPair[1]);
            if (i >= size || chars[i].toNumber() != C_COLON) {
                return null;
            }

            var valuePair = readValue(text, chars, skipSpace(chars, i + 1), depth);
            if (valuePair == null) {
                return null;
            }
            out[keyPair[0]] = valuePair[0];

            i = skipSpace(chars, valuePair[1]);
            if (i >= size) {
                return null;
            }

            var c = chars[i].toNumber();
            if (c == C_COMMA) {
                i += 1;
            } else if (c == C_CBRACE) {
                return [out, i + 1];
            } else {
                return null;
            }
        }
        return null;
    }

    function readArray(text, chars, pos, depth) as Lang.Array or Null {
        var out = [] as Lang.Array;
        var size = chars.size();
        var i = skipSpace(chars, pos);

        if (i < size && chars[i].toNumber() == C_CBRACKET) {
            return [out, i + 1];
        }

        var done = false;
        while (!done) {
            var valuePair = readValue(text, chars, skipSpace(chars, i), depth);
            if (valuePair == null) {
                return null;
            }
            out.add(valuePair[0]);

            i = skipSpace(chars, valuePair[1]);
            if (i >= size) {
                return null;
            }

            var c = chars[i].toNumber();
            if (c == C_COMMA) {
                i += 1;
            } else if (c == C_CBRACKET) {
                return [out, i + 1];
            } else {
                return null;
            }
        }
        return null;
    }

    function readString(chars, pos) as Lang.Array or Null {
        var out = "";
        var i = pos;
        var size = chars.size();

        while (i < size) {
            var c = chars[i].toNumber();
            if (c == C_QUOTE) {
                return [out, i + 1];
            }

            if (c != C_BACKSLASH) {
                out = out + chars[i].toString();
                i += 1;
                continue;
            }

            if (i + 1 >= size) {
                return null;
            }

            var e = chars[i + 1].toNumber();
            if (e == C_QUOTE) {
                out = out + "\"";
            } else if (e == C_BACKSLASH) {
                out = out + "\\";
            } else if (e == C_SLASH) {
                out = out + "/";
            } else if (e == 110) { // n
                out = out + C_LF.toChar();
            } else if (e == 114) { // r
                out = out + C_CR.toChar();
            } else if (e == 116) { // t
                out = out + C_TAB.toChar();
            } else if (e == 98) { // b
                out = out + 8.toChar();
            } else if (e == 102) { // f
                out = out + 12.toChar();
            } else if (e == 117) { // u
                // \uXXXX carries UTF-16 code units, so a surrogate pair arrives as
                // two escapes and is rebuilt as two units, which is what the
                // String holds anyway.
                if (i + 6 > size) {
                    return null;
                }
                var code = hexValue(chars, i + 2, 4);
                if (code == null) {
                    return null;
                }
                out = out + code.toChar();
                i += 4;
            } else {
                return null;
            }
            i += 2;
        }
        return null;
    }

    function hexValue(chars, pos, count) as Lang.Number or Null {
        var value = 0;
        for (var i = 0; i < count; i++) {
            var c = chars[pos + i].toNumber();
            var digit = -1;
            if (c >= C_ZERO && c <= C_NINE) {
                digit = c - C_ZERO;
            } else if (c >= 97 && c <= 102) {
                digit = c - 87;
            } else if (c >= 65 && c <= 70) {
                digit = c - 55;
            }
            if (digit < 0) {
                return null;
            }
            value = value * 16 + digit;
        }
        return value;
    }

    function readNumber(text, chars, pos) as Lang.Array or Null {
        var size = chars.size();
        var i = pos;

        if (i < size && chars[i].toNumber() == C_MINUS) {
            i += 1;
        }

        var digits = 0;
        while (i < size && isDigit(chars[i].toNumber())) {
            i += 1;
            digits += 1;
        }
        if (digits == 0) {
            return null;
        }

        if (i < size && chars[i].toNumber() == C_DOT) {
            i += 1;
            var fraction = 0;
            while (i < size && isDigit(chars[i].toNumber())) {
                i += 1;
                fraction += 1;
            }
            if (fraction == 0) {
                return null;
            }
        }

        if (i < size) {
            var e = chars[i].toNumber();
            if (e == C_LOWER_E || e == C_UPPER_E) {
                i += 1;
                if (i < size) {
                    var sign = chars[i].toNumber();
                    if (sign == C_PLUS || sign == C_MINUS) {
                        i += 1;
                    }
                }
                var exponentDigits = 0;
                while (i < size && isDigit(chars[i].toNumber())) {
                    i += 1;
                    exponentDigits += 1;
                }
                if (exponentDigits == 0) {
                    return null;
                }
            }
        }

        var value = numberFrom(text.substring(pos, i));
        if (value == null) {
            return null;
        }
        return [value, i];
    }

    // Hand-rolled because "82.5".toNumber() is 82: the SDK stops at the decimal
    // point, and a weight that silently loses its half-kilo is a wrong workout.
    function numberFrom(text) as Lang.Float or Null {
        var body = text;
        var negative = false;

        if (body.length() > 0 && body.substring(0, 1).equals("-")) {
            negative = true;
            body = body.substring(1, body.length());
        }

        var exponent = 0;
        var at = body.find("e");
        if (at == null) {
            at = body.find("E");
        }
        if (at != null) {
            var exponentText = body.substring(at + 1, body.length());
            var exponentValue = exponentText.toNumber();
            if (exponentValue == null) {
                return null;
            }
            exponent = exponentValue;
            body = body.substring(0, at);
        }

        var value = Plan.parseNumber(body);
        if (value == null) {
            return null;
        }

        for (var i = 0; i < exponent; i++) {
            value = value * 10.0;
        }
        for (var i = 0; i > exponent; i--) {
            value = value / 10.0;
        }

        return negative ? -value : value;
    }

    // ---- writing ---------------------------------------------------------

    // Writes only what the watch emits: dictionaries, arrays, strings, numbers,
    // booleans and null. Anything else is written as a string rather than
    // refused, so a wrong type in a payload cannot cost a session log.
    function write(value) as Lang.String {
        if (value == null) {
            return "null";
        }
        if (value instanceof Lang.String) {
            return quote(value);
        }
        if (value instanceof Lang.Boolean) {
            return value ? "true" : "false";
        }
        if (value instanceof Lang.Dictionary) {
            return writeObject(value);
        }
        if (value instanceof Lang.Array) {
            return writeArray(value);
        }
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            return fixed(value);
        }
        if (value instanceof Lang.Number) {
            return value.toString();
        }
        return quote(value.toString());
    }

    function writeObject(dict) as Lang.String {
        var out = "{";
        var keys = dict.keys();
        for (var i = 0; i < keys.size(); i++) {
            if (i > 0) {
                out = out + ",";
            }
            var key = keys[i];
            out = out + quote(key instanceof Lang.String ? key : key.toString());
            out = out + ":" + write(dict[key]);
        }
        return out + "}";
    }

    function writeArray(items) as Lang.String {
        var out = "[";
        for (var i = 0; i < items.size(); i++) {
            if (i > 0) {
                out = out + ",";
            }
            out = out + write(items[i]);
        }
        return out + "]";
    }

    function quote(text) as Lang.String {
        var out = "\"";
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i].toNumber();
            if (c == C_QUOTE) {
                out = out + "\\\"";
            } else if (c == C_BACKSLASH) {
                out = out + "\\\\";
            } else if (c == C_LF) {
                out = out + "\\n";
            } else if (c == C_CR) {
                out = out + "\\r";
            } else if (c == C_TAB) {
                out = out + "\\t";
            } else if (c < 32 || c > 126) {
                // Everything outside printable ASCII is escaped, so the wire stays
                // ASCII whatever the transport does with encodings, and a Czech
                // exercise name cannot arrive as mojibake.
                out = out + "\\u" + hex4(c);
            } else {
                out = out + chars[i].toString();
            }
        }
        return out + "\"";
    }

    // Two decimals, built from integers on purpose: Float.format() follows the
    // device locale, so a Czech watch would write "82,50" and the phone's parser
    // would reject it.
    function fixed(value) as Lang.String {
        var scale = 100;
        var scaled = (value * 100.0 + (value < 0 ? -0.5 : 0.5)).toNumber();
        var negative = scaled < 0;
        if (negative) {
            scaled = -scaled;
        }

        var whole = scaled / scale;
        var fraction = scaled % scale;
        var text = whole.toString() + "." + (fraction < 10 ? "0" : "") + fraction.toString();
        return negative ? "-" + text : text;
    }

    function hex4(value) as Lang.String {
        var n = value;
        if (n < 0) {
            n = -n;
        }
        var out = "";
        for (var i = 0; i < 4; i++) {
            var digit = n % 16;
            out = HEX_DIGITS.substring(digit, digit + 1) + out;
            n = n / 16;
        }
        return out;
    }
}
