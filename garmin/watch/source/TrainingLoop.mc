using Toybox.Lang;

// The free-training loop, as state only.
//
// Every screen in docs/watch-ux.md is one state of this machine, and the views
// only render it and forward a keypress. Keeping the loop free of Graphics,
// Storage and the clock is what makes the whole flow - pick, bank, rest,
// continue, finish - testable in the simulator, where a drawn screen is not.
//
// `now` is always passed in rather than read, for the same reason Engine does
// it: a test can pin the day the muscle load is computed for, and a session that
// crosses midnight is not a special case.
//
// The loop does not write the set log. Session.mc owns Storage and Bus.mc owns
// the wire, so bankSet() records the set in the loop's own tally and the caller
// (SetSheetView) writes it. That order is deliberate: the tally is what decides
// the next screen, and it must be right even if the write is what fails.

// Which screen the loop is on. A module rather than class constants because a
// class constant cannot be read from outside the class, and every view has to
// name the state it draws.
module LoopState {
    const HOME = 0;
    const PICK = 1;
    const EXERCISE = 2;
    const SET_SHEET = 3;
    const REST = 4;
    const NEXT_PROMPT = 5;
    const SUMMARY = 6;
}

// The two rows of the continue prompt.
module PromptRow {
    const SAME = 0;
    const DIFFERENT = 1;
}

class TrainingLoop {

    // The rest a library entry falls back to when it has none. 90 s is the
    // Library default and the middle of the 60-180 s range the app recommends.
    const DEFAULT_REST = 90;

    var state;

    // The catalogue and what the engine needs to advise on it. Both are passed
    // in, so a loop can be built for a test without a phone ever connecting.
    var specs;
    var history;
    var seeds;
    var bodyKg;

    // Loads the phone computed, id -> kg. The phone sees the whole history, so
    // its number wins over the watch's own when one is present.
    var phoneWeights;

    var exerciseId;
    var spec;
    var advice;
    var weight;
    var reps;
    var recommended;
    var done;

    // Sets banked this session, per exercise id. A lift picked twice in one
    // session continues its count instead of starting over.
    var sessionCounts;

    var sheet;
    var rest;
    var restAt;
    var peak;
    var bankedAt;

    var promptCursor;
    var lastSet;

    // `specs` are Engine specs ({:id, :name, :lo, :hi, :inc, :minW, :rest, :bw,
    // :pattern, :primary, :secondary}), `history` is Engine's timed-set shape,
    // `seeds` is the calibration result keyed by pattern, `bodyKg` may be null.
    function initialize(specList, historyList, seedMap, bodyWeight, weights) {
        specs = specList == null ? [] as Lang.Array : specList;
        history = historyList == null ? [] as Lang.Array : historyList;
        seeds = seedMap == null ? {} : seedMap;
        bodyKg = bodyWeight;
        phoneWeights = weights == null ? {} : weights;

        state = LoopState.HOME;
        exerciseId = null;
        spec = null;
        advice = null;
        weight = 0.0;
        reps = 0;
        recommended = 0;
        done = 0;
        sessionCounts = {};
        sheet = null;
        rest = null;
        restAt = 0;
        peak = new HrPeak();
        bankedAt = null;
        promptCursor = PromptRow.SAME;
        lastSet = null;
    }

    // A new library, history or recommendation arrived from the phone. The
    // catalogue is swapped in place rather than the loop rebuilt, because the
    // loop holds the session's tallies and the screen the user is looking at.
    // Advice is computed on pick(), so the next lift already uses the new data.
    function reload(newSpecs, newHistory, newSeeds, newBodyKg, newWeights) as Void {
        if (newSpecs != null) {
            specs = newSpecs;
        }
        if (newHistory != null) {
            history = newHistory;
        }
        if (newSeeds != null) {
            seeds = newSeeds;
        }
        if (newBodyKg != null) {
            bodyKg = newBodyKg;
        }
        if (newWeights != null) {
            phoneWeights = newWeights;
        }
    }

    // ---- transitions -----------------------------------------------------

    // Home -> the picker. Nothing else on Home is wired yet: workout mode and
    // calibration are a separate milestone, and a menu row that does nothing is
    // worse than a menu with one row.
    function start() as Void {
        state = LoopState.PICK;
    }

