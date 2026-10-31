using Toybox.Lang;
using Toybox.Sensor as Sensor;

// The peak heart rate for one set.
//
// How hard the set was decides how long the rest is, and the only measure of
// that on a wrist is the highest rate seen: from the start of the set until 20 s
// after it was banked, because the rate is still climbing when the bar goes
// down.
//
// A null reading is a strap that is off, not a rate of zero. It is dropped, so
// it can neither invent a peak nor pull a real one down.
class HrPeak {

    var peakHr;

    function initialize() {
        peakHr = null;
    }

    function sample(hr) as Void {
        if (hr == null) {
            return;
        }
        if (peakHr == null || hr > peakHr) {
            peakHr = hr;
        }
    }

    // The same, for the window after the set: a later sample belongs to the next
    // set's rest, not to this one.
    function sampleTail(hr, secondsSinceBank) as Void {
        if (secondsSinceBank > HeartRate.TAIL_SECONDS) {
            return;
        }
        sample(hr);
    }

    function peak() {
        return peakHr;
    }

    function reset() as Void {
        peakHr = null;
    }
}

module HeartRate {

    // How long after the set is banked its rate still counts towards the peak.
    const TAIL_SECONDS = 20;

    // Sensor.getInfo().heartRate is null in the simulator and null whenever the
    // strap is off, so null is an answer and not a failure. Reading it must never
    // be the thing that throws mid-set.
    function read() {
        try {
            var info = Sensor.getInfo();
            if (info == null) {
                return null;
            }
            return info.heartRate;
        } catch (e) {
            return null;
        }
    }
}
