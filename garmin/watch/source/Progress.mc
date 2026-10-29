using Toybox.Application as App;

// Local progression store.
//
// A Connect IQ app cannot read the Garmin Connect workout library or your
// history: there is no API for it from the watch. So the watch keeps its own
// record per exercise and progresses from what it saw last time.
//
// Only Float and Boolean values are stored, because Application.Storage
// supports primitives everywhere while dictionary support varies by API level.
module Progress {

    const STEP = 2.5;

    function weightKey(id) {
        return "w_" + id;
    }

    function okKey(id) {
        return "ok_" + id;
    }

    function lastWeight(id) {
        var value = App.Storage.getValue(weightKey(id));
        if (value == null) {
            return null;
        }
        return value;
    }

    function wasSuccessful(id) {
        return App.Storage.getValue(okKey(id)) == true;
    }

    // Double progression: repeat the same load until the target sets are
    // completed, then add one plate step. No RIR input on the wrist, so
    // "completed the work" is the only signal available.
    function suggest(id, fallback) {
        var previous = lastWeight(id);
        if (previous == null) {
            return fallback;
        }
        if (wasSuccessful(id)) {
            return previous + STEP;
        }
        return previous;
    }

    function record(id, weight, completed) {
        App.Storage.setValue(weightKey(id), weight);
        App.Storage.setValue(okKey(id), completed);
    }
}
