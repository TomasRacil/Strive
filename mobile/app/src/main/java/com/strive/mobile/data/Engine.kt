package com.strive.mobile.data

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.round

/**
 * What the engine needs to know about one lift.
 *
 * Deliberately not [Exercise]: the engine has to run in a unit test and on a
 * watch, so it takes the numbers it needs instead of the UI model. The rep
 * range, the increment and the floor are training decisions the library pushes
 * in - nothing about them can be derived from an exercise name.
 *
 * Weights are kilograms throughout; there is no unit handling here.
 */
data class EngineSpec(
    val id: String,
    /** Bottom of the rep range: the target after a load increase. */
    val lo: Int,
    /** Top of the rep range: the target while holding the load. */
    val hi: Int,
    val incrementKg: Double,
    /** Empty bar for barbells, the smallest plate the stack offers for the rest. */
    val minWeightKg: Double,
    val restSeconds: Int,
    val primary: Map<String, Double> = emptyMap(),
    val secondary: Map<String, Double> = emptyMap(),
    /** Which calibration measurement seeds it: "pushup", "squat", "pullup" or "". */
    val pattern: String = "",
    /** Share of body mass the movement moves; 0 for anything loaded with plates. */
    val bodyweightFraction: Double = 0.0
) {

    /**
     * Primary at face value, secondary at 60%, the same rule as
     * [Exercise.loadByMuscle]. Duplicated rather than shared because the engine
     * must not reach into the UI model - if the two ever disagree the vectors
     * catch it.
     */
    fun loadByMuscle(): Map<String, Double> {
        if (primary.isEmpty() && secondary.isEmpty()) return emptyMap()
        val out = mutableMapOf<String, Double>()
        primary.forEach { (muscle, share) -> out[muscle] = (out[muscle] ?: 0.0) + share }
        secondary.forEach { (muscle, share) -> out[muscle] = (out[muscle] ?: 0.0) + share * 0.6 }
        return out
    }

    /**
     * The muscle that gates the exercise, i.e. the one worth the most in
     * `primary`. Recovery of this one decides whether the lift may be excluded;
     * averaging every muscle would let a fresh stabiliser outvote a spent
     * prime mover.
     */
    fun primaryMuscle(): String? {
        var best: String? = null
        var bestShare = Double.NEGATIVE_INFINITY
        primary.forEach { (muscle, share) ->
            if (share > bestShare) {
                best = muscle
                bestShare = share
            }
        }
        return best
    }

    companion object {

        /**
         * Library defaults. `incrementKg` and `minWeightKg` are properties of
         * the exercise per the spec, so they live in one table instead of being
         * re-guessed at every call site.
         */
        private val DEFAULTS: Map<String, Defaults> = mapOf(
            // id -> lo, hi, inc, minW, pattern, bodyweight fraction
            "bench_press" to Defaults(6, 10, 2.5, 20.0, "pushup", 0.0),
            "squats" to Defaults(4, 8, 5.0, 20.0, "squat", 0.0),
            "deadlift" to Defaults(3, 6, 5.0, 20.0, "squat", 0.0),
            "overhead_press" to Defaults(6, 10, 2.5, 20.0, "pushup", 0.0),
            "pull_ups" to Defaults(6, 10, 2.5, 0.0, "pullup", 1.0),
            "bicep_curls" to Defaults(8, 12, 2.5, 2.5, "", 0.0)
        )

        private data class Defaults(
            val lo: Int,
            val hi: Int,
            val incrementKg: Double,
            val minWeightKg: Double,
            val pattern: String,
            val bodyweightFraction: Double
        )

        /**
         * Builds a spec from a library entry.
         *
         * Unknown exercises get a rep range of target +/- 2 and 2.5 kg steps,
         * or 5 kg when the entry is filed under Legs: lower-body compounds move
         * in bigger jumps, and the table above only covers the six shipped
         * lifts.
         */
        fun from(exercise: Exercise): EngineSpec {
            val known = DEFAULTS[exercise.id]
            val lowerBody = exercise.muscle == "Legs"
            return EngineSpec(
                id = exercise.id,
                lo = known?.lo ?: max(1, exercise.targetReps - 2),
                hi = known?.hi ?: (exercise.targetReps + 2),
                incrementKg = known?.incrementKg ?: if (lowerBody) 5.0 else 2.5,
                minWeightKg = known?.minWeightKg ?: if (lowerBody) 20.0 else 2.5,
                restSeconds = exercise.restSeconds,
                primary = exercise.primary,
                secondary = exercise.secondary,
                pattern = known?.pattern ?: "",
                bodyweightFraction = known?.bodyweightFraction ?: 0.0
            )
        }
    }
}

