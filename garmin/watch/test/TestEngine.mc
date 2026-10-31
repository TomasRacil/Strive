using Toybox.Test;
using Toybox.Lang;

// The watch half of the agreement check.
//
// Vectors.mc is generated from shared/engine-vectors.json by
// tools/gen_engine_vectors.py; the phone runs the same file through EngineTest.kt.
// Every case here has a Kotlin twin, so a formula changed on one side and not the
// other fails in one of the two suites.
//
// The extra cases at the bottom are watch-only: a null heart rate, empty history,
// an exercise id the library no longer has. They are the states the simulator and
// a dead sensor actually produce.

function vectorsClose(actual, expected) {
    var diff = actual - expected;
    if (diff < 0) {
        diff = -diff;
    }
    return diff <= Vectors.TOLERANCE;
}

function vectorsMapMatches(actual, expected) {
    var keys = expected.keys();
    if (actual.keys().size() != keys.size()) {
        return false;
    }
    for (var i = 0; i < keys.size(); i++) {
        var value = actual[keys[i]];
        if (value == null || !vectorsClose(value, expected[keys[i]])) {
            return false;
        }
    }
    return true;
}

// ---- the vectors -----------------------------------------------------------

(:test)
function testVectorE1rm(logger) as Lang.Boolean {
    var cases = Vectors.e1rm();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var actual = Engine.e1rm(c[:weight], c[:reps], c[:rir]);
        if (c[:bodyKg] != null) {
            actual = Engine.e1rmBodyweight(c[:weight], c[:reps], c[:rir], c[:bodyKg], c[:bodyweightFraction]);
        }

        if (!vectorsClose(actual, c[:expect])) {
            logger.debug("e1rm " + c[:name].toString() + ": " + actual.toString() + " != " + c[:expect].toString());
            ok = false;
        }
    }
    return ok;
}

(:test)
function testVectorNextLoad(logger) as Lang.Boolean {
    var cases = Vectors.nextLoad();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var advice = Engine.nextLoad(c[:spec], c[:history], c[:seedKg]);

        if (!vectorsClose(advice[:weight], c[:expectWeight]) || advice[:reps] != c[:expectReps]) {
            logger.debug("nextLoad " + c[:name].toString() + ": " + advice[:weight].toString() + "x" + advice[:reps].toString());
            ok = false;
        }
    }
    return ok;
}

(:test)
function testVectorRecommendedSets(logger) as Lang.Boolean {
    var cases = Vectors.recommendedSets();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var sets = Engine.recommendedSets(c[:spec], c[:weeklyMuscleSets], c[:everTrained]);

        if (sets != c[:expect]) {
            logger.debug("recommendedSets " + c[:name].toString() + ": " + sets.toString() + " != " + c[:expect].toString());
            ok = false;
        }
    }
    return ok;
}

(:test)
function testVectorMuscleLoad(logger) as Lang.Boolean {
    var cases = Vectors.muscleLoad();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var load = Engine.muscleLoad(c[:specs], c[:sets], c[:now]);

        if (!vectorsMapMatches(load, c[:expect])) {
            logger.debug("muscleLoad " + c[:name].toString() + ": " + load.toString());
            ok = false;
        }
    }
    return ok;
}

(:test)
function testVectorRecovery(logger) as Lang.Boolean {
    var cases = Vectors.recovery();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var recovered = Engine.recovery(c[:load]);

        if (!vectorsMapMatches(recovered, c[:expect])) {
            logger.debug("recovery " + c[:name].toString() + ": " + recovered.toString());
            ok = false;
        }
    }
    return ok;
}

(:test)
function testVectorRank(logger) as Lang.Boolean {
    var cases = Vectors.rank();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var ranked = Engine.rank(c[:specs], c[:sets], c[:now]);
        var order = c[:expectOrder];
        var scores = c[:expectScores];

        if (ranked.size() != order.size()) {
            logger.debug("rank " + c[:name].toString() + ": size " + ranked.size().toString() + " != " + order.size().toString());
            ok = false;
            continue;
        }

        for (var j = 0; j < order.size(); j++) {
            if (!Text.same(ranked[j][:id], order[j])) {
                logger.debug("rank " + c[:name].toString() + " position " + j.toString() + ": " + ranked[j][:id].toString() + " != " + order[j].toString());
                ok = false;
            }

            var expected = scores[ranked[j][:id]];
            if (expected == null || !vectorsClose(ranked[j][:score], expected)) {
                logger.debug("rank " + c[:name].toString() + " score " + ranked[j][:id].toString() + ": " + ranked[j][:score].toString());
                ok = false;
            }
        }
    }
    return ok;
}

