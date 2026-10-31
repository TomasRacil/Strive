package com.strive.mobile.ui

import com.strive.mobile.data.Exercise
import com.strive.mobile.data.Session
import com.strive.mobile.data.SetEntry
import com.strive.mobile.data.TrainingAdvice
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Progress maths, kept out of the composables so it can be reasoned about (and
 * tested) without a screen attached.
 */
object Stats {

    /**
     * Epley: estimated one-rep max from a working set. Rough, but consistent, so
     * the trend line is meaningful even if the absolute number is not.
     */
    fun estimate1RM(weightKg: Double, reps: Int): Double =
        if (reps <= 0) 0.0 else weightKg * (1 + reps / 30.0)

    /** Best estimated 1RM per session for one lift, oldest first. */
    fun bestPerSession(sessions: List<Session>, exerciseId: String): List<Double> =
        sessions
            .filter { session -> session.sets.any { it.exerciseId == exerciseId } }
            .sortedBy { it.startedAt }
            .map { session ->
                session.sets
                    .filter { it.exerciseId == exerciseId }
                    .maxOfOrNull { estimate1RM(it.weightKg, it.reps) } ?: 0.0
            }

    /** Total volume for each of the last [weeks] weeks, oldest first. */
    fun weeklyVolume(sessions: List<Session>, weeks: Int): List<Double> {
        val thisWeek = LocalDate.now().with(DayOfWeek.MONDAY)
        val firstWeek = thisWeek.minusWeeks((weeks - 1).toLong())

        return (0 until weeks).map { index ->
            val weekStart = firstWeek.plusWeeks(index.toLong())
            val weekEnd = weekStart.plusWeeks(1)

            sessions
                .filter { session ->
                    val day = Instant.ofEpochMilli(session.startedAt)
                        .atZone(ZoneId.systemDefault())
                        .toLocalDate()
                    !day.isBefore(weekStart) && day.isBefore(weekEnd)
                }
                .sumOf { it.volumeKg }
        }
    }

    fun bestEver(sessions: List<Session>, exerciseId: String): Double =
        sessions
            .flatMap { it.sets }
            .filter { it.exerciseId == exerciseId }
            .maxOfOrNull { estimate1RM(it.weightKg, it.reps) } ?: 0.0

    fun totalVolume(sessions: List<Session>): Double = sessions.sumOf { it.volumeKg }

    /**
     * The heaviest set of a group; reps break ties, so 100 kg x 5 beats 100 kg x 3.
     * Null for an empty group, which is the "nothing to compare" signal the
     * history card turns into a neutral state.
     */
    fun bestSetKg(sets: List<SetEntry>): Double? =
        sets
            .maxWithOrNull(compareBy<SetEntry> { it.weightKg }.thenBy { it.reps })
            ?.weightKg

    /**
     * The lift that carried the session: the one with the most sets, volume
     * breaking ties. That is the lift the workout was built around, so it is the
     * one worth comparing session to session.
     */
    fun mainLiftId(session: Session): String? =
        session.sets
            .groupBy { it.exerciseId }
            .maxWithOrNull(
                compareBy<Map.Entry<String, List<SetEntry>>> { it.value.size }
                    .thenBy { entry -> entry.value.sumOf { set -> set.weightKg * set.reps } }
            )
            ?.key

    /** Lift names in the session, the biggest contributor first. */
    fun topLifts(session: Session, limit: Int = 3): List<String> =
        session.sets
            .groupBy { it.exerciseId }
            .values
            .sortedWith(
                compareByDescending<List<SetEntry>> { it.size }
                    .thenByDescending { sets -> sets.sumOf { set -> set.weightKg * set.reps } }
            )
            .take(limit)
            .map { sets -> sets.first().exerciseName }

    /**
     * One session's main lift, with how its best set compares to the previous
     * session that contained the same lift. [deltaKg] is null when there is no
     * such session (first time this lift was trained, or only one session), so
     * the UI never divides or compares against nothing.
     */
    data class LiftProgress(
        val exerciseId: String,
        val exerciseName: String,
        val sets: Int,
        val bestKg: Double,
        val previousBestKg: Double?,
        /** This lift's best set per session, oldest first, ending with this one. */
        val history: List<Double>
    ) {
        val deltaKg: Double? get() = previousBestKg?.let { bestKg - it }
    }

