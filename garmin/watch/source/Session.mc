using Toybox.Application as App;
using Toybox.Lang;
using Toybox.Time as Time;

// The in-flight session and the log of what was actually lifted.
//
// Every set is written to Storage the moment it is logged, so a killed app or a
// flat battery resumes where it left off instead of losing the workout. This is
// the watch half of the same idea as the web app's crash-safe session.
//
// Storage reliably holds primitives only, so the log is a delimited string:
//
//     "bench_press|1000|8|1;squats|1200|6|3;"
//
// The weight is kept in tenths of a kilogram as an integer. Float formatting
// follows the device locale, so a Czech watch would write "100,5" and the value
// would not parse back on the phone.
//
// The fourth field is the RIR the user confirmed on the set sheet. A set with no
// RIR - every set the build before the sheet wrote, and any set the user left
// alone - is three fields, so there is exactly one encoding of "unknown" and no
// reader has to guess whether a missing number meant 2.
module Session {

    const ENTRY_SEPARATOR = ";";
    const FIELD_SEPARATOR = "|";

    function startKey() {
        return "sess_start";
    }

    function indexKey() {
        return "sess_index";
    }

    function logKey() {
        return "sess_log";
    }

    // The id the phone upserts by. Generated when the session starts, so a set
    // logged offline and delivered a day later still lands in the right session.
    function sidKey() {
        return "sess_sid";
    }

    // ---- lifecycle -------------------------------------------------------

    function active() as Lang.Boolean {
        var started = App.Storage.getValue(startKey());
        return started != null && started > 0;
    }

    function startedAt() {
        var value = App.Storage.getValue(startKey());
        if (value == null) {
            return 0;
        }
        return value;
    }

    function elapsedSeconds() {
        if (!active()) {
            return 0;
        }
        var elapsed = Time.now().value() - startedAt();
        return elapsed > 0 ? elapsed : 0;
    }

    function start() as Void {
        App.Storage.setValue(startKey(), Time.now().value());
        App.Storage.setValue(indexKey(), 0);
        App.Storage.setValue(logKey(), "");
        App.Storage.setValue(sidKey(), Bus.newId());
    }

    function sid() as Lang.String {
        var value = App.Storage.getValue(sidKey());
        return value == null ? "" : value;
    }

    // Clears the session. The log is read out first: end() must not be the
    // thing that loses the workout.
    function end() as Void {
        App.Storage.setValue(startKey(), 0);
        App.Storage.setValue(indexKey(), 0);
        App.Storage.setValue(logKey(), "");
        App.Storage.setValue(sidKey(), "");
    }

    // ---- position in the exercise list -----------------------------------

    function index() as Lang.Number {
        var value = App.Storage.getValue(indexKey());
        if (value == null) {
            return 0;
        }
        return value;
    }

    function setIndex(value) as Void {
        App.Storage.setValue(indexKey(), value);
    }

    // ---- the set log -----------------------------------------------------

    function logText() as Lang.String {
        var text = App.Storage.getValue(logKey());
        if (text == null) {
            return "";
        }
        return text;
    }

    // A set logged without an RIR. Kept because the training screen has no RIR
    // input yet and writes the three-field line the old build wrote.
    function addSet(id, weight, reps) as Void {
        append(id, weight, reps, null);
    }

    // The sheet's shape: the RIR the user confirmed along with the set.
    function addSetWithRir(id, weight, reps, rir) as Void {
        append(id, weight, reps, rir);
    }

    function append(id, weight, reps, rir) as Void {
        // +0.5 before truncating: 2.5 * 10.0 is not exactly 25.0 in binary.
        var tenths = (weight * 10.0 + 0.5).toNumber();
        var line = id + FIELD_SEPARATOR + tenths.toString() + FIELD_SEPARATOR + reps.toString();
        if (rir != null) {
            line = line + FIELD_SEPARATOR + rir.toString();
        }
        App.Storage.setValue(logKey(), logText() + line + ENTRY_SEPARATOR);
    }

    // Toybox.StringUtil has no split(), so this walks the string with find().
    function split(text, separator) {
        return Text.split(text, separator);
    }

    function entries() as Lang.Array<Lang.Dictionary> {
        var out = [] as Lang.Array<Lang.Dictionary>;
        var chunks = Text.split(logText(), ENTRY_SEPARATOR);

        for (var i = 0; i < chunks.size(); i++) {
            var parts = Text.split(chunks[i], FIELD_SEPARATOR);
            // Three fields is what the build before RIR wrote and still what a
            // set with no RIR writes; four is the sheet's shape. Anything else
            // is a torn line and is skipped, as before.
            if (parts.size() != 3 && parts.size() != 4) {
                continue;
            }

            // toNumber() returns null for anything it cannot read, and dividing
            // that would throw inside the draw path and freeze the screen on its
            // last frame - which reads as "the button does nothing".
            var tenths = parts[1].toNumber();
            var reps = parts[2].toNumber();
            if (tenths == null || reps == null) {
                continue;
            }

            // An old entry has no RIR, and an unreadable one is no better: null
            // means unknown. Dropping the set instead would lose work to a bad
            // digit, which is the one thing the log exists to prevent.
            var rir = null;
            if (parts.size() == 4) {
                rir = parts[3].toNumber();
            }

            out.add({
                :id => parts[0],
                :weight => tenths / 10.0,
                :reps => reps,
                :rir => rir
            });
        }

        return out;
    }

    function setsFor(id) as Lang.Number {
        var count = 0;
        var all = entries();
        for (var i = 0; i < all.size(); i++) {
            if (Text.same(all[i][:id], id)) {
                count += 1;
            }
        }
        return count;
    }

    // Tonnage: the same number the phone's history shows, so the two agree.
    function volume() as Lang.Float {
        var total = 0.0;
        var all = entries();
        for (var i = 0; i < all.size(); i++) {
            total = total + (all[i][:weight] * all[i][:reps]);
        }
        return total;
    }

    function setCount() as Lang.Number {
        return entries().size();
    }

    // What the summary screen draws and what gets pushed to the phone.
    function summary() as Lang.Dictionary {
        return {
            :sets => setCount(),
            :volume => volume(),
            :duration => elapsedSeconds(),
            :log => logText()
        };
    }
}
