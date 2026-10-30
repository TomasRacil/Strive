package com.strive.mobile.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.strive.mobile.data.Exercise
import com.strive.mobile.data.ExerciseMatcher
import com.strive.mobile.data.Progression
import com.strive.mobile.data.ProgressionEntry
import com.strive.mobile.data.Seed
import com.strive.mobile.data.Session
import com.strive.mobile.data.SetEntry
import com.strive.mobile.data.Settings
import com.strive.mobile.data.StriveStore
import com.strive.mobile.data.Variation
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Sets logged in the session that is currently open. */
class ActiveSession(
    val id: String,
    val startedAt: Long,
    val routineName: String? = null,
    /** Lifts to work through, in order. Empty means free-form. */
    val plannedIds: List<String> = emptyList()
) {
    val sets = mutableStateListOf<SetEntry>()

    /** Index into plannedIds. */
    var index by mutableStateOf(0)

    /** Set to the wall clock when the user marks the start of a set. */
    var setStartedAt by mutableStateOf<Long?>(null)
}

/**
 * Single state holder for the whole app. Compose observes the `mutableStateOf`
 * fields directly; every mutation is written through to disk immediately so a
 * process death mid-workout does not lose the sets already logged.
 */
class AppState(context: Context) {

    private val store = StriveStore(context)

    var settings by mutableStateOf(store.loadSettings())
        private set

    var sessions by mutableStateOf(store.loadSessions())
        private set

    var progression by mutableStateOf(store.loadProgression())
        private set

    var active by mutableStateOf<ActiveSession?>(null)
        private set

    var lastFinished by mutableStateOf<Session?>(null)
        private set

    // Seeded once from the built-in library, then owned by the user: adding,
    // editing or deleting a lift persists the whole list.
    var exercises by mutableStateOf(
        migrate(store.loadExercises() ?: Seed.exercises)
    )
        private set

    /**
     * Libraries saved before muscle mapping existed have no primary/secondary
     * data, which would leave the body map blank. For any lift whose id still
     * matches the seed, fill the mapping in without touching the user's own
     * name, reps or rest.
     */
    private fun migrate(loaded: List<Exercise>): List<Exercise> {
        val seedById = Seed.exercises.associateBy { it.id }
        var changed = false

        val migrated = loaded.map { exercise ->
            val seed = seedById[exercise.id] ?: return@map exercise
            if (exercise.primary.isNotEmpty()) return@map exercise

            changed = true
            exercise.copy(
                description = exercise.description.ifBlank { seed.description },
                primary = seed.primary,
                secondary = seed.secondary,
                variations = if (exercise.variations.isEmpty()) seed.variations else exercise.variations
            )
        }

        if (changed) store.saveExercises(migrated)
        return migrated
    }

    fun addExercise(name: String, muscle: String, targetReps: Int, restSeconds: Int) {
        val exercise = Exercise(
            id = UUID.randomUUID().toString(),
            name = name,
            muscle = muscle,
            targetReps = targetReps,
            restSeconds = restSeconds
        )
        exercises = exercises + exercise
        store.saveExercises(exercises)
    }

    fun updateExercise(updated: Exercise) {
        exercises = exercises.map { if (it.id == updated.id) updated else it }
        store.saveExercises(exercises)
    }

    fun deleteExercise(id: String) {
        exercises = exercises.filterNot { it.id == id }
        store.saveExercises(exercises)
    }

    fun addExercises(newOnes: List<Exercise>) {
        if (newOnes.isEmpty()) return
        exercises = exercises + newOnes
        store.saveExercises(exercises)
    }

    fun addVariation(exerciseId: String, name: String, note: String) {
        val updated = exercises.map { exercise ->
            if (exercise.id != exerciseId) exercise
            else exercise.copy(
                variations = exercise.variations + Variation(
                    id = UUID.randomUUID().toString(),
                    name = name,
                    note = note
                )
            )
        }
        exercises = updated
        store.saveExercises(updated)
    }