    fun liftProgress(
        session: Session,
        sessions: List<Session>,
        historyLimit: Int = 8
    ): LiftProgress? {
        val id = mainLiftId(session) ?: return null
        val sets = session.sets.filter { it.exerciseId == id }
        val best = bestSetKg(sets) ?: return null

        // Strictly earlier sessions only: two workouts on the same day still
        // compare, but a session never compares against itself.
        val earlier = sessions
            .filter { it.id != session.id && it.startedAt < session.startedAt }
            .sortedByDescending { it.startedAt }

        val previousBest = earlier
            .firstOrNull { previous -> previous.sets.any { it.exerciseId == id } }
            ?.let { previous -> bestSetKg(previous.sets.filter { it.exerciseId == id }) }

        val history = (earlier + session)
            .sortedBy { it.startedAt }
            .mapNotNull { entry -> bestSetKg(entry.sets.filter { it.exerciseId == id }) }
            .takeLast(historyLimit)

        return LiftProgress(
            exerciseId = id,
            exerciseName = sets.first().exerciseName,
            sets = sets.size,
            bestKg = best,
            previousBestKg = previousBest,
            history = history
        )
    }

    data class Recommendation(
        val exercise: Exercise,
        val weightKg: Double,
        val reason: String
    )

    /**
     * Picks today's lifts: whatever has had the least work recently, weighted by
     * how long it has been since that muscle was trained, with the suggested load
     * coming from the engine so the home card and the train screen agree.
     *
     * Deliberately simple and explainable - a recommendation you cannot justify
     * to yourself is worse than no recommendation.
     */
    fun recommend(
        exercises: List<Exercise>,
        sessions: List<Session>,
        bodyKg: Double,
        fallbackKg: Double,
        limit: Int = 5
    ): List<Recommendation> {
        if (exercises.isEmpty()) return emptyList()

        val byId = exercises.associateBy { it.id }
        val since = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000

        val weeklyVolume = mutableMapOf<String, Double>()
        val lastTrained = mutableMapOf<String, Long>()

        sessions.forEach { session ->
            session.sets.forEach { set ->
                val muscle = byId[set.exerciseId]?.muscle ?: return@forEach
                val volume = set.weightKg * set.reps
                if (session.startedAt >= since) {
                    weeklyVolume[muscle] = (weeklyVolume[muscle] ?: 0.0) + volume
                }
                if ((lastTrained[muscle] ?: 0L) < session.startedAt) {
                    lastTrained[muscle] = session.startedAt
                }
            }
        }

        val maxVolume = weeklyVolume.values.maxOrNull() ?: 0.0
        val dayMs = 24L * 60 * 60 * 1000
        val now = System.currentTimeMillis()

        fun score(exercise: Exercise): Double {
            val volume = weeklyVolume[exercise.muscle] ?: 0.0
            val daysOff = ((now - (lastTrained[exercise.muscle] ?: (now - 14 * dayMs))) / dayMs)
                .coerceIn(0, 14)
            // Least volume first, then longest rested.
            return (maxVolume - volume) / 1000.0 + daysOff
        }

        fun reason(exercise: Exercise): String {
            val volume = weeklyVolume[exercise.muscle]
            val last = lastTrained[exercise.muscle]
            return when {
                volume == null && last == null -> "Not trained recently"
                last == null -> "Not trained recently"
                else -> {
                    val days = ((now - last) / dayMs).toInt()
                    when {
                        days <= 0 -> "${exercise.muscle} trained today"
                        days == 1 -> "${exercise.muscle} trained yesterday"
                        else -> "${exercise.muscle} rested $days days"
                    }
                }
            }
        }

        val perMuscle = mutableMapOf<String, Int>()

        return exercises
            .sortedByDescending { score(it) }
            .filter { exercise ->
                val used = perMuscle[exercise.muscle] ?: 0
                if (used >= 2) return@filter false
                perMuscle[exercise.muscle] = used + 1
                true
            }
            .take(limit)
            .map { exercise ->
                Recommendation(
                    exercise = exercise,
                    weightKg = TrainingAdvice
                        .advice(exercise, sessions, fallbackKg, bodyKg)
                        .weightKg,
                    reason = reason(exercise)
                )
            }
    }
}
