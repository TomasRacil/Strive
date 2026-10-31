using Toybox.Application as App;
using Toybox.Lang;
using Toybox.Test;

// What the watch does with the `lib` payload's bodyweight fraction and its two
// muscle groups.
//
// Both are read through Library and TrainingLoop.specsFrom rather than by
// poking a dictionary: the bug these cover was that the fields never survived
// the trip from the wire into the engine's spec, so a test that skips that trip
// would have passed while the watch was still wrong.

const LIB_NOW = 1700000000;

// A library entry in the shape the phone sends, with every field the payload
// carries. `bw` is deliberately a parameter: a payload without it is the older
// phone's payload, which is the case the compiled table exists for.
function libEntry(id, name, mus, sec, bw) {
    var entry = {
        "id" => id,
        "name" => name,
        "short" => name,
        "lo" => 6,
        "hi" => 10,
        "rest" => 120,
        "inc" => 2.5,
        "minW" => 0.0,
        "mus" => mus,
        "sec" => sec
    };
    if (bw != null) {
        entry["bw"] = bw;
    }
    return entry;
}

// Applies a library of one or more entries and returns the engine specs the
// watch builds from it.
function libSpecs(entries) {
    App.Storage.deleteValue(Library.LIB_KEY);
    App.Storage.deleteValue(Library.LIB_V);
    Library.Cache.lib = null;
    Library.Cache.libV = -1;

    var applied = Library.apply("lib", { "v" => 9, "ex" => entries });
    if (!applied) {
        return null;
    }
    return TrainingLoop.specsFrom(Library.exercises());
}

// ---- bodyweight fraction ---------------------------------------------------

// The fraction the phone sent is the one the engine prices the set with.
(:test)
function testLibBodyweightFractionArrives(logger) as Lang.Boolean {
    var specs = libSpecs([
        libEntry("ring_dip", "Ring Dip", [["chest", 1.0]], [["triceps", 0.5]], 1.0)
    ]);
    if (specs == null || specs.size() != 1) {
        return false;
    }

    var bw = specs[0][:bw];
    logger.debug("bw from payload: " + bw.toString());

    // A pull-up with no external load is body mass, not zero kilos: the seed is
    // what the exercise screen starts from, and a bodyweight lift starts at 0.
    var seed = Engine.seedWeight(specs[0], {});
    return bw == 1.0 && seed == 0.0;
}

// A phone that predates `bw` sends nothing, and the compiled table is what keeps
// the watch pricing a pull-up correctly until the phone is updated.
(:test)
function testLibMissingBwFallsBackToCompiledTable(logger) as Lang.Boolean {
    var specs = libSpecs([
        libEntry("pull_ups", "Pull-ups", [["lats", 0.8]], [], null)
    ]);
    if (specs == null || specs.size() != 1) {
        return false;
    }

    logger.debug("bw without payload field: " + specs[0][:bw].toString());
    return specs[0][:bw] == 1.0;
}

// An id the compiled table has never heard of, and no fraction on the wire: a
// loaded lift, which is 0.0. Null here would reach Engine's arithmetic.
(:test)
function testLibUnknownIdWithoutBwIsALoadedLift(logger) as Lang.Boolean {
    var specs = libSpecs([
        libEntry("cable_fly_custom", "Cable Fly", [["chest", 1.0]], [], null)
    ]);
    if (specs == null || specs.size() != 1) {
        return false;
    }

    var bw = specs[0][:bw];
    logger.debug("bw for an unknown id: " + bw.toString());
    return bw != null && bw == 0.0;
}

// ---- muscle shares ---------------------------------------------------------

// The two groups are the reason the engine can discount a stabiliser; merging
// them would put a stabiliser's share into the gate that decides whether a lift
// is excluded at all.
(:test)
function testLibSecondarySharesLandInSecondary(logger) as Lang.Boolean {
    var specs = libSpecs([
        libEntry("bench_press", "Bench Press", [["chest", 1.0]], [["triceps", 0.6]], 0.0)
    ]);
    if (specs == null || specs.size() != 1) {
        return false;
    }

    var primary = specs[0][:primary];
    var secondary = specs[0][:secondary];
    var shares = Engine.loadByMuscle(specs[0]);

    logger.debug("primary=" + primary.toString() + " secondary=" + secondary.toString());

    // Chest at face value, triceps at 60% of the share the phone sent. The gate
    // is the biggest primary share, so a stabiliser can never gate the lift.
    var gate = Engine.primaryMuscle(specs[0]);
    return primary["chest"] == 1.0 &&
        primary["triceps"] == null &&
        secondary["triceps"] == 0.6 &&
        shares["chest"] > 0.99 && shares["chest"] < 1.01 &&
        shares["triceps"] > 0.35 && shares["triceps"] < 0.37 &&
        gate != null && Text.same(gate, "chest");
}