    fun updateSettings(next: Settings) {
        settings = next
        store.saveSettings(next)
    }

    /**
     * Sessions imported before name matching existed kept Garmin's own exercise
     * names, so their ids matched no library lift and every statistic skipped
     * them. Re-map by name now; idempotent, so it is safe to run at startup.
     */
    fun repairImportedSessions() {
        val working = exercises.toMutableList()
        val created = mutableListOf<Exercise>()
        var changed = 0

        val repaired = sessions.map { session ->
            val sets = session.sets.map { entry ->
                val target = ExerciseMatcher.match(entry.exerciseName, working)
                    ?: ExerciseMatcher.infer(entry.exerciseName)?.let { candidate ->
                        working.firstOrNull { it.id == candidate.id }
                            ?: candidate.also { working.add(it); created.add(it) }
                    }

                if (target != null &&
                    (target.id != entry.exerciseId || target.name != entry.exerciseName)
                ) {
                    changed += 1
                    entry.copy(exerciseId = target.id, exerciseName = target.name)
                } else {
                    entry
                }
            }
            if (sets == session.sets) session else session.copy(sets = sets)
        }

        if (created.isNotEmpty()) {
            exercises = exercises + created
            store.saveExercises(exercises)
        }
        if (changed > 0) {
            sessions = repaired
            store.saveSessions(sessions)
        }
    }

    init {
        // Fix up history imported before matching existed.
        repairImportedSessions()
    }

    fun startSession(plannedIds: List<String> = emptyList(), routineName: String? = null) {
        if (active != null) return
        active = ActiveSession(
            id = UUID.randomUUID().toString(),
            startedAt = System.currentTimeMillis(),
            routineName = routineName,
            plannedIds = plannedIds
        )
    }

    /** The lift the user is on right now: the planned one, else the first. */
    fun currentExercise(): Exercise? {
        val session = active
        if (session != null && session.plannedIds.isNotEmpty()) {
            val id = session.plannedIds.getOrNull(session.index) ?: return null
            return exercises.firstOrNull { it.id == id }
        }
        return exercises.firstOrNull()
    }

    fun nextExercise() {
        val session = active ?: return
        session.setStartedAt = null
        if (session.index < session.plannedIds.size - 1) session.index += 1
    }

    fun previousExercise() {
        val session = active ?: return
        session.setStartedAt = null
        if (session.index > 0) session.index -= 1
    }

    fun startSet() {
        active?.setStartedAt = System.currentTimeMillis()
    }

    /**
     * Ends the current set and records what actually happened. The user corrects
     * the recommendation here, which is what makes the next suggestion useful.
     */
    fun finishSet(exercise: Exercise, weightKg: Double, reps: Int, rir: Int?) {
        val session = active ?: return
        val startedAt = session.setStartedAt
        val duration = if (startedAt != null) {
            ((System.currentTimeMillis() - startedAt) / 1000).toInt().coerceAtLeast(0)
        } else 0

        session.sets.add(
            SetEntry(
                exerciseId = exercise.id,
                exerciseName = exercise.name,
                weightKg = weightKg,
                reps = reps,
                rir = rir,
                timestamp = System.currentTimeMillis(),
                durationSeconds = duration
            )
        )
        session.setStartedAt = null
    }

    /**
     * How many sets to aim for on this lift. Three is the default; if the last
     * session completed three or more with reps left in reserve, aim higher.
     */
    fun targetSets(exerciseId: String): Int {
        val last = sessions.firstOrNull { session ->
            session.sets.any { it.exerciseId == exerciseId }
        } ?: return 3

        val sets = last.sets.filter { it.exerciseId == exerciseId }
        val rirValues = sets.mapNotNull { it.rir }
        val averageRir = if (rirValues.isEmpty()) 2.0 else rirValues.average()

        return when {
            sets.size >= 4 && averageRir >= 2.0 -> 5
            sets.size >= 3 && averageRir >= 2.0 -> 4
            sets.size <= 2 -> 3
            else -> 3
        }.coerceIn(2, 6)
    }

