using Toybox.Lang;

// Exercise list lives in code: a sideloaded app cannot rely on settings
// delivered through Garmin Connect Mobile, and resources cannot be edited
// without rebuilding.
//
// `:bw` is the movement's fraction of body mass, and it is the one thing the
// phone's library snapshot cannot tell the watch: `lib` carries id, name, rep
// range, rest, increment and muscle shares, but not which movements are
// bodyweight. The compiled list is therefore the authority on that, keyed by id,
// for both the fallback list and the phone's.
module Exercises {

    const BW_PULL_UP = 1.0;

    function list() {
        return [
            { :id => "bench_press",    :name => "Bench Press",    :reps => 8,  :rest => 150, :bw => 0.0 },
            { :id => "squats",         :name => "Squats",         :reps => 6,  :rest => 180, :bw => 0.0 },
            { :id => "deadlift",       :name => "Deadlift",       :reps => 5,  :rest => 180, :bw => 0.0 },
            { :id => "overhead_press", :name => "Overhead Press", :reps => 8,  :rest => 120, :bw => 0.0 },
            { :id => "pull_ups",       :name => "Pull-ups",       :reps => 8,  :rest => 120, :bw => BW_PULL_UP },
            { :id => "bicep_curls",    :name => "Curls",          :reps => 10, :rest => 90,  :bw => 0.0 }
        ];
    }

    function count() {
        return list().size();
    }

    // 0.0 means "loaded lift": a spec with no fraction is priced at the weight
    // on the bar alone, which is what Engine.e1rmBodyweight does with it.
    function bwFor(id) as Lang.Float {
        var all = list();
        for (var i = 0; i < all.size(); i++) {
            if (Text.same(all[i][:id], id)) {
                return all[i][:bw];
            }
        }
        return 0.0;
    }
}