/** One logged set, as the progression rule sees it. */
data class EngineSet(val weightKg: Double, val reps: Int, val rir: Int?)

/** A logged set with the time it happened, for load and ranking. */
data class TimedSet(
    val exerciseId: String,
    val weightKg: Double,
    val reps: Int,
    val rir: Int?,
    val timestampEpochSeconds: Long
)

data class LoadAdvice(val weightKg: Double, val targetReps: Int)

data class RestAdvice(val seconds: Int, val ready: Boolean)

/** One entry of the recommendation list; `score` is only for display and ties. */
data class Ranked(val exerciseId: String, val score: Double)

/**
 * The training engine. Pure functions, no storage, no clock of its own - the
 * caller passes `now` so the result is reproducible and testable.
 *
 * This is the canonical implementation; `garmin/watch/source/Engine.mc` is the
 * port. They are held together by `shared/engine-vectors.json`, which both test
 * suites run, so a change here that the watch does not make fails a test rather
 * than shipping two different trainers.
 */
object Engine {

    /** Epley stops being an estimate past a rep range this long; the input is likelier wrong. */
    const val MAX_EFFECTIVE_REPS = 30

    /** Load halves every 2.5 days: 58% after two days, 19% after six. */
    const val RECOVERY_HALF_LIFE_DAYS = 2.5

    /** Sets older than this are history, not fatigue. */
    const val LOAD_WINDOW_DAYS = 7.0

    /** Effective sets in a week that drive recovery to zero. */
    const val HARD_WEEK_SETS = 12.0

    /** Below this a primary muscle is still wrecked and the lift is dropped. */
    const val RECOVERY_EXCLUSION = 0.25

    const val MIN_REST_SECONDS = 30
    const val REST_STEP_SECONDS = 15
    const val REST_EXTENSION_CAP = 1.5
    const val DEFAULT_RESTING_HR = 60
    const val HR_RESERVE_FRACTION = 0.40

    /** Body mass fractions of the calibration movements. */
    const val PUSHUP_FRACTION = 0.65
    const val SQUAT_FRACTION = 0.85

    /** The first session should end with reps in reserve, so it starts at 65%. */
    const val SEED_FRACTION = 0.65

    /** No seed available: an empty bar is the only honest guess. */
    const val FALLBACK_SEED_KG = 20.0

    private const val DAY_SECONDS = 86_400.0
    private const val DAYS_IN_WINDOW_28 = 28

    /** RIR nobody recorded is treated as "two in reserve" everywhere. */
    private const val ASSUMED_RIR = 2

    // ---- 1. strength -----------------------------------------------------

    /**
     * Epley with reps in reserve counted as reps not taken.
     *
     * Weight 0 is a bodyweight movement with no external load: the formula has
     * nothing to scale, so it returns 0 and callers that know the body mass use
     * the overload below.
     */
    fun e1rm(weightKg: Double, reps: Int, rir: Int): Double =
        e1rm(weightKg, reps, rir, 0.0, 0.0)

