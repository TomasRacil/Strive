package com.strive.mobile.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.strive.mobile.data.Exercise
import com.strive.mobile.data.Progression
import com.strive.mobile.data.ProgressionEntry
import com.strive.mobile.data.Seed
import com.strive.mobile.data.Session
import com.strive.mobile.data.SetEntry
import com.strive.mobile.data.Settings
import com.strive.mobile.data.StriveStore
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** Sets logged in the session that is currently open. */
class ActiveSession(val id: String, val startedAt: Long) {
    val sets = mutableStateListOf<SetEntry>()
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

    val exercises: List<Exercise> = Seed.exercises

    fun updateSettings(next: Settings) {
        settings = next
        store.saveSettings(next)
    }

    fun startSession() {
        if (active != null) return
        active = ActiveSession(UUID.randomUUID().toString(), System.currentTimeMillis())
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
