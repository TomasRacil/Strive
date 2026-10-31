using Toybox.Test;
using Toybox.Lang;

// The free-training loop.
//
// This is the whole flow from docs/watch-ux.md as a state machine: pick a lift,
// bank a set, rest, continue, and the prompt that asks whether to. Nothing here
// draws, so every claim below is about the flow rather than about a screen -
// which is the point of pulling the loop out of the views in the first place.
//
// The engine is exercised through the loop, not instead of it: the numbers come
// from Engine (its own vectors cover the formulas) and what is asserted here is
// that the loop asks it the right question and shows the answer it gets back.

const LOOP_NOW = 1700000000;

function loopSpec(id, name, lo, hi, inc, minW, rest, bw, muscle) {
    var primary = {};
    if (muscle != null) {
        primary[muscle] = 1.0;
    }
    return {
        :id => id,
        :name => name,
        :lo => lo,
        :hi => hi,
        :inc => inc,
        :minW => minW,
        :rest => rest,
        :bw => bw,
        :pattern => "",
        :primary => primary,
        :secondary => {}
    };
}

function loopBench() {
    return loopSpec("bench_press", "Bench Press", 6, 8, 2.5, 20.0, 150, 0.0, "chest");
}

function loopSquat() {
    return loopSpec("squats", "Squats", 4, 6, 5.0, 40.0, 180, 0.0, "quads");
}

function loopPullUp() {
    return loopSpec("pull_ups", "Pull-ups", 6, 10, 2.5, 0.0, 120, 1.0, "lats");
}

function loopCatalogue() {
    return [loopBench(), loopSquat(), loopPullUp()];
}

function loopSet(id, weight, reps, rir, ts) {
    return { :id => id, :weight => weight, :reps => reps, :rir => rir, :ts => ts };
}

function loopNew(history, phoneWeights) {
    return new TrainingLoop(loopCatalogue(), history, {}, 80.0, phoneWeights);
}

// ---- the walk --------------------------------------------------------------

(:test)
function testLoopStartsOnHome(logger) as Lang.Boolean {
    var loop = loopNew([], {});

    var atHome = loop.state == LoopState.HOME;
    loop.start();

    logger.debug("home -> " + loop.state.toString());
    return atHome && loop.state == LoopState.PICK && loop.totalSets() == 0;
}

// The flow end to end: HOME, pick, bank, rest, continue, the prompt flipping
// once the engine's count is reached, Different back to the picker, and a
// summary that counts what was actually banked.
(:test)
function testLoopWalksFromPickToSummary(logger) as Lang.Boolean {
    var loop = loopNew([], {});

    loop.start();
    loop.pick("bench_press", LOOP_NOW);

    var picked = loop.state == LoopState.EXERCISE && Text.same(loop.exerciseId, "bench_press");
    // Never trained: the engine asks for three sets, and the seed is the floor.
    var advised = loop.recommended == 3 && loop.weight > 19.9 && loop.weight < 20.1;

    loop.openSheet();
    var sheetOpen = loop.state == LoopState.SET_SHEET && loop.sheet != null && loop.sheet.focus() == SheetField.WEIGHT;

    // Three sets, each banked, rested out and continued. The first two leave sets
    // to do, so the prompt still says yes; the third reaches the count.
    var banked = true;
    for (var i = 0; i < 3; i++) {
        loop.bankSet(100.0, 8, 2, LOOP_NOW + i * 200);
        banked = banked && loop.state == LoopState.REST && loop.done == i + 1;

        loop.restFinished();
        banked = banked && loop.state == LoopState.NEXT_PROMPT;
        banked = banked && loop.prompt() == (i < 2 ? PromptRow.SAME : PromptRow.DIFFERENT);

        if (i < 2) {
            loop.continueSame();
            banked = banked && loop.state == LoopState.EXERCISE;
            loop.openSheet();
        }
    }

    // The recommended count is reached: the prompt now defaults to leaving.
    var flipped = loop.prompt() == PromptRow.DIFFERENT;

    loop.chooseDifferent();
    var backAtPicker = loop.state == LoopState.PICK;

    loop.finish();
    var finished = loop.state == LoopState.SUMMARY && loop.totalSets() == 3;

    logger.debug("walk: picked=" + picked.toString() + " advised=" + advised.toString() +
        " sheet=" + sheetOpen.toString() + " banked=" + banked.toString() +
        " flipped=" + flipped.toString() + " picker=" + backAtPicker.toString() +
        " total=" + loop.totalSets().toString());

    return picked && advised && sheetOpen && banked && flipped && backAtPicker && finished;
}