    /**
     * The bodyweight form: when no external load was logged, the mass moved is
     * body mass times the movement's fraction (push-up 0.65, squat 0.85,
     * pull-up 1.0). A logged weight always wins over the estimate.
     */
    fun e1rm(
        weightKg: Double,
        reps: Int,
        rir: Int,
        bodyKg: Double,
        bodyweightFraction: Double
    ): Double {
        val effectiveReps = (reps + rir).coerceIn(0, MAX_EFFECTIVE_REPS)
        val load = if (weightKg > 0.0) weightKg else bodyKg * bodyweightFraction
        return load * (1.0 + effectiveReps / 30.0)
    }

    // ---- 2. next load ----------------------------------------------------

    /**
     * The next load for one exercise, given the sets of the most recent session
     * that contains it, oldest first.
     *
     * Empty history is not an error: the caller's seed is used, aimed at the top
     * of the range because a seed is deliberately conservative.
     *
     * "top" is the set with the highest e1rm. Ties are broken towards more reps
     * and then less RIR, which only matters for bodyweight work where every set
     * has weight 0 and e1rm is therefore 0 for all of them - without a tie-break
     * the "top" set would be whichever was logged first.
     */
    fun nextLoad(spec: EngineSpec, history: List<EngineSet>, seedKg: Double): LoadAdvice {
        if (history.isEmpty()) {
            return LoadAdvice(
                weightKg = clampToSpec(seedKg, spec),
                targetReps = spec.hi
            )
        }

        val top = history.reduce { best, set -> if (betterSet(set, best)) set else best }
        val rir = top.rir ?: ASSUMED_RIR
        val base = top.weightKg

        val raw = when {
            top.reps >= spec.hi && rir >= 2 -> base + spec.incrementKg
            top.reps >= spec.hi && rir == 1 -> base
            rir <= 0 && top.reps < spec.lo -> base - spec.incrementKg
            else -> base
        }

        return LoadAdvice(
            weightKg = clampToSpec(raw, spec),
            // The point of a range is to earn the increment before taking it.
            targetReps = if (raw > base) spec.lo else spec.hi
        )
    }

    private fun betterSet(candidate: EngineSet, best: EngineSet): Boolean {
        val candidateE1rm = e1rm(candidate.weightKg, candidate.reps, candidate.rir ?: ASSUMED_RIR)
        val bestE1rm = e1rm(best.weightKg, best.reps, best.rir ?: ASSUMED_RIR)
        if (candidateE1rm != bestE1rm) return candidateE1rm > bestE1rm
        if (candidate.reps != best.reps) return candidate.reps > best.reps
        return (candidate.rir ?: ASSUMED_RIR) < (best.rir ?: ASSUMED_RIR)
    }

    // ---- 3. how many sets ------------------------------------------------

    /**
     * Free-training set count. A muscle under 8 weekly sets gets a fourth set;
     * a movement the user has never done stays at 3 however fresh the muscle is,
     * because the first session is about learning the lift, not volume.
     *
     * A planned workout uses the plan's own number - this is not called there.
     */
    fun recommendedSets(spec: EngineSpec, weeklyMuscleSets: Int, everTrained: Boolean = true): Int {
        var sets = 3
        if (weeklyMuscleSets < 8) sets = 4
        if (!everTrained) sets = 3
        return sets.coerceIn(2, 5)
    }

    // ---- 4. load, recovery, priority -------------------------------------

    /**
     * How hard each muscle has been worked in the last 7 days, in "effective
     * sets": a set counts for its muscle share, scaled by how close to failure
     * it was and by how long ago it was.
     *
     * Sets of exercises that are not in [specs] are skipped rather than thrown:
     * history outlives the library, and a deleted exercise must not crash the
     * recommendation.
     */
    fun muscleLoad(
        specs: Map<String, EngineSpec>,
        sets: List<TimedSet>,
        nowEpochSeconds: Long
    ): Map<String, Double> {
        val out = mutableMapOf<String, Double>()
        for (set in sets) {
            val spec = specs[set.exerciseId] ?: continue
            val ageDays = ageDays(set.timestampEpochSeconds, nowEpochSeconds)
            // A set from the future is clock skew, not extra fatigue.
            if (ageDays > LOAD_WINDOW_DAYS) continue

            val decay = 0.5.pow(ageDays / RECOVERY_HALF_LIFE_DAYS)
            val weight = effort(set.rir) * decay
            spec.loadByMuscle().forEach { (muscle, share) ->
                out[muscle] = (out[muscle] ?: 0.0) + share * weight
            }
        }
        return out
    }

