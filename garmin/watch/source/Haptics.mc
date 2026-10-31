using Toybox.Attention as Attention;
using Toybox.Lang;

// The four buzzes from docs/watch-ux.md.
//
// They have to be told apart by feel, because the wrist is often under a sleeve
// or behind a bar: one pulse means a set is banked, two mean the rate is back,
// three mean the rest is over, and the single long one means the sync failed and
// needs the user. The failure pattern shares no rhythm with the rest on purpose.
//
// A VibeProfile is (duty cycle 0..100, length in ms) on this firmware. The gaps
// are zero-duty profiles of the same kind, which is how the training screen
// already writes its buzz.
module Haptics {

    const DUTY = 60;
    const QUIET = 0;
    const SHORT_MS = 60;
    const GAP_MS = 100;
    const LONG_MS = 400;

    function available() as Lang.Boolean {
        return Attention has :vibrate;
    }

    // Set banked: one short pulse.
    function setBanked() as Void {
        emit([new Attention.VibeProfile(DUTY, SHORT_MS)]);
    }

    // Heart rate back under target: two pulses, once.
    function ready() as Void {
        emit([pulse(), gap(), pulse()]);
    }

    // Rest over: three pulses.
    function restOver() as Void {
        emit([pulse(), gap(), pulse(), gap(), pulse()]);
    }

    // Sync failure: one long pulse. Deliberately unlike the other three.
    function syncFailure() as Void {
        emit([new Attention.VibeProfile(DUTY, LONG_MS)]);
    }

    function pulse() {
        return new Attention.VibeProfile(DUTY, SHORT_MS);
    }

    function gap() {
        return new Attention.VibeProfile(QUIET, GAP_MS);
    }

    function emit(profiles) as Void {
        if (!(Attention has :vibrate)) {
            return;
        }
        try {
            Attention.vibrate(profiles);
        } catch (e) {
            // A watch that refuses to buzz must not lose the set over it.
        }
    }
}
