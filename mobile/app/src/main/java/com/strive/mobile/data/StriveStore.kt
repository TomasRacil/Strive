package com.strive.mobile.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Local-first persistence on SharedPreferences, holding JSON.
 *
 * The web app used localStorage and this keeps the same shape of data: sessions
 * are the unit of history and weights are kilograms. No network, no account.
 */
class StriveStore(context: Context) {

    private val prefs =
        context.applicationContext.getSharedPreferences("strive", Context.MODE_PRIVATE)

    // ---------------------------------------------------------------- settings

    fun loadSettings(): Settings {
        val raw = prefs.getString(KEY_SETTINGS, null) ?: return Settings()
        return runCatching {
            val o = JSONObject(raw)
            Settings(
                theme = o.optString("theme", "system"),
                unit = o.optString("unit", "kg"),
                lang = o.optString("lang", "en"),
                // Absent in settings saved before body mass existed: the engine's
                // own assumption is the honest answer until calibration runs.
                bodyKg = o.optDouble("bodyKg", Engine.DEFAULT_BODY_KG)
            )
        }.getOrDefault(Settings())
    }

    fun saveSettings(settings: Settings) {
        val o = JSONObject()
            .put("theme", settings.theme)
            .put("unit", settings.unit)
            .put("lang", settings.lang)
            .put("bodyKg", settings.bodyKg)
        prefs.edit().putString(KEY_SETTINGS, o.toString()).apply()
    }

    // --------------------------------------------------------------- exercises

    /** Null means "never saved", so the caller can seed the library once. */
    fun loadExercises(): List<Exercise>? {
        val raw = prefs.getString(KEY_EXERCISES, null) ?: return null
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Exercise(
                    id = o.optString("id"),
                    name = o.optString("name"),
                    muscle = o.optString("muscle"),
                    targetReps = o.optInt("targetReps", 8),
                    restSeconds = o.optInt("restSeconds", 120),
                    description = o.optString("description", ""),
                    primary = readWeights(o.optJSONObject("primary")),
                    secondary = readWeights(o.optJSONObject("secondary")),
                    variations = readVariations(o.optJSONArray("variations"))
                )
            }
        }.getOrNull()
    }

    fun saveExercises(exercises: List<Exercise>) {
        val arr = JSONArray()
        exercises.forEach { e ->
            val o = JSONObject()
                .put("id", e.id)
                .put("name", e.name)
                .put("muscle", e.muscle)
                .put("targetReps", e.targetReps)
                .put("restSeconds", e.restSeconds)
                .put("description", e.description)
                .put("primary", writeWeights(e.primary))
                .put("secondary", writeWeights(e.secondary))
                .put("variations", writeVariations(e.variations))
            arr.put(o)
        }
        prefs.edit().putString(KEY_EXERCISES, arr.toString()).apply()
    }

    private fun readWeights(o: JSONObject?): Map<String, Double> {
        if (o == null) return emptyMap()
        return o.keys().asSequence().associateWith { o.optDouble(it, 0.0) }
    }

    private fun writeWeights(map: Map<String, Double>): JSONObject {
        val o = JSONObject()
        map.forEach { (muscle, weight) -> o.put(muscle, weight) }
        return o
    }

    private fun readVariations(arr: JSONArray?): List<Variation> {
        if (arr == null) return emptyList()
        return (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            Variation(
                id = o.optString("id"),
                name = o.optString("name"),
                note = o.optString("note", ""),
                targetReps = if (o.has("targetReps")) o.optInt("targetReps") else null,
                restSeconds = if (o.has("restSeconds")) o.optInt("restSeconds") else null
            )
        }
    }

    private fun writeVariations(variations: List<Variation>): JSONArray {
        val arr = JSONArray()
        variations.forEach { v ->
            val o = JSONObject()
                .put("id", v.id)
                .put("name", v.name)
                .put("note", v.note)
            if (v.targetReps != null) o.put("targetReps", v.targetReps)
            if (v.restSeconds != null) o.put("restSeconds", v.restSeconds)
            arr.put(o)
        }
        return arr
    }

    // ---------------------------------------------------------------- sessions

    fun loadSessions(): List<Session> {
        val raw = prefs.getString(KEY_SESSIONS, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { parseSession(arr.getJSONObject(it)) }
                .sortedByDescending { it.startedAt }
        }.getOrDefault(emptyList())
    }

    fun saveSessions(sessions: List<Session>) {
        val arr = JSONArray()
        sessions.forEach { arr.put(sessionToJson(it)) }
        prefs.edit().putString(KEY_SESSIONS, arr.toString()).apply()
    }

    private fun parseSession(o: JSONObject): Session {
        val setsArr = o.optJSONArray("sets") ?: JSONArray()
        val sets = (0 until setsArr.length()).map { i ->
            val s = setsArr.getJSONObject(i)
            SetEntry(
                exerciseId = s.optString("exerciseId"),
                exerciseName = s.optString("exerciseName"),
                weightKg = s.optDouble("weightKg", 0.0),
                reps = s.optInt("reps", 0),
                rir = if (s.has("rir") && !s.isNull("rir")) s.optInt("rir") else null,
                timestamp = s.optLong("timestamp", 0L),
                durationSeconds = s.optInt("durationSeconds", 0)
            )
        }
        return Session(
            id = o.optString("id"),
            startedAt = o.optLong("startedAt", 0L),
            endedAt = if (o.has("endedAt") && !o.isNull("endedAt")) o.optLong("endedAt") else null,
            sets = sets
        )
    }

    private fun sessionToJson(session: Session): JSONObject {
        val setsArr = JSONArray()
        session.sets.forEach { s ->
            val o = JSONObject()
                .put("exerciseId", s.exerciseId)
                .put("exerciseName", s.exerciseName)
                .put("weightKg", s.weightKg)
                .put("reps", s.reps)
                .put("timestamp", s.timestamp)
                .put("durationSeconds", s.durationSeconds)
            if (s.rir != null) o.put("rir", s.rir)
            setsArr.put(o)
        }
        return JSONObject()
            .put("id", session.id)
            .put("startedAt", session.startedAt)
            .put("sets", setsArr)
            .apply { if (session.endedAt != null) put("endedAt", session.endedAt) }
    }

    // ---------------------------------------------------------------- routines

    fun loadRoutines(): List<Routine> {
        val raw = prefs.getString(KEY_ROUTINES, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val ids = o.optJSONArray("exerciseIds") ?: JSONArray()
                Routine(
                    id = o.optString("id"),
                    name = o.optString("name"),
                    exerciseIds = (0 until ids.length()).map { ids.optString(it) }
                )
            }
        }.getOrDefault(emptyList())
    }

    fun saveRoutines(routines: List<Routine>) {
        val arr = JSONArray()
        routines.forEach { routine ->
            arr.put(
                JSONObject()
                    .put("id", routine.id)
                    .put("name", routine.name)
                    .put("exerciseIds", JSONArray(routine.exerciseIds))
            )
        }
        prefs.edit().putString(KEY_ROUTINES, arr.toString()).apply()
    }

    private companion object {
        const val KEY_SETTINGS = "settings"
        const val KEY_SESSIONS = "sessions"
        const val KEY_EXERCISES = "exercises"
        const val KEY_ROUTINES = "routines"
    }
}