    /** 1 is fully recovered, 0 is a muscle that cannot do another hard set. */
    fun recovery(load: Map<String, Double>): Map<String, Double> =
        load.mapValues { (_, value) -> (1.0 - value / HARD_WEEK_SETS).coerceIn(0.0, 1.0) }

    /**
     * The recommendation order for free training.
     *
     * Recovery of the exercise's muscles dominates; the recency and frequency
     * terms are small on purpose (0.15 and 0.10) so they only separate lifts
     * whose muscles are in the same state. Ties keep library order, which is why
     * this takes a list and not a map.
     */
    fun rank(
        specs: List<EngineSpec>,
        sets: List<TimedSet>,
        nowEpochSeconds: Long
    ): List<Ranked> {
        val load = muscleLoad(specs.associateBy { it.id }, sets, nowEpochSeconds)
        val recovered = recovery(load)

        val scored = specs.mapNotNull { spec ->
            val muscles = spec.loadByMuscle()
            val meanRecovery =
                if (muscles.isEmpty()) 1.0
                else muscles.keys.sumOf { recovered[it] ?: 1.0 } / muscles.size

            // Gated on the prime mover: a spent chest must bury the bench even
            // if the triceps are fresh.
            val gate = spec.primaryMuscle()?.let { recovered[it] ?: 1.0 } ?: 1.0
            if (gate < RECOVERY_EXCLUSION) return@mapNotNull null

            val mine = sets.filter { it.exerciseId == spec.id }
            val daysSince = mine.maxOfOrNull { ageDays(it.timestampEpochSeconds, nowEpochSeconds) }
                ?.coerceIn(0.0, 7.0) ?: 7.0
            val timesTrained = distinctTrainingDays(mine, nowEpochSeconds).coerceAtMost(8)

            val score = meanRecovery +
                0.15 * min(daysSince, 7.0) / 7.0 +
                0.10 * min(timesTrained.toDouble(), 8.0) / 8.0
            Ranked(spec.id, score)
        }

        // sortedByDescending is stable, so equal scores keep library order.
        return scored.sortedByDescending { it.score }
    }

    /**
     * Distinct days, not sets: eight sets in one session is one training day,
     * and the term is meant to say "this lift comes up often", not "this lift
     * gets a lot of sets".
     */
    private fun distinctTrainingDays(sets: List<TimedSet>, nowEpochSeconds: Long): Int {
        val from = nowEpochSeconds - DAYS_IN_WINDOW_28 * DAY_SECONDS.toLong()
        return sets.asSequence()
            .filter { it.timestampEpochSeconds in from..nowEpochSeconds }
            .map { it.timestampEpochSeconds / DAY_SECONDS.toLong() }
            .distinct()
            .count()
    }

    /**
     * 1.2 for a set near failure, 1.0 in the middle, 0.8 for an easy one. An
     * unrecorded RIR counts as 2: assuming failure would overstate the fatigue,
     * assuming easy would understate it, and 2 is where most working sets land.
     */
    fun effort(rir: Int?): Double = when {
        rir == null -> 1.0
        rir <= 1 -> 1.2
        rir <= 3 -> 1.0
        else -> 0.8
    }

    // ---- 6. rest ---------------------------------------------------------