// ---- ranking ---------------------------------------------------------------

// A compound whose stabiliser is already spent must not be pushed below an
// isolation lift that only shares its prime mover. That is the behaviour the 40%
// discount exists for: the stabiliser's own work counts for less, so a bench is
// not punished as hard as a fly would be for the same triceps fatigue.
//
// The setup: the triceps were hammered today by a press that carries them as a
// stabiliser, the chest was trained by six fly sets, and the bench has not been
// touched this week. The bench earns the staleness bonus and, with the discount,
// keeps a higher score than the fly.
(:test)
function testSpentSecondaryDoesNotBuryACompound(logger) as Lang.Boolean {
    var bench = libEntry("bench_press", "Bench Press", [["chest", 1.0]], [["triceps", 0.6]], 0.0);
    var fly = libEntry("chest_fly", "Chest Fly", [["chest", 1.0]], [], 0.0);
    var press = libEntry("front_press", "Front Press", [["front_delts", 1.0]], [["triceps", 0.6]], 0.0);

    var specs = libSpecs([bench, fly, press]);
    if (specs == null || specs.size() != 3) {
        return false;
    }

    var sets = [] as Lang.Array;
    for (var i = 0; i < 18; i++) {
        sets.add({ :id => "front_press", :weight => 40.0, :reps => 8, :rir => 2, :ts => LIB_NOW });
    }
    for (var i = 0; i < 6; i++) {
        sets.add({ :id => "chest_fly", :weight => 20.0, :reps => 10, :rir => 2, :ts => LIB_NOW });
    }

    var ranked = Engine.rank(specs, sets, LIB_NOW);
    var benchAt = libIndexOf(ranked, "bench_press");
    var flyAt = libIndexOf(ranked, "chest_fly");

    logger.debug("ranked with sec: " + libScoreOf(ranked, "bench_press").toString() +
        " vs " + libScoreOf(ranked, "chest_fly").toString());

    // The old payload put every share in :primary, so the press's 0.6 triceps
    // arrived at full weight and the same history left the triceps at 0.1
    // recovery instead of 0.46. Built by hand, because no payload can produce
    // that shape any more - it is the regression this test guards.
    var flat = [
        { :id => "bench_press", :lo => 6, :hi => 10, :inc => 2.5, :minW => 0.0, :rest => 120,
          :bw => 0.0, :pattern => "", :primary => { "chest" => 1.0, "triceps" => 0.6 }, :secondary => {} },
        { :id => "chest_fly", :lo => 6, :hi => 10, :inc => 2.5, :minW => 0.0, :rest => 120,
          :bw => 0.0, :pattern => "", :primary => { "chest" => 1.0 }, :secondary => {} },
        { :id => "front_press", :lo => 6, :hi => 10, :inc => 2.5, :minW => 0.0, :rest => 120,
          :bw => 0.0, :pattern => "", :primary => { "front_delts" => 1.0, "triceps" => 0.6 }, :secondary => {} }
    ];
    var flatRanked = Engine.rank(flat, sets, LIB_NOW);
    var flatBenchAt = libIndexOf(flatRanked, "bench_press");
    var flatFlyAt = libIndexOf(flatRanked, "chest_fly");

    logger.debug("ranked flat: bench=" + flatBenchAt.toString() + " fly=" + flatFlyAt.toString() +
        " (" + libScoreOf(flatRanked, "bench_press").toString() + " vs " +
        libScoreOf(flatRanked, "chest_fly").toString() + ")");

    var keptApart = benchAt < flyAt;
    var flatBuried = flatBenchAt > flatFlyAt;
    return keptApart && flatBuried;
}

function libIndexOf(ranked, id) {
    for (var i = 0; i < ranked.size(); i++) {
        if (Text.same(ranked[i][:id], id)) {
            return i;
        }
    }
    return -1;
}

function libScoreOf(ranked, id) {
    for (var i = 0; i < ranked.size(); i++) {
        if (Text.same(ranked[i][:id], id)) {
            return ranked[i][:score];
        }
    }
    return -1.0;
}
