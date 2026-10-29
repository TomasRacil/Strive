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
                lang = o.optString("lang", "en")
            )
        }.getOrDefault(Settings())
    }

    fun saveSettings(settings: Settings) {
        val o = JSONObject()
            .put("theme", settings.theme)
            .put("unit", settings.unit)
            .put("lang", settings.lang)
        prefs.edit().putString(KEY_SETTINGS, o.toString()).apply()
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
                timestamp = s.optLong("timestamp", 0L)
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
            if (s.rir != null) o.put("rir", s.rir)
            setsArr.put(o)
        }
        return JSONObject()
            .put("id", session.id)
            .put("startedAt", session.startedAt)
            .put("sets", setsArr)
            .apply { if (session.endedAt != null) put("endedAt", session.endedAt) }
    }

    // ------------------------------------------------------------- progression

    fun loadProgression(): Map<String, ProgressionEntry> {
        val raw = prefs.getString(KEY_PROGRESSION, null) ?: return emptyMap()
        return runCatching {
            val o = JSONObject(raw)
            o.keys().asSequence().associateWith { key ->
                val e = o.getJSONObject(key)
                ProgressionEntry(
                    weightKg = e.optDouble("weightKg", 0.0),
                    completed = e.optBoolean("completed", false)
                )
            }
        }.getOrDefault(emptyMap())
    }

    fun saveProgression(map: Map<String, ProgressionEntry>) {
        val o = JSONObject()
        map.forEach { (key, entry) ->
            o.put(
                key,
                JSONObject()
                    .put("weightKg", entry.weightKg)
                    .put("completed", entry.completed)
            )
        }
        prefs.edit().putString(KEY_PROGRESSION, o.toString()).apply()
    }

    private companion object {
        const val KEY_SETTINGS = "settings"
        const val KEY_SESSIONS = "sessions"
        const val KEY_PROGRESSION = "progression"
    }
}