    /**
     * One evaluation of the rest clock.
     *
     * The spec describes a loop - keep extending while the heart rate is above
     * target, in 15 s steps, at most 1.5x base - but this function is pure and
     * has no elapsed time to reason about, so it decides one step: the caller
     * re-calls it while the clock runs and feeds the new length back as `base`.
     *
     * That is why `ceilingSeconds` exists. Fed back without it, `base` grows and
     * the 1.5x cap grows with it, so the extension would never stop; passing the
     * original ceiling once makes the loop converge and the result idempotent
     * (a length already at the ceiling stays there).
     *
     * No heart rate (null peak or null current, which is the simulator and every
     * session without a strap) means exactly `base`: a missing sensor must never
     * delay or shorten a rest.
     */
    fun rest(
        baseSeconds: Int,
        peakHr: Int?,
        currentHr: Int?,
        restingHr: Int = DEFAULT_RESTING_HR,
        ceilingSeconds: Int? = null
    ): RestAdvice {
        val floor = max(baseSeconds, MIN_REST_SECONDS)
        if (peakHr == null || currentHr == null) return RestAdvice(floor, ready = false)

        val target = restingHr + HR_RESERVE_FRACTION * (peakHr - restingHr)
        if (currentHr <= target) {
            // Down early: keep the clock running but say so, so the app can buzz
            // once instead of making the user watch the seconds.
            return RestAdvice(floor, ready = true)
        }

        val ceiling = ceilingSeconds ?: (baseSeconds * REST_EXTENSION_CAP).toInt()
        val extended = min(baseSeconds + REST_STEP_SECONDS, ceiling)
        return RestAdvice(max(extended, MIN_REST_SECONDS), ready = false)
    }

    // ---- 5. seeds --------------------------------------------------------

    /**
     * Calibration: push-ups and bodyweight squats taken to RIR 1 give an e1rm
     * per pattern without a barbell in sight.
     */
    fun seedE1rm(bodyKg: Double, pushUpReps: Int, squatReps: Int): Map<String, Double> = mapOf(
        "pushup" to bodyKg * PUSHUP_FRACTION * (1.0 + clampReps(pushUpReps) / 30.0),
        "squat" to bodyKg * SQUAT_FRACTION * (1.0 + clampReps(squatReps) / 30.0)
    )

    /**
     * The first working weight for one exercise, from the calibration.
     *
     * Mapped patterns start at 65% of the pattern's estimate. A bodyweight
     * movement starts at 0 kg external - there is no bar to load, and 20 kg on
     * a pull-up would be a different exercise. Everything else gets an empty
     * bar, or the exercise's own floor if that is heavier.
     */
    fun seedWeight(spec: EngineSpec, seeds: Map<String, Double>): Double {
        if (spec.bodyweightFraction > 0.0) return 0.0

        val patternE1rm = if (spec.pattern.isEmpty()) null else seeds[spec.pattern]
        if (patternE1rm == null || patternE1rm <= 0.0) {
            return max(FALLBACK_SEED_KG, spec.minWeightKg)
        }

        val seeded = roundToIncrement(patternE1rm * SEED_FRACTION, spec.incrementKg)
        return max(seeded, spec.minWeightKg)
    }

    // ---- shared helpers --------------------------------------------------

    private fun clampReps(reps: Int): Int = reps.coerceIn(0, MAX_EFFECTIVE_REPS)

    /** Round to the nearest multiple of the step, then hold the exercise's floor. */
    fun clampToSpec(weightKg: Double, spec: EngineSpec): Double =
        max(roundToIncrement(weightKg, spec.incrementKg), spec.minWeightKg)

    /**
     * Nearest multiple of [incrementKg], halves up. A step of 0 (a spec that
     * forgot to push one) leaves the weight alone rather than dividing by zero.
     */
    fun roundToIncrement(weightKg: Double, incrementKg: Double): Double {
        if (incrementKg <= 0.0) return weightKg
        return round(weightKg / incrementKg) * incrementKg
    }

    private fun ageDays(timestampEpochSeconds: Long, nowEpochSeconds: Long): Double =
        max(0.0, (nowEpochSeconds - timestampEpochSeconds) / DAY_SECONDS)
}
