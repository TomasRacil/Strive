# Watch app flows

What the wrist actually does, screen by screen. This is the behaviour the UI PRs
implement; the formulas behind the numbers are in `training-engine.md` and the
transport in `watch-protocol.md`.

Design constraints that decide most of what follows:

- **Gloves and sweat.** Buttons first. Every action reachable with UP, DOWN and
  START. Touch is a shortcut, never the only way.
- **No phone.** Recommendation, set logging, rest timing and the session log all
  work with the phone in another room. The phone only makes recommendations
  better and the history permanent.
- **Never lose a set.** Every accepted set is written to Storage before anything
  is drawn, and queued for the phone before it is sent.
- **One thumb, one glance.** Nothing on screen needs reading twice mid-set.

## Buttons

    UP / DOWN      move the highlight, or change the highlighted value
    START          confirm / advance / log the set
    BACK           one level up; opens the action menu on the exercise screen
    swipe L / R    previous / next screen in a list
    tap            acts on the tapped row

## Home

    Free training
    Workout: Push A          (only when the phone has pushed a plan)
    Calibrate                (only until it has been done once)
    History                  (last five sessions, read-only)

First item highlighted. START opens it.

The very first launch after install has no history and no seeds, so `Calibrate`
is the highlighted item and the app says why: *"Two minutes to set your starting
weights."* Everything still works without calibrating — the seed falls back to
`minW` — but the recommendations are guesses until it is done.

## Free training

### 1. Pick an exercise

    Bench Press          100.0 kg   3 x 8
    Squats                82.5 kg   3 x 6
    Pull-ups               BW       3 x 8
    ---
    All exercises >

The first three rows are the engine's ranking: least-loaded muscles first, with
a nudge for lifts that have not come up in a week and for ones done often. Each
row shows the recommended load and sets. `All exercises` opens the full library,
scrolled with UP/DOWN, one line per exercise, filtered to nothing — the user may
train whatever they want.

If the phone is connected and has sent `rec`, those numbers win; otherwise the
watch computes the same thing from its own history (`hist`) and its own log.

### 2. Do the set

    Bench Press
        100.0 kg
        8 reps        1/3
        [START: log set]

UP/DOWN adjust the load by the exercise's increment. START opens the set
confirm sheet, pre-filled with what the app expects:

    Weight   100.0 kg
    Reps          8
    RIR           2

UP/DOWN change the highlighted row, START moves to the next row, and START on
the last row banks the set. BACK cancels and nothing is logged. RIR defaults to
2 and is the only field the user usually has to touch, so it is the row that
gets the highlight first when the sheet opens on a repeat set of the same
exercise.

### 3. Rest

    REST           1:42
    HR 148 -> 132
    ready at 132
    [START: skip]

The countdown is the engine's rest for that exercise, extended in 15 s steps
while the heart rate is still above 40% of heart-rate reserve, capped at 1.5x
the base. When the rate reaches the target the screen says READY and buzzes
once; the countdown keeps running to its own end because the user may want the
full rest anyway. START ends the rest immediately.

With no heart rate (strap off, or the sensor returning null) the screen shows no
HR line and the rest is exactly the base time.

### 4. Continue or change

When the rest ends:

    Continue Bench Press?
      > Yes, next set        (default while sets remain)
        Different exercise

The default is the engine's answer: while the recommended set count is not yet
reached, `Yes` is highlighted; once it is, `Different exercise` is. UP/DOWN move
the highlight, START takes it. `Yes` returns to the same exercise with the next
set pre-filled (weight from the engine's advice, reps target, RIR 2). `Different
exercise` returns to the picker, with the just-finished exercise's set count
already banked.

The user can also leave the prompt alone: nothing times out, nothing is lost, the
session stays open.

### 5. Finish

BACK on the exercise screen opens the action menu:

    End exercise
    Add exercise here
    Finish workout

`Finish workout` asks once ("Swipe to confirm" style: the second press within 5 s
confirms) and then shows the summary and queues the `end` message. `End exercise`
banks what was done and returns to the picker. `Add exercise here` inserts a lift
at the current position — useful mid-session, not only at the end.

## Workout mode

Same screens, three differences.

1. **The exercise order is the plan's.** After the last set of an item, the
   continue prompt defaults to the next planned item rather than to another set.
   The user may still take another set, skip ahead, or end an item early.
2. **Supersets alternate.** Items sharing a superset group (`ss`) run back to
   back with no rest between them; rest starts after the last member of the
   group. The screen shows `A1`, `A2` next to the name so it is obvious which
   half of the pair is next.
3. **Early finish is normal.** `Finish workout` is always available and banks
   whatever was done. A plan is a suggestion, not a contract.

Ending early and adding an exercise between items are both allowed at any point;
neither is a special case in the state machine — they are the same actions as in
free training.

## Summary

    Session done
    14 sets
    8 240 kg
    52:10
    sync ok | sync queued (3)
    BACK to close

The sync line is honest: `ok` only after the phone acknowledged the `end`
message, `queued (n)` while the outbox still holds it. A summary that claims
success without an ack would be a guess.

## Calibration

Three screens, one value each, all editable with UP/DOWN:

    Body weight     80 kg
    Push-ups        12      (to RIR 1, form good)
    Squats          25      (bodyweight, to RIR 1)

Then the seeds are computed (see `training-engine.md` §5), stored, and the app
returns to Home with `Calibrate` gone. The result is also queued as a `bench`
message so the phone can show where the starting numbers came from.

Re-running calibration is available from the action menu on Home ("Recalibrate")
for the case where the first attempt was a bad day.

## Haptics

Every state change that matters is also a buzz, because the screen is often
covered by a sleeve or a bar. Four patterns, distinguishable by feel alone:

    set banked        one short pulse          60 ms
    READY (HR back)   two short pulses         60 / 100 / 60 ms
    rest over         three short pulses       60 / 100 / 60 / 100 / 60 ms
    sync failure      one long pulse           400 ms

The failure pattern is deliberately unlike the others: it is the only one that
means "something needs you", and it must not be mistaken for a completed rest.

## Heart rate

`Sensor.getInfo().heartRate` is read once per second while a set is in progress
and while resting. The peak seen from the start of the set to 20 s after it was
banked is what the rest calculation uses. A null rate is normal and must never
block anything: it means the strap is off or the wrist sensor has no reading.

The watch's own optical sensor is enough for this; no strap is required.

## Not in this version

- No FIT activity is recorded. The session lives in Storage and reaches the phone
  as messages, not as a Garmin activity.
- No editing of a finished session on the watch. Fix it on the phone.
- No timer for isometric holds beyond the rest clock.
- No settings screen on the watch: units, language and profile come from the
  phone (`profile`), and the watch falls back to kg and English.
