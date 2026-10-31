using Toybox.Application as App;
using Toybox.Lang;

// Everything the phone owns that the watch needs while it is offline.
//
// Storage holds primitives only, so each snapshot is kept as the JSON string it
// arrived as, under a version stamp. Parsing happens once per version and is
// cached, because the screen asks for the current exercise on every frame.
//
// `lib`, `plan` and `hist` are snapshots: applying one replaces the previous one
// wholesale. A version that is not newer is still applied - the phone is
// authoritative - and the stamp only tells the UI whether anything changed.
module Library {

    const LIB_KEY = "lib_json";
    const LIB_V = "lib_v";
    const PLAN_KEY = "plan_json";
    const PLAN_V = "plan_v";
    const PLAN_WID = "plan_wid";
    const PLAN_NAME = "plan_name";
    const HIST_KEY = "hist_json";
    const REC_KEY = "rec_json";
    const PROFILE_PREFIX = "pr_";

    // Defaults for a library entry the phone left sparse. 2.5 kg is the smallest
    // plate pair in the gym this is written for.
    const DEFAULT_INC = 2.5;
    const DEFAULT_REST = 90;
    const DEFAULT_REPS = 8;

    // Parsed snapshots, kept across calls. A class rather than module variables
    // because static class variables are what the rest of the app already uses.
    class Cache {
        static var lib = null;
        static var libV = -1;
        static var plan = null;
        static var planV = -1;
    }

    // ---- applying --------------------------------------------------------

    function apply(kind, payload) as Lang.Boolean {
        if (payload == null || !(payload instanceof Lang.Dictionary)) {
            return false;
        }

        if (Text.same(kind, "lib")) {
            return applyLib(payload);
        }
        if (Text.same(kind, "plan")) {
            return applyPlan(payload);
        }
        if (Text.same(kind, "hist")) {
            return applyHist(payload);
        }
        if (Text.same(kind, "rec")) {
            return applyRec(payload);
        }
        if (Text.same(kind, "profile")) {
            return applyProfile(payload);
        }
        return false;
    }