    // Picker -> the exercise. Everything the exercise screen and the sheet show
    // is decided here, once, so a redraw cannot disagree with the advice.
    function pick(id, now) as Void {
        exerciseId = id;
        spec = specFor(id);

        advice = adviceFor(spec, now);
        weight = advice[:weight];
        reps = advice[:reps];
        recommended = recommendedFor(spec, now);
        done = countFor(id);

        // A new lift is a new set: the peak from the last one belongs to the
        // rest it was banked in.
        peak = new HrPeak();
        bankedAt = null;
        sheet = null;
        rest = null;

        state = LoopState.EXERCISE;
    }

    // The sheet is a view of its own; the loop only remembers that it is open so
    // a stray redraw cannot skip it.
    function openSheet() as Void {
        if (state != LoopState.EXERCISE) {
            return;
        }
        // An id the catalogue does not know (a library the phone replaced under
        // the session) leaves no increment; the sheet then moves the load by
        // nothing rather than dividing by it.
        var increment = spec == null ? 0.0 : spec[:inc];
        sheet = new SetSheet({ :weight => weight, :reps => reps }, increment, done > 0);
        state = LoopState.SET_SHEET;
    }

    // The user confirmed the set. The rest starts from the exercise's own
    // interval, not from a constant: a deadlift is not a curl.
    function bankSet(bankedWeight, bankedReps, rir, now) as Void {
        lastSet = { :weight => bankedWeight, :reps => bankedReps, :rir => rir };
        weight = bankedWeight;
        reps = bankedReps;

        done = countFor(exerciseId) + 1;
        sessionCounts[exerciseId] = done;

        rest = new RestState(restFor(spec));
        restAt = now;
        bankedAt = now;
        sheet = null;

        state = LoopState.REST;
    }

    // The countdown ran out, or START cut it short.
    function restFinished() as Void {
        if (state != LoopState.REST) {
            return;
        }
        promptCursor = promptDefault();
        state = LoopState.NEXT_PROMPT;
    }

    // "Yes, next set": the same lift, the next set. The load the user adjusted
    // on the exercise screen is kept, because the engine's advice does not
    // change mid-session and re-advising would silently undo an adjustment.
    function continueSame() as Void {
        if (state != LoopState.NEXT_PROMPT) {
            return;
        }
        rest = null;
        peak = new HrPeak();
        bankedAt = null;
        state = LoopState.EXERCISE;
    }

    // "Different exercise", and "End exercise" from the action menu.
    function chooseDifferent() as Void {
        rest = null;
        sheet = null;
        state = LoopState.PICK;
    }

    function finish() as Void {
        rest = null;
        sheet = null;
        state = LoopState.SUMMARY;
    }

    // The summary has been shown; Home must not push it again when it comes
    // back into view.
    function closeSummary() as Void {
        if (state != LoopState.SUMMARY) {
            return;
        }
        exerciseId = null;
        spec = null;
        sessionCounts = {};
        state = LoopState.HOME;
    }

    // ---- the exercise screen ---------------------------------------------

    // UP/DOWN on the exercise screen. The step is the plate pair the exercise
    // can actually be loaded with.
    function adjustWeight(direction) as Void {
        if (spec == null || direction == 0) {
            return;
        }
        var step = spec[:inc];
        if (step == null || step <= 0.0) {
            return;
        }
        var moved = weight + step * direction.toFloat();
        weight = moved < 0.0 ? 0.0 : moved;
    }

    function name() as Lang.String {
        if (spec == null) {
            return "";
        }
        var value = spec[:name];
        return value == null ? exerciseId : value.toString();
    }

    // "BW", "BW +2.5 kg" or "100.0 kg". Bodyweight is a load, not an empty
    // weight, and a pull-up with a plate is body mass plus the plate.
    function loadLabel() as Lang.String {
        return loadTextFor(weight, spec);
    }

    function loadTextFor(value, target) as Lang.String {
        var fraction = target == null ? 0.0 : target[:bw];
        var load = asFloat(value);

        if (fraction != null && fraction > 0.0) {
            if (load <= 0.0) {
                return "BW";
            }
            return "BW +" + load.format("%.1f") + " kg";
        }
        return load.format("%.1f") + " kg";
    }

