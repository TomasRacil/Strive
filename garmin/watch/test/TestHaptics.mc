using Toybox.Test;
using Toybox.Lang;

// The four haptic patterns.
//
// Nothing can be felt in the simulator, so this pins what can be pinned: the
// four patterns exist, they compile against this firmware's Attention API, and a
// device without a vibrator takes the guard instead of throwing. Whether two
// pulses feel different from three is a judgement for a wrist, not an assertion.

(:test)
function testHapticsSurviveWithoutAVibrator(logger) as Lang.Boolean {
    logger.debug("vibrate available: " + Haptics.available().toString());

    Haptics.setBanked();
    Haptics.ready();
    Haptics.restOver();
    Haptics.syncFailure();
    return true;
}
