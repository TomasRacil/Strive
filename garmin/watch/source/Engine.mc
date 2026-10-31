using Toybox.Lang;
using Toybox.Math;

// The training engine, ported.
//
// The watch has to recommend loads, count rest and rank what to do next with no
// phone anywhere near it, and a Connect IQ app cannot call into the Android app,
// so the formulas exist twice. The defence against the two drifting is
// shared/engine-vectors.json: both test suites run the same cases, so a change
// on one side that the other does not make turns a test red instead of shipping
// two different trainers. tools/gen_engine_vectors.py turns the JSON into
// test/Vectors.mc because Monkey C has no JSON parser.
//
// Pure functions only - no Storage, no UI, and no clock of its own. `now` is
// always passed in so a test can pin it and a caller can replay history.
//
// Monkey C has no data classes, so everything is a Dictionary:
//
//   spec  { :id, :lo, :hi, :inc, :minW, :rest, :pattern, :bw,
//           :primary, :secondary }
//         :primary and :secondary are String-keyed maps of muscle id -> share.
//   set   { :weight, :reps, :rir }        :rir is null when it was not recorded
//   timed { :id, :weight, :reps, :rir, :ts }
//   load  { "muscle_id" => effective sets }, String-keyed, because that is the
//         key the caller looks the muscle up with.
//
// Weights are kilograms, reps are whole numbers, times are epoch seconds.
module Engine {

    // Epley stops being an estimate past a rep range this long.
    const MAX_EFFECTIVE_REPS = 30;

    // Load halves every 2.5 days: 58% after two, 19% after six.
    const RECOVERY_HALF_LIFE_DAYS = 2.5;
    const LOAD_WINDOW_DAYS = 7.0;
    const HARD_WEEK_SETS = 12.0;
    const RECOVERY_EXCLUSION = 0.25;

    const MIN_REST_SECONDS = 30;
    const REST_STEP_SECONDS = 15;
    const REST_EXTENSION_CAP = 1.5;
    const DEFAULT_RESTING_HR = 60;
    const HR_RESERVE_FRACTION = 0.40;

    const PUSHUP_FRACTION = 0.65;
    const SQUAT_FRACTION = 0.85;
    const SEED_FRACTION = 0.65;
    const FALLBACK_SEED_KG = 20.0;

    // Body mass assumed before onboarding has asked for one. A bodyweight set is
    // priced at bodyKg * :bw, so without it every pull-up set scores e1rm 0 and
    // the tie-break decides which one was top. The real profile weight is passed
    // in as soon as there is one.
    const DEFAULT_BODY_KG = 80.0;

    const DAY_SECONDS = 86400.0;
    const DAYS_IN_WINDOW_28 = 28;

    // ---- 1. strength -----------------------------------------------------

    function e1rm(weight, reps, rir) {
        return e1rmBodyweight(weight, reps, rir, 0.0, 0.0);
    }

    // Bodyweight form: with no external load the mass moved is body mass times
    // the movement's fraction. A logged weight always wins over the estimate.
    function e1rmBodyweight(weight, reps, rir, bodyKg, fraction) {
        var effective = reps + rir;
        if (effective < 0) {
            effective = 0;
        }
        if (effective > MAX_EFFECTIVE_REPS) {
            effective = MAX_EFFECTIVE_REPS;
        }

        var load = weight > 0.0 ? weight : bodyKg * fraction;
        return load * (1.0 + effective / 30.0);
    }

    // ---- 2. next load ----------------------------------------------------

    // The sets of the most recent session that contains the exercise, oldest
    // first. Empty history falls back to the seed, aimed at the top of the range
    // because a seed is deliberately conservative.
    //
    // `bodyKg` is what makes a bodyweight set scoreable: weight 0 priced at body
    // mass times :bw, so 15 pull-ups at 3 in reserve beats 15 at failure. A
    // caller with no body weight yet passes null and gets DEFAULT_BODY_KG.
    //
    // "top" is the highest e1rm. Ties go to more reps and then to more reps in
    // reserve: two sets of one lift that score the same, and the one that left
    // more in the tank is the one worth progressing from.
    function nextLoad(spec, history, seedKg, bodyKg) {
        var lo = spec[:lo];
        var hi = spec[:hi];

        if (bodyKg == null) {
            bodyKg = DEFAULT_BODY_KG;
        }

        if (history == null || history.size() == 0) {
            return { :weight => clampToSpec(seedKg, spec), :reps => hi };
        }

        var top = history[0];
        for (var i = 1; i < history.size(); i++) {
            if (betterSet(history[i], top, spec, bodyKg)) {
                top = history[i];
            }
        }

        var rir = rirOf(top);
        var base = top[:weight];
        var inc = spec[:inc];
        var raw = base;

        if (top[:reps] >= hi && rir >= 2) {
            raw = base + inc;
        } else if (top[:reps] >= hi && rir == 1) {
            // One more session at this load: the range has to be earned.
            raw = base;
        } else if (rir <= 0 && top[:reps] < lo) {
            raw = base - inc;
        }

        return {
            :weight => clampToSpec(raw, spec),
            // Any load change targets the bottom of the range: an increase has to
            // be earned, and a deload rebuilds reps before plates.
            :reps => raw != base ? lo : hi
        };
    }

