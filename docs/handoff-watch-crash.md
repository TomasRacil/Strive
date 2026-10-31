# Handoff: the watch crash after Free training

Written at the point the session was stopped, so the next one starts from the
state rather than from the story.

## What works

- Master is green: PWA lint + tests, Android unit tests + debug APK (CI), and the
  watch app compiles to `Strive-fenix847mm.prg`.
- Phone app on the Pixel 9 Pro: Home shows engine-ranked suggestions with real
  imported history ("Overhead Press 50.0 kg, shoulders rested 16 days").
- Watch app sideloaded: Home renders, "Free training" opens, and the phone found
  the watch (`fenix 8 - 47mm, AMOLED`, Connected, "Strive app on watch:
  installed"). So the bus, the app id and the pairing all work.

## The bug

Anything past the picker's first screen kills the app on the watch: the Connect
IQ icon with an exclamation mark. Pressing DOWN in the picker does it, and START
does it. Nothing has produced an error message yet.

## What was ruled out, and how

- Not the history size: the phone caps `hist` at 40 exercises x 3 sets.
- Not a null name or a null load: `Text.fit` and `TrainingLoop.name()` both guard.
- Not the radio: `Wire` now starts stubbed and `StriveApp.onStart` opts in.
- The exception guards on the picker and exercise screen never ran, because the
  build carrying them never reached the watch — see below.

## The tooling fault that wasted the most time

`deploy.ps1` reported `Copied ... (0 bytes)` on every attempt and I treated that
as success. A truncated MTP write leaves the previous build on the watch, so
"same problem" was measured against code that was never installed. `deploy.ps1`
now polls the device until the reported size matches the build and exits
non-zero otherwise. **Verify the byte count before asking for a test.**

The watch drops off MTP within seconds of its screen locking, so it has to be
awake and unlocked for the whole copy.

## The simulator

It ran 14, 30 and 61 tests green earlier in the day and then wedged: it starts,
accepts `monkeydo`'s connection on port 1234, and answers nothing — even for a
single known-good test. Killed and restarted repeatedly, different device id,
cleared `build/.simlock`, longer boot waits, bounded attempts. Its UI thread is
unresponsive to the accessibility tree as well. A reboot is the documented cure
and has not been tried.

Until it is back, the watch suite (117 tests) is compiled but unverified.

## The next three steps

1. Deploy with the watch awake and confirm "matches the build".
2. Open Free training, press DOWN, then reopen the app and read the orange
   breadcrumb at the bottom of Home. It names the last step that returned:
   `rank`, `rank ok`, `mv`, `mv ok`, `paint`, `paint ok`, `take`, `picked`.
3. Fix what that names. `mv` without `mv ok` means it dies inside
   `Engine.rank`; `paint` without `paint ok` means a row is being drawn with
   something the engine did not expect.

If the breadcrumb is missing entirely, the build still has not landed and step 1
is the whole problem.

## Open issues

- #20 planned workout mode, #21 calibration: deliberately not started. Both
  rewrite `TrainingLoop` and `StriveApp`, which is exactly the code that has
  never run on hardware.