// The count is the engine's, not a constant: a lift with one set of history and
// a fresh muscle earns four, so the prompt must not flip after three.
(:test)
function testLoopPromptFollowsTheEngineCount(logger) as Lang.Boolean {
    var history = [ loopSet("bench_press", 100.0, 8, 2, LOOP_NOW - 86400) ];
    var loop = loopNew(history, {});

    loop.start();
    loop.pick("bench_press", LOOP_NOW);
    var recommended = loop.recommended;

    var sameWhileSetsRemain = true;
    for (var i = 0; i < recommended - 1; i++) {
        loop.openSheet();
        loop.bankSet(100.0, 8, 2, LOOP_NOW + i * 200);
        loop.restFinished();
        sameWhileSetsRemain = sameWhileSetsRemain && loop.prompt() == PromptRow.SAME;
        loop.continueSame();
    }

    loop.openSheet();
    loop.bankSet(100.0, 8, 2, LOOP_NOW + recommended * 200);
    loop.restFinished();

    logger.debug("engine count: " + recommended.toString() + " same=" + sameWhileSetsRemain.toString() +
        " then=" + loop.prompt().toString());

    return recommended == 4 && sameWhileSetsRemain && loop.prompt() == PromptRow.DIFFERENT;
}

// A muscle already at 12 weekly sets earns three, not four: the count moves in
// both directions, which is what "comes from the engine" has to mean.
(:test)
function testLoopRecommendedSetsDropForALoadedMuscle(logger) as Lang.Boolean {
    var history = [] as Lang.Array;
    for (var i = 0; i < 12; i++) {
        history.add(loopSet("bench_press", 100.0, 8, 2, LOOP_NOW - 3600));
    }

    var loop = loopNew(history, {});
    loop.start();
    loop.pick("bench_press", LOOP_NOW);

    logger.debug("loaded muscle asks for " + loop.recommended.toString() + " sets");
    return loop.recommended == 3;
}

// ---- load ------------------------------------------------------------------

// No history, no seeds: the fallback seed, held to the exercise's own floor.
(:test)
function testLoopUntrainedLiftGetsTheSeed(logger) as Lang.Boolean {
    var loop = loopNew([], {});
    loop.start();
    loop.pick("bench_press", LOOP_NOW);

    logger.debug("seed: " + loop.loadLabel());
    return loop.weight > 19.9 && loop.weight < 20.1 && loop.reps == 8;
}

// A lift whose floor is heavier than the seed starts at the floor: 40 kg cannot
// be rounded down to 20 just because the seed is a guess.
(:test)
function testLoopFloorWinsOverTheSeed(logger) as Lang.Boolean {
    var loop = loopNew([], {});
    loop.start();
    loop.pick("squats", LOOP_NOW);

    logger.debug("floor: " + loop.loadLabel());
    return loop.weight > 39.9 && loop.weight < 40.1;
}

// Bodyweight is a load, and a plate on it is body mass plus the plate.
(:test)
function testLoopBodyweightLiftShowsBw(logger) as Lang.Boolean {
    var loop = loopNew([], {});
    loop.start();
    loop.pick("pull_ups", LOOP_NOW);

    var empty = Text.same(loop.loadLabel(), "BW");
    var atZero = loop.weight == 0.0;

    loop.adjustWeight(1);
    var loaded = loop.loadLabel().find("BW +") == 0 && loop.weight > 2.4 && loop.weight < 2.6;

    logger.debug("bodyweight: " + empty.toString() + " then " + loop.loadLabel());
    return empty && atZero && loaded;
}

// The phone's recommendation wins over the watch's own arithmetic, and is still
// held to the exercise's floor.
(:test)
function testLoopPrefersThePhoneLoad(logger) as Lang.Boolean {
    var phone = { "bench_press" => 90.0 };
    var loop = loopNew([], phone);
    loop.start();
    loop.pick("bench_press", LOOP_NOW);
    var fromPhone = loop.weight > 89.9 && loop.weight < 90.1;

    var low = { "bench_press" => 5.0 };
    var clamped = loopNew([], low);
    clamped.start();
    clamped.pick("bench_press", LOOP_NOW);

    logger.debug("phone: " + fromPhone.toString() + " clamped=" + clamped.loadLabel());
    return fromPhone && clamped.weight > 19.9 && clamped.weight < 20.1;
}

// ---- the catalogue ---------------------------------------------------------

// The translation from what the phone sends to what Engine reads. A rep target
// that arrives as 10.0 must become the whole number 10, or the screen prints
// "10.000000"; bodyweight has to survive the trip, because `lib` does not carry
// it.
(:test)
function testLoopSpecsFromLibraryEntries(logger) as Lang.Boolean {
    var entry = {
        "id" => "pull_ups",
        "name" => "Pull-ups",
        "short" => "Pull-ups",
        "reps" => 10.0,
        "lo" => 6.0,
        "hi" => 10.0,
        "rest" => 120.0,
        "inc" => 2.5,
        "minW" => 0.0,
        "mus" => [["lats", 0.8]]
    };

    var specs = TrainingLoop.specsFrom([entry]);
    var spec = specs[0];
    var hi = spec[:hi];
    var primary = spec[:primary];

    var whole = hi == 10 && !(hi instanceof Lang.Float);
    var bodyweight = spec[:bw] > 0.9;
    var muscle = primary["lats"] != null && primary["lats"] > 0.7;

    logger.debug("spec: hi=" + hi.toString() + " rest=" + spec[:rest].toString() + " bw=" + spec[:bw].toString());
    return specs.size() == 1 && whole && bodyweight && muscle && spec[:rest] == 120;
}

