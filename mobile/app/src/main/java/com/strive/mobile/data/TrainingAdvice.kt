package com.strive.mobile.data

import kotlin.math.roundToInt

/**
 * The engine's view of the app's own data: sessions in, advice out.
 *
 * [Engine] takes flat values and a caller-supplied clock so it stays pure and
 * shareable with the watch. This is the one place that knows how a [Session]
 * maps onto that, and it is deliberately free of Android types: [com.strive.mobile.ui.AppState]
 * needs a Context, and the mapping is the part worth testing.
 */
object TrainingAdvice {

    /**
     * The sets of [exerciseId] from the most recent session that contains it,
     * oldest first - the window [Engine.nextLoad] reads.
     *
     * Older sessions are ignored on purpose: the rule asks what the last time
     * looked like, not what the best ever was.
     */
    fun latestSets(sessions: List<Session>, exerciseId: String): List<EngineSet> {
        val last = sessions
            .filter { session -> session.sets.any { it.exerciseId == exerciseId } }
            .maxByOrNull { it.startedAt }
            ?: return emptyList()
        return last.sets
            .filter { it.exerciseId == exerciseId }
            .map { EngineSet(it.weightKg, it.reps, it.rir) }
    }

    fun everTrained(sessions: List<Session>, exerciseId: String): Boolean =
        sessions.any { session -> session.sets.any { it.exerciseId == exerciseId } }

    /** Every logged set with its timestamp: the shape load and ranking take. */
    fun timedSets(sessions: List<Session>): List<TimedSet> =
        sessions.flatMap { session ->
            session.sets.map { set ->
                TimedSet(set.exerciseId, set.weightKg, set.reps, set.rir, set.timestamp / 1000)
            }
        }

    fun specs(exercises: List<Exercise>): Map<String, EngineSpec> =
        exercises.associate { it.id to EngineSpec.from(it) }

    /**
     * Load and rep target for one lift. [seedKg] is what a lift with no history
     * starts at; [bodyKg] prices bodyweight sets, which is what stops a pull-up
     * session scoring zero and losing to a set with added weight.
     */
    fun advice(
        exercise: Exercise,
        sessions: List<Session>,
        seedKg: Double,
        bodyKg: Double
    ): LoadAdvice = Engine.nextLoad(
        spec = EngineSpec.from(exercise),
        history = latestSets(sessions, exercise.id),
        seedKg = seedKg,
        bodyKg = bodyKg
    )

    /**
     * How many sets to aim for on this lift.
     *
     * The muscle total comes from the whole library, not just this lift: a bench
     * press spends triceps that a press-down also spends, and the rule is about
     * the muscle's week. The engine reports fractional sets (a set of bench is
     * part of the triceps' week), and the rule only asks "under eight?", so it is
     * rounded here rather than inside the engine.
     */
    fun targetSets(
        sessions: List<Session>,
        library: List<Exercise>,
        exercise: Exercise,
        nowMillis: Long
    ): Int {
        val spec = EngineSpec.from(exercise)
        val load = Engine.muscleLoad(specs(library), timedSets(sessions), nowMillis / 1000)
        val weekly = spec.primaryMuscle()?.let { (load[it] ?: 0.0).roundToInt() } ?: 0
        return Engine.recommendedSets(spec, weekly, everTrained(sessions, exercise.id))
    }

    /**
     * The library in [Engine.rank] order, least-loaded muscles first.
     *
     * rank drops a lift whose primary muscle is wrecked. Dropping it from the
     * picker would hide a lift the user may still want to log, so those go to the
     * back in library order instead of disappearing.
     */
    fun order(exercises: List<Exercise>, sessions: List<Session>, nowMillis: Long): List<Exercise> {
        if (exercises.isEmpty()) return exercises
        val byId = exercises.associateBy { it.id }
        // rank takes a list, not a map: equal scores keep library order, and a map
        // has no order to keep.
        val ranked = Engine.rank(
            exercises.map { EngineSpec.from(it) },
            timedSets(sessions),
            nowMillis / 1000
        ).mapNotNull { byId[it.exerciseId] }
        val placed = ranked.mapTo(mutableSetOf()) { it.id }
        return ranked + exercises.filterNot { it.id in placed }
    }
}