(:test)
function testVectorRest(logger) as Lang.Boolean {
    var cases = Vectors.rest();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var advice = Engine.rest(c[:base], c[:peakHr], c[:currentHr], c[:restingHr], c[:ceiling]);

        if (advice[:seconds] != c[:expectSeconds] || advice[:ready] != c[:expectReady]) {
            logger.debug("rest " + c[:name].toString() + ": " + advice[:seconds].toString() + "s ready=" + advice[:ready].toString());
            ok = false;
        }
    }
    return ok;
}

(:test)
function testVectorSeed(logger) as Lang.Boolean {
    var cases = Vectors.seed();
    var ok = cases.size() > 0;

    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i];
        var seeds = Engine.seedE1rm(c[:bodyKg], c[:pushUpReps], c[:squatReps]);

        if (!vectorsMapMatches(seeds, c[:expectE1rm])) {
            logger.debug("seedE1rm " + c[:name].toString() + ": " + seeds.toString());
            ok = false;
        }

        var weight = Engine.seedWeight(c[:spec], seeds);
        if (!vectorsClose(weight, c[:expectWeight])) {
            logger.debug("seedWeight " + c[:name].toString() + ": " + weight.toString() + " != " + c[:expectWeight].toString());
            ok = false;
        }
    }
    return ok;
}

// ---- watch-only edges ------------------------------------------------------

function testSpec() {
    return {
        :id => "bench_press", :lo => 6, :hi => 10, :inc => 2.5, :minW => 20.0,
        :rest => 150, :pattern => "pushup", :bw => 0.0,
        :primary => { "pectoralis_major" => 1.0 },
        :secondary => { "triceps_lateral" => 0.5 }
    };
}

// Sensor.getInfo().heartRate is null in the simulator and null whenever the
// strap is off. The peak being there and the current reading not is the case
// where a naive implementation divides by a null.
(:test)
function testRestWithHalfAHeartRate(logger) as Lang.Boolean {
    var advice = Engine.rest(150, 180, null, 60, null);
    logger.debug("half hr: " + advice[:seconds].toString() + " ready=" + advice[:ready].toString());
    return advice[:seconds] == 150 && advice[:ready] == false;
}

(:test)
function testRestExtensionConvergesAtTheCeiling(logger) as Lang.Boolean {
    var base = 150;
    var ceiling = (base * 1.5).toNumber();
    var seconds = base;
    for (var i = 0; i < 10; i++) {
        seconds = Engine.rest(seconds, 190, 185, 60, ceiling)[:seconds];
    }
    logger.debug("converged at: " + seconds.toString() + " ceiling " + ceiling.toString());
    return seconds == ceiling;
}

(:test)
function testEmptyHistoryUsesTheSeedAndTheFloor(logger) as Lang.Boolean {
    var advice = Engine.nextLoad(testSpec(), [], 0.0);
    logger.debug("empty history: " + advice[:weight].toString() + "x" + advice[:reps].toString());
    return vectorsClose(advice[:weight], 20.0) && advice[:reps] == 10;
}

(:test)
function testUnknownExerciseIsIgnored(logger) as Lang.Boolean {
    var specs = [testSpec()];
    var sets = [
        { :id => "deleted_lift", :weight => 100.0, :reps => 8, :rir => 1, :ts => 1728000 }
    ];

    var load = Engine.muscleLoad(specs, sets, 1728000);
    var ranked = Engine.rank(specs, sets, 1728000);

    logger.debug("unknown id: load " + load.size().toString() + " ranked " + ranked.size().toString());
    return load.size() == 0 && ranked.size() == 1 && Text.same(ranked[0][:id], "bench_press");
}

(:test)
function testEmptyInputsAreNotErrors(logger) as Lang.Boolean {
    var load = Engine.muscleLoad([], [], 1728000);
    var recovered = Engine.recovery(load);
    var ranked = Engine.rank([], [], 1728000);

    return load.size() == 0 && recovered.size() == 0 && ranked.size() == 0;
}

// A negative RIR is a data-entry slip, not a rep count: clamp instead of
// returning a negative estimate.
(:test)
function testNegativeRirClamps(logger) as Lang.Boolean {
    var estimate = Engine.e1rm(100.0, 5, -5);
    logger.debug("negative rir: " + estimate.toString());
    return vectorsClose(estimate, 100.0);
}

(:test)
function testRestNeverDropsBelowThirtySeconds(logger) as Lang.Boolean {
    var quiet = Engine.rest(10, null, null, 60, null);
    var extended = Engine.rest(10, 200, 190, 60, null);
    logger.debug("short base: " + quiet[:seconds].toString() + " " + extended[:seconds].toString());
    return quiet[:seconds] == 30 && extended[:seconds] == 30;
}