    // Float.format is the only formatter the watch has, and a Number that
    // reached the display path would be drawn without its decimal point.
    static function asFloat(value) {
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            return value;
        }
        if (value instanceof Lang.Number) {
            return value.toFloat();
        }
        return 0.0;
    }

    function setLabel() as Lang.String {
        return done.toString() + "/" + recommended.toString();
    }

    // ---- the picker ------------------------------------------------------

    // The engine's ranking, as specs: least-loaded muscles first, with a nudge
    // for what has not come up in a week. Ties keep library order, which is what
    // makes a watch with no history show the list in the order it was written.
    function ranked(now, count) as Lang.Array {
        var rankedIds = Engine.rank(specs, history, now);
        var out = [] as Lang.Array;

        for (var i = 0; i < rankedIds.size() && out.size() < count; i++) {
            var entry = specFor(rankedIds[i][:id]);
            if (entry != null) {
                out.add(entry);
            }
        }
        return out;
    }

    function all() as Lang.Array {
        return specs;
    }

    // The number under the name on a picker row.
    function rowDetail(entry, now) as Lang.String {
        var rowAdvice = adviceFor(entry, now);
        return loadTextFor(rowAdvice[:weight], entry) + "  " +
            recommendedFor(entry, now).toString() + " x " + rowAdvice[:reps].toString();
    }

    // ---- the prompt ------------------------------------------------------

    // Yes while the recommended count is not reached, Different once it is: the
    // engine's answer is the default, and the user only has to move the
    // highlight when they disagree with it.
    function promptDefault() as Lang.Number {
        return done < recommended ? PromptRow.SAME : PromptRow.DIFFERENT;
    }

    function prompt() as Lang.Number {
        return promptCursor;
    }

    function movePrompt(direction) as Void {
        var moved = promptCursor + direction;
        if (moved < PromptRow.SAME) {
            moved = PromptRow.SAME;
        }
        if (moved > PromptRow.DIFFERENT) {
            moved = PromptRow.DIFFERENT;
        }
        promptCursor = moved;
    }

    // ---- rest and heart rate ---------------------------------------------

    // Called once a second while the set is being done and while resting. A null
    // rate is a strap that is off and is dropped by HrPeak, never counted as a
    // zero.
    function sampleHr(hr, now) as Void {
        if (bankedAt == null) {
            peak.sample(hr);
            return;
        }
        peak.sampleTail(hr, now - bankedAt);
    }

    function peakHr() {
        return peak.peak();
    }

    function restRemaining(now) as Lang.Number {
        if (rest == null) {
            return 0;
        }
        return rest.remaining(now - restAt);
    }

    // The rate the rest is waiting for: 40% of heart-rate reserve above resting,
    // the same target Engine.rest compares against. Null when there is no peak
    // to compute a reserve from, which is the strap-off case the screen must not
    // pretend to know better than.
    function readyTarget(restingHr) {
        var top = peak.peak();
        if (top == null) {
            return null;
        }
        var base = restingHr == null ? Engine.DEFAULT_RESTING_HR : restingHr;
        return (base + Engine.HR_RESERVE_FRACTION * (top - base)).toNumber();
    }

    // ---- totals ----------------------------------------------------------

    function totalSets() as Lang.Number {
        var ids = sessionCounts.keys();
        var total = 0;
        for (var i = 0; i < ids.size(); i++) {
            total += sessionCounts[ids[i]];
        }
        return total;
    }

    function setsFor(id) as Lang.Number {
        return countFor(id);
    }

    function countFor(id) as Lang.Number {
        if (id == null) {
            return 0;
        }
        var value = sessionCounts[id];
        return value == null ? 0 : value;
    }

    // ---- the engine ------------------------------------------------------

    // The phone's load if it sent one, else the engine's own answer from the
    // watch's history, else the seed. docs/watch-ux.md §1 puts the phone first
    // because it has the whole history, not the last three sets of it.
    function adviceFor(target, now) {
        if (target == null) {
            return { :weight => 0.0, :reps => 0 };
        }

        var next = Engine.nextLoad(target, historyFor(target[:id]), Engine.seedWeight(target, seeds), bodyKg);

        var phone = phoneWeights[target[:id]];
        if (phone != null) {
            next = { :weight => Engine.clampToSpec(phone, target), :reps => next[:reps] };
        }
        return next;
    }

    // A muscle under 8 weekly sets earns a fourth; a movement never trained
    // stays at 3. The number is the engine's, not a constant, so a lift that has
    // been hammered this week is asked for fewer sets than a fresh one.
    function recommendedFor(target, now) as Lang.Number {
        if (target == null) {
            return 0;
        }
        return Engine.recommendedSets(target, weeklySetsFor(target, now), everTrained(target[:id]));
    }

    function weeklySetsFor(target, now) {
        var load = Engine.muscleLoad(specs, history, now);
        var primary = Engine.primaryMuscle(target);
        if (primary == null) {
            return 0.0;
        }
        var value = load[primary];
        return value == null ? 0.0 : value;
    }

    function everTrained(id) as Lang.Boolean {
        for (var i = 0; i < history.size(); i++) {
            if (Text.same(history[i][:id], id)) {
                return true;
            }
        }
        return false;
    }

    function historyFor(id) as Lang.Array {
        var out = [] as Lang.Array;
        for (var i = 0; i < history.size(); i++) {
            if (Text.same(history[i][:id], id)) {
                out.add(history[i]);
            }
        }
        return out;
    }

    function restFor(target) as Lang.Number {
        if (target == null) {
            return DEFAULT_REST;
        }
        var value = target[:rest];
        if (value == null) {
            return DEFAULT_REST;
        }
        // A whole number of seconds: the countdown divides by 60, and a Float
        // here would print "2.500000" on the rest screen.
        return whole(value);
    }

    function specFor(id) {
        for (var i = 0; i < specs.size(); i++) {
            if (Text.same(specs[i][:id], id)) {
                return specs[i];
            }
        }
        return null;
    }

    // ---- building the catalogue ------------------------------------------

    // Library's normalised entries are String-keyed (they come from the phone's
    // JSON) and carry the bodyweight fraction as a plain number; Engine wants
    // symbols and the movement fractions. This is the one place that translation
    // happens, so the picker and the engine cannot disagree about what a row
    // means.
    //
    // `mus` and `sec` are the muscle shares the phone sent, kept apart: the
    // engine prices `sec` at 60%, which is the whole point of the payload
    // distinguishing them. Without either the ranking is a library-order list,
    // which is what a watch that has never heard from the phone gets - still
    // usable, just not personalised.
    static function specsFrom(entries) as Lang.Array {
        var out = [] as Lang.Array;
        if (entries == null) {
            return out;
        }

        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i];
            if (entry == null) {
                continue;
            }

            out.add({
                :id => entry["id"],
                :name => entry["name"],
                :lo => whole(entry["lo"]),
                :hi => whole(entry["hi"]),
                :inc => entry["inc"],
                :minW => entry["minW"],
                :rest => whole(entry["rest"]),
                :bw => bodyweightFraction(entry),
                :pattern => "",
                :primary => sharesOf(entry["mus"]),
                :secondary => sharesOf(entry["sec"])
            });
        }
        return out;
    }

    // The payload's own fraction wins, because it is the phone's library and a
    // user can add a calisthenics movement the watch has never heard of. A
    // library entry from an older phone carries no `bw`, and that is what the
    // compiled table in Exercises.mc is still for; an id it does not know is 0.0,
    // a loaded lift, never a crash.
    static function bodyweightFraction(entry) as Lang.Float {
        var sent = entry["bw"];
        if (sent instanceof Lang.Float || sent instanceof Lang.Double) {
            return sent;
        }
        if (sent instanceof Lang.Number) {
            return sent.toFloat();
        }
        return Exercises.bwFor(entry["id"] == null ? "" : entry["id"].toString());
    }

    // JSON numbers arrive as Float, and a rep target of 8.0 prints as
    // "8.000000" on the watch. Counts are whole numbers; weights stay floats.
    static function whole(value) {
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            return value.toNumber();
        }
        return value;
    }

    // `mus` is [[muscle, share], ...] on the wire, and `sec` has the same shape.
    // Both are String-keyed maps of muscle id -> share by the time Engine sees
    // them; the engine is what applies the 40% discount to the second one, so the
    // two are never merged here.
    static function sharesOf(mus) as Lang.Dictionary {
        var out = {};
        if (mus == null || !(mus instanceof Lang.Array)) {
            return out;
        }

        for (var i = 0; i < mus.size(); i++) {
            var pair = mus[i];
            if (pair == null || !(pair instanceof Lang.Array) || pair.size() < 2) {
                continue;
            }
            var muscle = pair[0];
            var share = pair[1];
            if (muscle == null) {
                continue;
            }
            if (share instanceof Lang.Float || share instanceof Lang.Double) {
                out[muscle.toString()] = share;
            } else if (share instanceof Lang.Number) {
                out[muscle.toString()] = share.toFloat();
            }
        }
        return out;
    }
}