    function versionOf(payload) {
        var value = payload["v"];
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            return value.toNumber();
        }
        if (value instanceof Lang.Number) {
            return value;
        }
        return 0;
    }

    function applyLib(payload) as Lang.Boolean {
        var list = payload["ex"];
        if (list == null || !(list instanceof Lang.Array)) {
            return false;
        }

        App.Storage.setValue(LIB_KEY, Json.write(payload));
        App.Storage.setValue(LIB_V, versionOf(payload));
        Cache.lib = payload;
        Cache.libV = versionOf(payload);
        return true;
    }

    // An empty item list clears the plan. Nothing here invents a weight: the plan
    // carries sets and rep ranges, and the load comes from `rec` or `hist`.
    function applyPlan(payload) as Lang.Boolean {
        var items = payload["items"];
        if (items == null || !(items instanceof Lang.Array)) {
            return false;
        }

        var wid = payload["wid"];
        var name = payload["name"];

        App.Storage.setValue(PLAN_KEY, Json.write(payload));
        App.Storage.setValue(PLAN_V, versionOf(payload));
        App.Storage.setValue(PLAN_WID, wid == null ? "" : wid.toString());
        App.Storage.setValue(PLAN_NAME, name == null ? "" : name.toString());
        Cache.plan = payload;
        Cache.planV = versionOf(payload);

        // The training screen still reads Plan.weightFor(), so a planned weight
        // is mirrored there when one is already known. The screen itself is
        // unchanged in this step on purpose.
        for (var i = 0; i < items.size(); i++) {
            var item = items[i];
            if (item == null || !(item instanceof Lang.Dictionary)) {
                continue;
            }
            var ex = item["ex"];
            if (ex == null) {
                continue;
            }
            var known = weightFor(ex.toString());
            if (known != null) {
                Plan.setWeight(ex.toString(), known);
            }
        }
        return true;
    }

    function applyRec(payload) as Lang.Boolean {
        var items = payload["items"];
        if (items == null || !(items instanceof Lang.Array)) {
            return false;
        }

        App.Storage.setValue(REC_KEY, Json.write(payload));

        // A recommendation is the one message that carries a load, so it is what
        // the training screen shows.
        for (var i = 0; i < items.size(); i++) {
            var item = items[i];
            if (item == null || !(item instanceof Lang.Dictionary)) {
                continue;
            }
            var ex = item["ex"];
            var weight = numberOr(item["w"], null);
            if (ex == null || weight == null) {
                continue;
            }
            Plan.setWeight(ex.toString(), weight);
        }
        return true;
    }

    function applyHist(payload) as Lang.Boolean {
        var ex = payload["ex"];
        if (ex == null || !(ex instanceof Lang.Dictionary)) {
            return false;
        }

        App.Storage.setValue(HIST_KEY, Json.write(payload));

        // History only fills in a load the phone has not recommended. It never
        // overwrites one: the recommendation already accounts for the history.
        var keys = ex.keys();
        for (var i = 0; i < keys.size(); i++) {
            var id = keys[i].toString();
            if (Plan.weightFor(id) != null) {
                continue;
            }
            var weight = historyWeight(ex[keys[i]]);
            if (weight != null) {
                Plan.setWeight(id, weight);
            }
        }
        return true;
    }

    function applyProfile(payload) as Lang.Boolean {
        var keys = payload.keys();
        for (var i = 0; i < keys.size(); i++) {
            var value = payload[keys[i]];
            // Storage is reliable for primitives only; a nested object here is a
            // phone bug and must not poison the rest of the profile.
            if (value == null || value instanceof Lang.Array || value instanceof Lang.Dictionary) {
                continue;
            }
            App.Storage.setValue(PROFILE_PREFIX + keys[i].toString(), value);
        }
        return true;
    }

    // ---- lookups ---------------------------------------------------------

    function lib() {
        var stamp = App.Storage.getValue(LIB_V);
        var version = stamp == null ? -1 : stamp;

        if (Cache.lib != null && Cache.libV == version) {
            return Cache.lib;
        }

        var stored = App.Storage.getValue(LIB_KEY);
        if (stored == null) {
            return null;
        }

        var parsed = Json.parse(stored);
        if (parsed == null || !(parsed instanceof Lang.Dictionary)) {
            return null;
        }

        Cache.lib = parsed;
        Cache.libV = version;
        return parsed;
    }

    function libVersion() {
        var value = App.Storage.getValue(LIB_V);
        return value == null ? 0 : value;
    }

    function planVersion() {
        var value = App.Storage.getValue(PLAN_V);
        return value == null ? 0 : value;
    }

    function planWid() {
        var value = App.Storage.getValue(PLAN_WID);
        return value == null ? "" : value;
    }

    function planName() {
        var value = App.Storage.getValue(PLAN_NAME);
        return value == null ? "" : value;
    }

    // The ordered exercise list, normalised so a caller does not care whether it
    // came from the phone or from the compiled-in fallback.
    function exercises() {
        var snapshot = lib();
        var out = [] as Lang.Array;

        if (snapshot == null) {
            var compiled = Exercises.list();
            for (var i = 0; i < compiled.size(); i++) {
                var entry = compiled[i];
                out.add({
                    "id" => entry[:id],
                    "name" => entry[:name],
                    "short" => entry[:name],
                    "reps" => entry[:reps],
                    "lo" => entry[:reps],
                    "hi" => entry[:reps],
                    "rest" => entry[:rest],
                    "inc" => DEFAULT_INC,
                    "minW" => 0.0,
                    "mus" => null
                });
            }
            return out;
        }

        var list = snapshot["ex"];
        if (list == null || !(list instanceof Lang.Array)) {
            return out;
        }

        for (var i = 0; i < list.size(); i++) {
            var item = list[i];
            if (item == null || !(item instanceof Lang.Dictionary)) {
                continue;
            }
            var name = item["name"];
            var short = item["short"];
            var hi = numberOr(item["hi"], DEFAULT_REPS);
            out.add({
                "id" => item["id"] == null ? "" : item["id"].toString(),
                "name" => name == null ? "" : name.toString(),
                "short" => short == null ? (name == null ? "" : name.toString()) : short.toString(),
                "reps" => hi,
                "lo" => numberOr(item["lo"], hi),
                "hi" => hi,
                "rest" => numberOr(item["rest"], DEFAULT_REST),
                "inc" => numberOr(item["inc"], DEFAULT_INC),
                "minW" => numberOr(item["minW"], 0.0),
                "mus" => item["mus"]
            });
        }
        return out;
    }

    function exerciseById(id) {
        var list = exercises();
        for (var i = 0; i < list.size(); i++) {
            if (Text.same(list[i]["id"], id)) {
                return list[i];
            }
        }
        return null;
    }

    function restFor(id) {
        var exercise = exerciseById(id);
        if (exercise == null) {
            return DEFAULT_REST;
        }
        return exercise["rest"];
    }

    function plan() {
        var stamp = App.Storage.getValue(PLAN_V);
        var version = stamp == null ? -1 : stamp;

        if (Cache.plan != null && Cache.planV == version) {
            return Cache.plan;
        }

        var stored = App.Storage.getValue(PLAN_KEY);
        if (stored == null) {
            return null;
        }

        var parsed = Json.parse(stored);
        if (parsed == null || !(parsed instanceof Lang.Dictionary)) {
            return null;
        }

        Cache.plan = parsed;
        Cache.planV = version;
        return parsed;
    }

    function planItems() {
        var snapshot = plan();
        if (snapshot == null) {
            return [] as Lang.Array;
        }
        var items = snapshot["items"];
        if (items == null || !(items instanceof Lang.Array)) {
            return [] as Lang.Array;
        }
        return items;
    }

    function profile(key, fallback) {
        var value = App.Storage.getValue(PROFILE_PREFIX + key);
        return value == null ? fallback : value;
    }

    // The load the phone last suggested for an exercise, from the recommendation
    // if there is one, else the newest set in the history.
    function weightFor(id) {
        var recommended = recommendedWeight(id);
        if (recommended != null) {
            return recommended;
        }
        return historyWeightFor(id);
    }

    function recommendedWeight(id) {
        var stored = App.Storage.getValue(REC_KEY);
        if (stored == null) {
            return null;
        }

        var parsed = Json.parse(stored);
        if (parsed == null || !(parsed instanceof Lang.Dictionary)) {
            return null;
        }

        var items = parsed["items"];
        if (items == null || !(items instanceof Lang.Array)) {
            return null;
        }

        for (var i = 0; i < items.size(); i++) {
            var item = items[i];
            if (item == null || !(item instanceof Lang.Dictionary)) {
                continue;
            }
            if (Text.same(item["ex"], id)) {
                return numberOr(item["w"], null);
            }
        }
        return null;
    }

    function historyWeightFor(id) {
        var stored = App.Storage.getValue(HIST_KEY);
        if (stored == null) {
            return null;
        }

        var parsed = Json.parse(stored);
        if (parsed == null || !(parsed instanceof Lang.Dictionary)) {
            return null;
        }

        var ex = parsed["ex"];
        if (ex == null || !(ex instanceof Lang.Dictionary)) {
            return null;
        }
        return historyWeight(ex[id]);
    }

    // The history as Engine's timed-set shape, so the watch can rank and advise
    // offline. The phone sends age in days because the two clocks are not
    // synchronised (docs/watch-protocol.md), so the timestamp is reconstructed
    // from the watch's own clock and the age the phone measured.
    //
    // A set whose fields do not parse is skipped, never guessed at: one bad row
    // must not move a recommendation.
    function historySets(now) as Lang.Array {
        var out = [] as Lang.Array;
        var stored = App.Storage.getValue(HIST_KEY);
        if (stored == null) {
            return out;
        }

        var parsed = Json.parse(stored);
        if (parsed == null || !(parsed instanceof Lang.Dictionary)) {
            return out;
        }

        var ex = parsed["ex"];
        if (ex == null || !(ex instanceof Lang.Dictionary)) {
            return out;
        }

        var ids = ex.keys();
        for (var i = 0; i < ids.size(); i++) {
            var id = ids[i].toString();
            var sets = ex[ids[i]];
            if (sets == null || !(sets instanceof Lang.Array)) {
                continue;
            }

            for (var k = 0; k < sets.size(); k++) {
                var set = sets[k];
                if (set == null || !(set instanceof Lang.Array) || set.size() < 4) {
                    continue;
                }

                var weight = numberOr(set[0], null);
                var reps = wholeOr(set[1], null);
                var age = numberOr(set[3], null);
                if (weight == null || reps == null || age == null) {
                    continue;
                }

                // -1 is the phone's "no RIR recorded", the same convention the
                // watch writes on the way out.
                var rir = wholeOr(set[2], -1);
                out.add({
                    :id => id,
                    :weight => weight,
                    :reps => reps,
                    :rir => rir < 0 ? null : rir,
                    :ts => (now - age * 86400.0).toNumber()
                });
            }
        }
        return out;
    }

    // The loads the phone recommended, id -> kg, parsed once so the picker does
    // not re-parse the JSON for every row it draws.
    function recWeights() as Lang.Dictionary {
        var out = {};
        var stored = App.Storage.getValue(REC_KEY);
        if (stored == null) {
            return out;
        }

        var parsed = Json.parse(stored);
        if (parsed == null || !(parsed instanceof Lang.Dictionary)) {
            return out;
        }

        var items = parsed["items"];
        if (items == null || !(items instanceof Lang.Array)) {
            return out;
        }

        for (var i = 0; i < items.size(); i++) {
            var item = items[i];
            if (item == null || !(item instanceof Lang.Dictionary)) {
                continue;
            }
            var ex = item["ex"];
            var weight = numberOr(item["w"], null);
            if (ex == null || weight == null) {
                continue;
            }
            out[ex.toString()] = weight;
        }
        return out;
    }

    function wholeOr(value, fallback) {
        var asFloat = numberOr(value, null);
        return asFloat == null ? fallback : asFloat.toNumber();
    }

    // [[w, reps, rir, ageDays], ...] - the newest set is the one with the
    // smallest age, which is the only ordering the payload promises.
    function historyWeight(sets) {
        if (sets == null || !(sets instanceof Lang.Array) || sets.size() == 0) {
            return null;
        }

        var best = null;
        var bestAge = 0;

        for (var i = 0; i < sets.size(); i++) {
            var set = sets[i];
            if (set == null || !(set instanceof Lang.Array) || set.size() < 4) {
                continue;
            }
            var age = numberOr(set[3], null);
            if (age == null) {
                continue;
            }
            if (best == null || age < bestAge) {
                best = set;
                bestAge = age;
            }
        }

        if (best == null) {
            return null;
        }
        return numberOr(best[0], null);
    }

    function numberOr(value, fallback) {
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            return value;
        }
        if (value instanceof Lang.Number) {
            return value.toFloat();
        }
        return fallback;
    }
}
