// Exercise list lives in code: a sideloaded app cannot rely on settings
// delivered through Garmin Connect Mobile, and resources cannot be edited
// without rebuilding.
module Exercises {

    function list() {
        return [
            { :id => "bench_press",    :name => "Bench Press",    :reps => 8,  :rest => 150 },
            { :id => "squats",         :name => "Squats",         :reps => 6,  :rest => 180 },
            { :id => "deadlift",       :name => "Deadlift",       :reps => 5,  :rest => 180 },
            { :id => "overhead_press", :name => "Overhead Press", :reps => 8,  :rest => 120 },
            { :id => "pull_ups",       :name => "Pull-ups",       :reps => 8,  :rest => 120 },
            { :id => "bicep_curls",    :name => "Curls",          :reps => 10, :rest => 90 }
        ];
    }

    function count() {
        return list().size();
    }
}