    fun suggestedWeight(exerciseId: String): Double =
        Progression.suggest(progression[exerciseId], DEFAULT_START_KG)

    fun logSet(exercise: Exercise, weightKg: Double, reps: Int, rir: Int?) {
        val session = active ?: return
        session.sets.add(
            SetEntry(
                exerciseId = exercise.id,
                exerciseName = exercise.name,
                weightKg = weightKg,
                reps = reps,
                rir = rir,
                timestamp = System.currentTimeMillis()
            )
        )
    }

    fun finishSession() {
        val session = active ?: return
        if (session.sets.isEmpty()) {
            active = null
            return
        }

        val finished = Session(
            id = session.id,
            startedAt = session.startedAt,
            endedAt = System.currentTimeMillis(),
            sets = session.sets.toList()
        )

        // Double progression: the load is earned by completing the target sets.
        val updatedProgression = progression.toMutableMap()
        session.sets.groupBy { it.exerciseId }.forEach { (exerciseId, sets) ->
            updatedProgression[exerciseId] = ProgressionEntry(
                weightKg = sets.last().weightKg,
                completed = sets.size >= Progression.TARGET_SETS
            )
        }
        progression = updatedProgression
        store.saveProgression(updatedProgression)

        val all = listOf(finished) + sessions
        sessions = all
        store.saveSessions(all)

        lastFinished = finished
        active = null
    }

    fun deleteSession(id: String) {
        val all = sessions.filterNot { it.id == id }
        sessions = all
        store.saveSessions(all)
    }

    /**
     * Merge externally produced sessions (Garmin imports) into history.
     * Duplicates are dropped by id, so importing the same file twice is a no-op.
     * Returns how many were actually added.
     */
    /**
     * Adds new sessions and refreshes known ones. Refreshing matters because an
     * older import may have stored exercise names before matching existed;
     * re-importing the same file now repairs them instead of being ignored.
     */
    fun importSessions(incoming: List<Session>): Pair<Int, Int> {
        if (incoming.isEmpty()) return 0 to 0

        val merged = sessions.toMutableList()
        var added = 0
        var updated = 0

        incoming
            .filter { it.id.isNotBlank() && it.sets.isNotEmpty() }
            .forEach { session ->
                val index = merged.indexOfFirst { it.id == session.id }
                when {
                    index < 0 -> {
                        merged.add(session)
                        added += 1
                    }
                    merged[index] != session -> {
                        merged[index] = session
                        updated += 1
                    }
                }
            }

        if (added == 0 && updated == 0) return 0 to 0

        sessions = merged.sortedByDescending { it.startedAt }
        store.saveSessions(sessions)
        return added to updated
    }

    fun dismissSummary() {
        lastFinished = null
    }

    /**
     * Consecutive days with a session, counting back from today. A streak that
     * ended yesterday still counts as alive, matching how the web app behaves.
     */
    fun streak(): Int {
        if (sessions.isEmpty()) return 0
        val days = sessions
            .map { Instant.ofEpochMilli(it.startedAt).atZone(ZoneId.systemDefault()).toLocalDate() }
            .toSet()

        var cursor = LocalDate.now()
        if (cursor !in days) {
            cursor = cursor.minusDays(1)
            if (cursor !in days) return 0
        }

        var count = 0
        while (cursor in days) {
            count++
            cursor = cursor.minusDays(1)
        }
        return count
    }

    fun volumeLastDays(days: Int): Double {
        val since = System.currentTimeMillis() - days * 24L * 60 * 60 * 1000
        return sessions.filter { it.startedAt >= since }.sumOf { it.volumeKg }
    }

    fun sessionsLastDays(days: Int): Int {
        val since = System.currentTimeMillis() - days * 24L * 60 * 60 * 1000
        return sessions.count { it.startedAt >= since }
    }

    companion object {
        const val DEFAULT_START_KG = 20.0
    }
}