// ---- the sheet -------------------------------------------------------------

// RIR is the only row usually worth touching on a repeat set, so the sheet opens
// focused there - the repeatSet contract SetSheet already has, now driven by the
// loop's own tally rather than by a caller's guess.
(:test)
function testLoopSheetOpensOnRirAfterASet(logger) as Lang.Boolean {
    var loop = loopNew([], {});
    loop.start();
    loop.pick("bench_press", LOOP_NOW);

    loop.openSheet();
    var first = loop.sheet.focus();

    loop.bankSet(100.0, 8, 2, LOOP_NOW);
    loop.restFinished();
    loop.continueSame();
    loop.openSheet();
    var second = loop.sheet.focus();

    logger.debug("sheet focus: " + first.toString() + " then " + second.toString());
    return first == SheetField.WEIGHT && second == SheetField.RIR;
}

// A lift picked twice in one session continues its count: the picker is not a
// reset button.
(:test)
function testLoopKeepsTheTallyAcrossVisits(logger) as Lang.Boolean {
    var loop = loopNew([], {});
    loop.start();
    loop.pick("bench_press", LOOP_NOW);
    loop.openSheet();
    loop.bankSet(100.0, 8, 2, LOOP_NOW);
    loop.restFinished();
    loop.chooseDifferent();

    loop.pick("bench_press", LOOP_NOW + 300);

    logger.debug("tally across visits: " + loop.done.toString() + " total " + loop.totalSets().toString());
    return loop.done == 1 && loop.totalSets() == 1 && loop.setsFor("bench_press") == 1;
}

// ---- rest ------------------------------------------------------------------

// The rest is the exercise's own interval, not one number for the session.
(:test)
function testLoopRestIsTheExercisesOwn(logger) as Lang.Boolean {
    var loop = loopNew([], {});

    loop.start();
    loop.pick("bench_press", LOOP_NOW);
    loop.openSheet();
    loop.bankSet(100.0, 8, 2, LOOP_NOW);
    var bench = loop.restRemaining(LOOP_NOW);

    loop.restFinished();
    loop.chooseDifferent();
    loop.pick("squats", LOOP_NOW);
    loop.openSheet();
    loop.bankSet(60.0, 6, 2, LOOP_NOW);
    var squat = loop.restRemaining(LOOP_NOW);

    logger.debug("rest: bench " + bench.toString() + "s squat " + squat.toString() + "s");
    return bench == 150 && squat == 180;
}

// ---- the log and the wire --------------------------------------------------

// The set the sheet accepted is the set in Storage and the set on the wire, with
// the RIR the user confirmed. This is the half of issue #3 that a sheet alone
// did not fix: a correct RIR on the wrist that reaches the phone as -1 cannot
// move the next load.
(:test)
function testLoopBankedSetReachesLogAndBusWithItsRir(logger) as Lang.Boolean {
    Wire.reset();
    StriveApp.outbox.reset();
    Session.end();

    var loop = loopNew([], {});
    loop.start();
    loop.pick("bench_press", LOOP_NOW);
    loop.openSheet();

    var set = { :weight => 102.5, :reps => 6, :rir => 1 };
    loop.bankSet(set[:weight], set[:reps], set[:rir], LOOP_NOW);
    StriveApp.recordSet(loop, set);

    var entries = Session.entries();
    var logged = Session.active() && entries.size() == 1 && entries[0][:rir] == 1 &&
        entries[0][:reps] == 6 && entries[0][:weight] > 102.4 && entries[0][:weight] < 102.6;

    var sent = Wire.sent.size() == 0 ? "" : Wire.sent[Wire.sent.size() - 1];
    var onWire = sent.find("\"rir\":1") != null && sent.find("\"ex\":\"bench_press\"") != null;
    var started = Wire.sent.size() >= 2 && Wire.sent[0].find("\"k\":\"start\"") != null;

    logger.debug("banked: logged=" + logged.toString() + " wire=" + Text.fit(sent, 24));

    Session.end();
    return logged && onWire && started;
}

// A set the user never rated keeps saying so. -1 is the phone's "not recorded",
// and inventing a 2 here is what makes an e1rm a guess.
(:test)
function testLoopSetWithoutRirSendsMinusOne(logger) as Lang.Boolean {
    Wire.reset();
    StriveApp.outbox.reset();
    Session.end();

    Session.start();
    Session.addSet("bench_press", 100.0, 8);
    Bus.sendSet(0);

    var sent = Wire.sent.size() == 0 ? "" : Wire.sent[Wire.sent.size() - 1];
    var ok = sent.find("\"rir\":-1") != null;

    logger.debug("unrated: " + Text.fit(sent, 24));
    Session.end();
    return ok;
}
