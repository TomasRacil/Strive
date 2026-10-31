using Toybox.Test;
using Toybox.Lang;

// The set sheet's state machine: which row is focused, what the values clamp to,
// and what accept() hands back.
//
// Nothing here draws. The sheet exists as a model precisely so the part that can
// be wrong silently - a weight going negative, a RIR past 4, START banking on the
// second row - is testable in the simulator, where a screen is not.

function sheetAdvice() {
    return { :weight => 100.0, :reps => 8 };
}

(:test)
function testSetSheetDefaults(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, false);
    logger.debug("defaults: " + sheet.weight().format("%.1f") + "x" + sheet.reps().toString() + " rir " + sheet.rir().toString());

    return sheet.focus() == SheetField.WEIGHT &&
        sheet.weight() > 99.9 && sheet.weight() < 100.1 &&
        sheet.reps() == 8 &&
        sheet.rir() == 2 &&
        !sheet.isCancelled();
}

// RIR is the only row usually worth touching on a repeat set, so it opens
// focused there and the user does not have to walk past weight and reps.
(:test)
function testSetSheetRepeatOpensOnRir(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, true);
    logger.debug("repeat focus: " + sheet.focus().toString());
    return sheet.focus() == SheetField.RIR;
}

(:test)
function testSetSheetWalksTheRows(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, false);

    var first = sheet.next();
    var second = sheet.next();
    var atEnd = sheet.next();
    var back = sheet.previous();

    logger.debug("walk: " + first.toString() + second.toString() + atEnd.toString() + back.toString());
    return first && second && !atEnd && back && sheet.focus() == SheetField.REPS;
}

(:test)
function testSetSheetPreviousStopsAtTheTop(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, false);
    return !sheet.previous() && sheet.focus() == SheetField.WEIGHT;
}

(:test)
function testSetSheetWeightMovesByTheIncrement(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, false);
    sheet.adjust(1);
    sheet.adjust(1);
    var up = sheet.weight();
    sheet.adjust(-1);
    var down = sheet.weight();

    logger.debug("weight: " + up.format("%.1f") + " then " + down.format("%.1f"));
    return up > 104.9 && up < 105.1 && down > 102.4 && down < 102.6;
}

(:test)
function testSetSheetWeightNeverGoesNegative(logger) as Lang.Boolean {
    var sheet = new SetSheet({ :weight => 2.5, :reps => 8 }, 2.5, false);
    for (var i = 0; i < 5; i++) {
        sheet.adjust(-1);
    }
    logger.debug("floor: " + sheet.weight().format("%.1f"));
    return sheet.weight() >= 0.0 && sheet.weight() < 0.01;
}

(:test)
function testSetSheetRepsClamp(logger) as Lang.Boolean {
    var sheet = new SetSheet({ :weight => 100.0, :reps => 100 }, 2.5, false);
    sheet.next();

    sheet.adjust(1);
    var high = sheet.reps();

    for (var i = 0; i < 120; i++) {
        sheet.adjust(-1);
    }
    var low = sheet.reps();

    logger.debug("reps: " + high.toString() + " .. " + low.toString());
    return high == 100 && low == 1;
}

(:test)
function testSetSheetRirClampsToZeroAndFour(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, true);

    sheet.adjust(1);
    sheet.adjust(1);
    var high = sheet.rir();
    sheet.adjust(1);
    var capped = sheet.rir();

    for (var i = 0; i < 10; i++) {
        sheet.adjust(-1);
    }
    var low = sheet.rir();

    logger.debug("rir: " + high.toString() + " " + capped.toString() + " " + low.toString());
    return high == 4 && capped == 4 && low == 0;
}

(:test)
function testSetSheetAcceptReturnsWhatWasSet(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, false);
    sheet.adjust(1);
    sheet.next();
    sheet.adjust(-1);
    sheet.next();
    sheet.adjust(-1);

    var set = sheet.accept();
    logger.debug("accepted: " + set[:weight].format("%.1f") + "x" + set[:reps].toString() + " rir " + set[:rir].toString());

    return set != null &&
        set[:weight] > 102.4 && set[:weight] < 102.6 &&
        set[:reps] == 7 &&
        set[:rir] == 1;
}

// BACK is an answer, not a no-op: a cancelled sheet must not log work that was
// not done.
(:test)
function testSetSheetCancelBanksNothing(logger) as Lang.Boolean {
    var sheet = new SetSheet(sheetAdvice(), 2.5, false);
    sheet.cancel();

    return sheet.isCancelled() && sheet.accept() == null;
}
