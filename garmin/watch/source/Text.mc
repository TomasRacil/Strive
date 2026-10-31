using Toybox.Lang;

// String helpers.
//
// The SDK already provides String.split() (it takes a Char) and
// String.toCharArray(), so both are used here instead of slicing by index.
// Slicing with substring(i, i + 1) and comparing to a one-character String
// silently never matched on this firmware, and that one fault broke two
// unrelated features at once: the plan parser saw no id:weight pairs, and logged
// sets were discarded because id|weight|reps never split.
module Text {

    function split(text, separator) as Lang.Array<Lang.String> {
        if (text == null || text.length() == 0) {
            return [] as Lang.Array<Lang.String>;
        }

        var chars = separator.toCharArray();
        if (chars.size() == 0) {
            return [text];
        }

        return text.split(chars[0], null);
    }

    // String equality on this firmware: `a == b` is false for two equal Strings,
    // even two literals, while `.equals()` is true. Every id comparison in the
    // app goes through here, because a silent false reads as "no sets logged".
    function same(a, b) as Lang.Boolean {
        if (a == null || b == null) {
            return false;
        }
        return a.equals(b);
    }

    // Index of the first occurrence of needle at or after `from`, or null.
    //
    // String.find() takes exactly one argument on this firmware — passing a
    // start offset fails to compile — so the search is re-rooted by slicing.
    function indexOf(text, needle, from) as Lang.Number or Null {
        if (text == null) {
            return null;
        }

        var start = from == null || from < 0 ? 0 : from;
        if (start >= text.length()) {
            return null;
        }

        var found = (start == 0 ? text : text.substring(start, text.length())).find(needle);
        if (found == null) {
            return null;
        }
        return found + start;
    }

    // A countdown or a duration: "1:42", "10:00". Minutes are not padded -
    // "0:09" is a rest that has just started, and the single digit is the cue.
    function clock(seconds) as Lang.String {
        var value = seconds == null || seconds < 0 ? 0 : seconds;
        var minutes = value / 60;
        var secs = value % 60;
        var pad = secs < 10 ? "0" : "";
        return minutes.toString() + ":" + pad + secs.toString();
    }

    // A name cut to what a row can hold. A round face loses the ends of a long
    // exercise name, and "Overhead Pre" reads as a truncation where a wrapped
    // name reads as a second row the app forgot to draw.
    function fit(text, max) as Lang.String {
        if (text == null) {
            return "";
        }
        var value = text.toString();
        return value.length() > max ? value.substring(0, max) : value;
    }

    // Drops the surrounding braces of a JSON object body.
    function trimBraces(text) as Lang.String {
        var chars = text.toCharArray();
        var start = 0;
        var end = chars.size();

        while (start < end && (chars[start] == '{' || chars[start] == ' ')) {
            start += 1;
        }
        while (end > start && (chars[end - 1] == '}' || chars[end - 1] == ' ')) {
            end -= 1;
        }

        return text.substring(start, end);
    }

    // Strips JSON quoting and whitespace from one field.
    function clean(text) as Lang.String {
        var chars = text.toCharArray();
        var start = 0;
        var end = chars.size();

        while (start < end && (chars[start] == '"' || chars[start] == ' ' || chars[start] == '{')) {
            start += 1;
        }
        while (end > start && (chars[end - 1] == '"' || chars[end - 1] == ' ' || chars[end - 1] == '}')) {
            end -= 1;
        }

        return text.substring(start, end);
    }

    // ByteArray.toString() is documented only as "convert to a String", with no
    // promise that it decodes UTF-8. Building the string byte by byte is
    // unambiguous: a wrong decode here would leave every GATT read looking
    // successful while the payload never parsed.
    function fromBytes(bytes) as Lang.String {
        var out = "";
        var size = bytes.size();
        for (var i = 0; i < size; i++) {
            out = out + bytes[i].toChar();
        }
        return out;
    }
}