    function betterSet(candidate, best, spec, bodyKg) {
        // A spec that forgot :bw is a loaded lift, not a crash.
        var fraction = spec[:bw];
        if (fraction == null) {
            fraction = 0.0;
        }
        var candidateE1rm = e1rmBodyweight(candidate[:weight], candidate[:reps], rirOf(candidate), bodyKg, fraction);
        var bestE1rm = e1rmBodyweight(best[:weight], best[:reps], rirOf(best), bodyKg, fraction);
        if (candidateE1rm != bestE1rm) {
            return candidateE1rm > bestE1rm;
        }
        if (candidate[:reps] != best[:reps]) {
            return candidate[:reps] > best[:reps];
        }
        return rirOf(candidate) > rirOf(best);
    }

    // ---- 3. how many sets ------------------------------------------------

    // A muscle under 8 weekly sets earns a fourth set. A movement never done
    // stays at 3 however fresh the muscle is: the first session is about
    // learning the lift, not volume. A planned workout uses the plan's number.
    function recommendedSets(spec, weeklyMuscleSets, everTrained) {
        var sets = 3;
        if (weeklyMuscleSets < 8) {
            sets = 4;
        }
        if (everTrained == false) {
            sets = 3;
        }
        if (sets > 5) {
            sets = 5;
        }
        if (sets < 2) {
            sets = 2;
        }
        return sets;
    }

    // ---- 4. load, recovery, priority -------------------------------------

    // Effective sets per muscle over the last 7 days: the set counts for its
    // muscle share, scaled by how close to failure it was and by how long ago.
    //
    // A set whose exercise is not in `specs` is skipped, not thrown: history
    // outlives the library and a deleted exercise must not stop the watch
    // recommending anything.
    function muscleLoad(specs, sets, now) {
        var out = {};
        if (sets == null) {
            return out;
        }

        for (var i = 0; i < sets.size(); i++) {
            var set = sets[i];
            var spec = findSpec(specs, set[:id]);
            if (spec == null) {
                continue;
            }

            var age = ageDays(set[:ts], now);
            if (age > LOAD_WINDOW_DAYS) {
                continue;
            }

            var decay = Math.pow(0.5, age / RECOVERY_HALF_LIFE_DAYS);
            var weight = effort(set[:rir]) * decay;
            var shares = loadByMuscle(spec);
            var muscles = shares.keys();

            for (var k = 0; k < muscles.size(); k++) {
                var muscle = muscles[k];
                var previous = out[muscle];
                out[muscle] = (previous == null ? 0.0 : previous) + shares[muscle] * weight;
            }
        }

        return out;
    }

    function recovery(load) {
        var out = {};
        if (load == null) {
            return out;
        }

        var muscles = load.keys();
        for (var i = 0; i < muscles.size(); i++) {
            var value = 1.0 - load[muscles[i]] / HARD_WEEK_SETS;
            if (value < 0.0) {
                value = 0.0;
            }
            if (value > 1.0) {
                value = 1.0;
            }
            out[muscles[i]] = value;
        }
        return out;
    }

