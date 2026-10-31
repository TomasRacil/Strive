# The training engine

One set of formulas, implemented twice: Kotlin for the phone, Monkey C for the
watch. The watch must be able to recommend, rest-time and log without a phone, so
there is no way around the second implementation — the defence against the two
drifting is `shared/engine-vectors.json`, a table of inputs and expected outputs
that both test suites run.

Canonical implementation: `mobile/app/src/main/java/com/strive/mobile/data/Engine.kt`.
Port: `garmin/watch/source/Engine.mc`. Vector generator:
`tools/gen_engine_vectors.py` writes `garmin/watch/test/Vectors.mc` from the JSON
so the watch tests do not need a JSON parser for their own fixtures.

All weights are kilograms. All reps are whole numbers. RIR is "reps in reserve":
0 means the set ended at failure, 4 means four more were possible.

## 1. Estimating strength

    effectiveReps = reps + rir
    e1rm          = weight * (1 + effectiveReps / 30)

Epley with RIR counted as reps not taken. `reps + rir` is clamped to 30: beyond
that the estimate explodes and the input is more likely wrong than extreme. For a
bodyweight movement the same formula runs on body mass times the movement's
bodyweight fraction (push-up 0.65, squat 0.85, pull-up 1.0) plus any external
load: a plate on a pull-up adds to the mass moved instead of replacing it, so
+2.5 kg on an 80 kg lifter is 82.5 kg and not 2.5 kg. Session tonnage is that
same load times reps, so a calisthenics session counts the body it moved; the
watch's `end` message still reports external-load tonnage only, and the phone
recomputes the priced figure from the log.

Body mass comes from the profile. Before onboarding has asked for it, the engine
uses `DEFAULT_BODY_KG = 80`, one constant in each implementation: without a body
mass every pull-up set scores e1rm 0 and progression for bodyweight work becomes a
coin toss. Callers pass the real weight as soon as they have it.

## 2. Next load for one exercise

Input: the sets logged for this exercise in the most recent session that
contains it, oldest first. Each set is `{weight, reps, rir}`, and the caller also
passes the user's body mass for the e1rm above.

    top = the set with the highest e1rm in that session
          (ties: more reps first, then more reps in reserve)

    if top.reps >= hi and top.rir >= 2   -> weight + inc
    if top.reps >= hi and top.rir == 1   -> weight          (one more time at this load)
    if top.rir <= 0 and top.reps < lo    -> weight - inc
    otherwise                            -> weight

The e1rm is the bodyweight-aware one, so 15 pull-ups at 3 in reserve is a better
set than 15 at failure: same reps, more left in the tank, and the first one earns
the increment.

Then round to the nearest multiple of `inc` and clamp to at least `minW` (empty
bar 20 kg for barbell movements, 2.5 kg for accessory work). `inc` defaults to
2.5 kg for upper body and 5 kg for lower body compounds; it is a property of the
exercise, pushed in the library.

Target reps for the next session: `lo` whenever the load changes, `hi` only when
it is held. The point of a rep range is to earn the increment before taking it,
and a deload rebuilds the same way — from the bottom of the range, so the reps
come back before the plates do.

No history at all is not an error: fall back to the seed in section 5.

## 3. How many sets

    sets = 3
    if the muscle's weekly load is under 8 sets -> 4
    if the user has never trained the exercise -> 3

Capped at 5, floored at 2. Inside a planned workout the plan's own number wins;
this only applies to free training.

## 4. Muscle load and what to recommend

Every exercise declares its muscles with a share (primary 1.0, secondary 0.6, as
`Exercise.loadByMuscle()` already does on the phone).

For each muscle, over the last 7 days:

    load(m) = sum over sets s touching m of
                  share(s, m) * effort(s) * 0.5 ^ (ageDays(s) / 2.5)

    effort(s) = 1.2 if rir <= 1, 1.0 if rir is 2-3, 0.8 if rir >= 4

    recovery(m) = clamp(1 - load(m) / 12, 0, 1)

Twelve "effective sets" is a hard week for one muscle, so it is the point where
recovery reaches zero. The 2.5-day half-life is why a muscle trained two days ago
is still at 58% of its load and one trained six days ago at 19%.

Exercise priority:

    score = mean over the exercise's muscles of recovery(m)
          + 0.15 * min(daysSinceLastTrained, 7) / 7
          + 0.10 * min(timesTrainedIn28Days, 8) / 8

    exclude an exercise whose primary muscle has recovery < 0.25

    order by score descending, tie-break on library order

`daysSinceLastTrained` is the age of the newest set of that exercise, not the
oldest: the term is asking how long the muscle has had to recover. Taking the
oldest would read a lift trained this morning as stale, and the more often it came
up the more of the 0.15 it would collect. Never trained means 7.

The first term is the user's rule — least-loaded muscles first. The second keeps
a lift that has not come up in a week from being buried. The third is the
"often done" preference. Weights 0.15 and 0.10 are choices, not measurements:
they are small enough that recovery dominates, which is the stated intent.

## 5. Seeds: the first session must not be a guess

Before any history exists the app runs a calibration: push-ups and bodyweight
squats, taken to RIR 1, reps recorded.

    e1rm(pushup) = bodyKg * 0.65 * (1 + reps / 30)
    e1rm(squat)  = bodyKg * 0.85 * (1 + reps / 30)

Then every barbell movement seeds from the matching pattern at 65% of that
estimate, rounded to `inc`:

    bench press, overhead press, row      <- pushup e1rm * 0.65
    squat, deadlift, leg press            <- squat e1rm * 0.65
    anything unmapped                     <- 20 kg, or the exercise's minW

65% is deliberately conservative: the first session should end with reps in
reserve, because the point of it is to produce a number to progress from, not to
find a limit.

## 6. Rest, and what the heart rate is for

    base   = exercise.restSeconds        (library or plan)
    target = restHr + 0.40 * (peakHr - restHr)

`peakHr` is the highest heart rate seen from the start of the set until 20 s after
it was banked. `restHr` is the profile's resting rate (default 60). The target is
40% of heart-rate reserve — the usual "ready for the next set" band for
hypertrophy work.

    rest = base
    if heart rate is available and still above target at base
        -> extend in 15 s steps, at most to base * 1.5
    if heart rate reaches target before base
        -> keep counting down, but mark READY and buzz once
    never below 30 s

With no heart rate (`Sensor.getInfo().heartRate` is null — it is null in the
simulator, and null whenever the strap is off) the rest is exactly `base`. A
missing sensor must never delay or shorten a rest.

Heart rate is displayed during rest regardless of whether it changed the length,
so the user can see why the watch is waiting.

## 7. What this engine deliberately does not do

- No RPE, no velocity, no autoregulation beyond RIR.
- No per-muscle volume targets, only recovery.
- No deload weeks. A lift that fails three sessions in a row holds its load
  (section 2, `top.rir <= 0 and top.reps >= lo`), which is the whole deload
  policy for now.
