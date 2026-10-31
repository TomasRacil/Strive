using Toybox.Lang;

// The set confirmation sheet, as state only.
//
// The sheet is a three-row form: weight, reps, RIR, one row focused. Keeping it
// free of Graphics is what makes the focus walk and the clamping testable in the
// simulator, where a drawn screen is not.
//
// Everything the user does is a keypress on one of those rows, so the model's
// whole vocabulary is next / previous / adjust, plus accept and cancel.

// Which row the sheet is on. A module rather than class constants because a
// class constant cannot be read from outside the class, and the tests have to
// say which row they mean.
module SheetField {
    const WEIGHT = 0;
    const REPS = 1;
    const RIR = 2;
    const COUNT = 3;
}

class SetSheet {

    // A set outside these bounds is a typo, not a set. RIR 0..4 is the range a
    // lifter can honestly judge; reps past 100 is a different exercise.
    const MIN_RIR = 0;
    const MAX_RIR = 4;
    const MIN_REPS = 1;
    const MAX_REPS = 100;

    // Where the sheet opens when nothing else is known: two reps in reserve is
    // the middle of the range and what most working sets land on.
    const DEFAULT_RIR = 2;

    var cursor;
    var weightValue;
    var repsValue;
    var rirValue;
    var step;
    var cancelled;

    // `advice` is the engine's recommendation, { :weight, :reps }. `increment`
    // is the exercise's plate step, so UP moves by what can actually be loaded.
    // `repeatSet` is true when this is not the first set of the exercise: RIR is
    // then the only row usually worth touching, so it opens focused.
    function initialize(advice, increment, repeatSet) {
        var weight = advice[:weight];
        var reps = advice[:reps];

        weightValue = weight == null ? 0.0 : weight;
        repsValue = reps == null ? MIN_REPS : clampReps(reps);
        rirValue = DEFAULT_RIR;
        step = increment == null ? 0.0 : increment;
        cancelled = false;
        cursor = repeatSet ? SheetField.RIR : SheetField.WEIGHT;
    }

    function focus() as Lang.Number {
        return cursor;
    }

    function weight() {
        return weightValue;
    }

    function reps() as Lang.Number {
        return repsValue;
    }

    function rir() as Lang.Number {
        return rirValue;
    }

    function isCancelled() as Lang.Boolean {
        return cancelled;
    }

    // False when there is no row left: START on the last row is the bank.
    function next() as Lang.Boolean {
        if (cursor >= SheetField.COUNT - 1) {
            return false;
        }
        cursor += 1;
        return true;
    }

    function previous() as Lang.Boolean {
        if (cursor <= 0) {
            return false;
        }
        cursor -= 1;
        return true;
    }

    // `direction` is +1 or -1. The weight moves by the exercise's increment;
    // reps and RIR by one, because half a rep is not a rep.
    function adjust(direction) as Void {
        if (direction == 0) {
            return;
        }

        if (cursor == SheetField.WEIGHT) {
            // A spec that forgot its increment leaves the load alone rather than
            // making UP a no-op that looks like a broken button.
            if (step > 0.0) {
                var moved = weightValue + step * direction.toFloat();
                weightValue = moved < 0.0 ? 0.0 : moved;
            }
            return;
        }

        if (cursor == SheetField.REPS) {
            repsValue = clampReps(repsValue + direction);
            return;
        }

        rirValue = clampRir(rirValue + direction);
    }

    // The set to bank, or null after a cancel: a sheet the user backed out of
    // must never log work that was not done.
    function accept() {
        if (cancelled) {
            return null;
        }
        return { :weight => weightValue, :reps => repsValue, :rir => rirValue };
    }

    function cancel() as Void {
        cancelled = true;
    }

    function clampRir(value) as Lang.Number {
        if (value < MIN_RIR) {
            return MIN_RIR;
        }
        return value > MAX_RIR ? MAX_RIR : value;
    }

    function clampReps(value) as Lang.Number {
        if (value < MIN_REPS) {
            return MIN_REPS;
        }
        return value > MAX_REPS ? MAX_REPS : value;
    }
}