    // Recovery of the exercise's muscles dominates; recency and frequency are
    // small on purpose (0.15, 0.10) so they only separate lifts whose muscles
    // are in the same state. Ties keep library order, which is why `specs` is an
    // Array and not a Dictionary.
    function rank(specs, sets, now) {
        // Nothing to rank, or nothing logged yet: an empty list, not a crash.
        // The watch calls this on every redraw, including before the first set.
        if (specs == null) {
            return [];
        }
        if (sets == null) {
            sets = [];
        }

        var recovered = recovery(muscleLoad(specs, sets, now));
        var scored = [];

        for (var i = 0; i < specs.size(); i++) {
            var spec = specs[i];
            var shares = loadByMuscle(spec);
            var meanRecovery = 1.0;

            if (shares.size() > 0) {
                var total = 0.0;
                var muscles = shares.keys();
                for (var k = 0; k < muscles.size(); k++) {
                    var value = recovered[muscles[k]];
                    total = total + (value == null ? 1.0 : value);
                }
                meanRecovery = total / shares.size();
            }

            // Gated on the prime mover: a spent chest buries the bench even with
            // fresh triceps.
            var gate = 1.0;
            var primary = primaryMuscle(spec);
            if (primary != null) {
                var primaryRecovery = recovered[primary];
                if (primaryRecovery != null) {
                    gate = primaryRecovery;
                }
            }
            if (gate < RECOVERY_EXCLUSION) {
                continue;
            }

            var daysSince = 7.0;
            // The newest set, not the oldest: days since last trained is how long
            // the muscle has had to recover. The oldest would read a lift trained
            // this morning as stale, so training it more often would earn more of
            // the staleness bonus.
            var newest = -1.0;
            var daySeen = {};
            var windowStart = now - DAYS_IN_WINDOW_28 * 86400;

            for (var j = 0; j < sets.size(); j++) {
                var set = sets[j];
                if (!Text.same(set[:id], spec[:id])) {
                    continue;
                }

                var age = ageDays(set[:ts], now);
                if (newest < 0.0 || age < newest) {
                    newest = age;
                }
                if (set[:ts] >= windowStart && set[:ts] <= now) {
                    daySeen[(set[:ts] / 86400).toNumber()] = true;
                }
            }

            if (newest >= 0.0) {
                daysSince = newest > 7.0 ? 7.0 : newest;
            }

            var timesTrained = daySeen.size();
            if (timesTrained > 8) {
                timesTrained = 8;
            }

            var score = meanRecovery
                + 0.15 * daysSince / 7.0
                + 0.10 * timesTrained / 8.0;

            scored.add({ :id => spec[:id], :score => score, :order => i });
        }

        // Total order (score, library index) and a hand-written sort: Array.sort
        // needs a comparator this firmware will not take here, and the ordering
        // has to be deterministic anyway.
        for (var i = 0; i < scored.size(); i++) {
            for (var j = 0; j + 1 < scored.size() - i; j++) {
                if (before(scored[j + 1], scored[j])) {
                    var swap = scored[j];
                    scored[j] = scored[j + 1];
                    scored[j + 1] = swap;
                }
            }
        }

        var out = [];
        for (var i = 0; i < scored.size(); i++) {
            out.add({ :id => scored[i][:id], :score => scored[i][:score] });
        }
        return out;
    }

    function before(left, right) {
        if (left[:score] != right[:score]) {
            return left[:score] > right[:score];
        }
        return left[:order] < right[:order];
    }

    // 1.2 near failure, 1.0 in the middle, 0.8 for an easy set. An unrecorded
    // RIR counts as 2: assuming failure would overstate fatigue, assuming easy
    // would understate it, and 2 is where most working sets land.
    function effort(rir) {
        if (rir == null) {
            return 1.0;
        }
        if (rir <= 1) {
            return 1.2;
        }
        if (rir <= 3) {
            return 1.0;
        }
        return 0.8;
    }

    // ---- 6. rest ---------------------------------------------------------

    // One evaluation of the rest clock.
    //
    // The rule is a loop - keep extending while the heart rate is above target,
    // 15 s at a time, at most 1.5x base - but this is a pure function with no
    // elapsed time to reason about, so it decides one step. The caller re-calls
    // it while the clock runs and feeds the new length back as `base`.
    //
    // That is what `ceilingSeconds` is for. Fed back without it, `base` grows and
    // the 1.5x cap grows with it, so the extension would never stop; passing the
    // original ceiling once makes the loop converge (a length already at the
    // ceiling stays there).
    //
    // A null peak or current heart rate means exactly `base`: the simulator has
    // no strap and neither does a session without one, and a missing sensor must
    // never delay or shorten a rest.
    function rest(base, peakHr, currentHr, restingHr, ceilingSeconds) {
        var resting = restingHr == null ? DEFAULT_RESTING_HR : restingHr;
        var floor = base > MIN_REST_SECONDS ? base : MIN_REST_SECONDS;

        if (peakHr == null || currentHr == null) {
            return { :seconds => floor, :ready => false };
        }

        var target = resting + HR_RESERVE_FRACTION * (peakHr - resting);
        if (currentHr <= target) {
            // Down early: the clock keeps running, but say so, so the app can
            // buzz once instead of making the user watch the seconds.
            return { :seconds => floor, :ready => true };
        }

        var ceiling = ceilingSeconds;
        if (ceiling == null) {
            ceiling = (base * REST_EXTENSION_CAP).toNumber();
        }

        var extended = base + REST_STEP_SECONDS;
        if (extended > ceiling) {
            extended = ceiling;
        }
        if (extended < MIN_REST_SECONDS) {
            extended = MIN_REST_SECONDS;
        }

        return { :seconds => extended, :ready => false };
    }

    // ---- 5. seeds --------------------------------------------------------

    // Calibration: push-ups and bodyweight squats taken to RIR 1 give an e1rm
    // per pattern without a barbell in sight.
    function seedE1rm(bodyKg, pushUpReps, squatReps) {
        return {
            "pushup" => bodyKg * PUSHUP_FRACTION * (1.0 + clampReps(pushUpReps) / 30.0),
            "squat" => bodyKg * SQUAT_FRACTION * (1.0 + clampReps(squatReps) / 30.0)
        };
    }

    // Mapped patterns start at 65% of the pattern's estimate. A bodyweight
    // movement starts at 0 kg external - there is no bar to load and 20 kg on a
    // pull-up would be a different exercise. Everything else gets an empty bar,
    // or the exercise's own floor when that is heavier.
    function seedWeight(spec, seeds) {
        if (spec[:bw] > 0.0) {
            return 0.0;
        }
        if (seeds == null) {
            seeds = {};
        }
        var pattern = spec[:pattern];
        var patternE1rm = null;
        if (pattern != null && pattern.length() > 0) {
            patternE1rm = seeds[pattern];
        }

        if (patternE1rm == null || patternE1rm <= 0.0) {
            return FALLBACK_SEED_KG > spec[:minW] ? FALLBACK_SEED_KG : spec[:minW];
        }

        var seeded = roundToIncrement(patternE1rm * SEED_FRACTION, spec[:inc]);
        return seeded > spec[:minW] ? seeded : spec[:minW];
    }

    // ---- shared helpers --------------------------------------------------

    // Nearest multiple of the step, halves up, then the exercise's floor.
    function clampToSpec(weight, spec) {
        var rounded = roundToIncrement(weight, spec[:inc]);
        return rounded > spec[:minW] ? rounded : spec[:minW];
    }

    // A step of 0 (a spec that forgot to push one) leaves the weight alone
    // rather than dividing by zero.
    function roundToIncrement(weight, increment) {
        if (increment <= 0.0) {
            return weight;
        }
        return Math.round(weight / increment) * increment;
    }

    function rirOf(set) {
        var rir = set[:rir];
        return rir == null ? 2 : rir;
    }

    function clampReps(reps) {
        if (reps < 0) {
            return 0;
        }
        return reps > MAX_EFFECTIVE_REPS ? MAX_EFFECTIVE_REPS : reps;
    }

    // Primary at face value, secondary at 60%: a stabiliser is not doing the
    // work of a prime mover. Same rule as the phone's Exercise.loadByMuscle.
    function loadByMuscle(spec) {
        var out = {};

        var primary = spec[:primary];
        if (primary != null) {
            var muscles = primary.keys();
            for (var i = 0; i < muscles.size(); i++) {
                var previous = out[muscles[i]];
                out[muscles[i]] = (previous == null ? 0.0 : previous) + primary[muscles[i]];
            }
        }

        var secondary = spec[:secondary];
        if (secondary != null) {
            var muscles = secondary.keys();
            for (var i = 0; i < muscles.size(); i++) {
                var previous = out[muscles[i]];
                out[muscles[i]] = (previous == null ? 0.0 : previous) + secondary[muscles[i]] * 0.6;
            }
        }

        return out;
    }

    // The muscle that gates the exercise: the biggest share in :primary.
    // Averaging every muscle would let a fresh stabiliser outvote a spent prime
    // mover.
    function primaryMuscle(spec) {
        var primary = spec[:primary];
        if (primary == null) {
            return null;
        }

        var best = null;
        var bestShare = null;
        var muscles = primary.keys();
        for (var i = 0; i < muscles.size(); i++) {
            var share = primary[muscles[i]];
            if (bestShare == null || share > bestShare) {
                best = muscles[i];
                bestShare = share;
            }
        }
        return best;
    }

    function findSpec(specs, id) {
        if (specs == null) {
            return null;
        }
        for (var i = 0; i < specs.size(); i++) {
            if (Text.same(specs[i][:id], id)) {
                return specs[i];
            }
        }
        return null;
    }

    // A set from the future is clock skew, not extra fatigue.
    function ageDays(timestamp, now) {
        var seconds = now - timestamp;
        if (seconds < 0) {
            seconds = 0;
        }
        return seconds / DAY_SECONDS;
    }
}
