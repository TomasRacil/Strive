package com.strive.mobile.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * Reads the JSON produced by `python garmin/bridge.py pull --out file.json`.
 *
 * Shape: {"version":"1.2","source":"garmin","sessions":[{id,timestamp,duration,sets:[{exerciseId,exerciseName,weight,reps,rir,timestamp}]}]}
 *
 * Note `weight` rather than `weightKg`, and ISO-8601 timestamps rather than
 * epoch millis - that is what the Python side emits.
 */
object GarminImport {

    class ImportException(message: String) : Exception(message)

    /**
     * @param exercises the phone's library, used to map Garmin's generated
     * exercise ids onto real ones so imported history feeds the same stats.
     */
    fun parse(json: String, exercises: List<Exercise>): List<Session> {
        val root = runCatching { JSONObject(json) }
            .getOrElse { throw ImportException("Not a Strive/Garmin export file.") }

        val array = root.optJSONArray("sessions")
            ?: runCatching { JSONArray(json) }.getOrNull()
            ?: throw ImportException("No \"sessions\" array in that file.")

        val byName = exercises.associateBy { it.name.lowercase().trim() }

        return (0 until array.length()).mapNotNull { index ->
            val raw = array.optJSONObject(index) ?: return@mapNotNull null
            val startedAt = parseTime(raw.optString("timestamp")) ?: return@mapNotNull null

            val setsArray = raw.optJSONArray("sets") ?: JSONArray()
            val sets = (0 until setsArray.length()).mapNotNull { i ->
                val s = setsArray.optJSONObject(i) ?: return@mapNotNull null
                val name = s.optString("exerciseName")
                val matched = byName[name.lowercase().trim()]

                val weight = when {
                    s.has("weightKg") -> s.optDouble("weightKg", 0.0)
                    else -> s.optDouble("weight", 0.0)
                }
                val reps = s.optInt("reps", 0)
                if (reps <= 0) return@mapNotNull null

                SetEntry(
                    exerciseId = matched?.id ?: s.optString("exerciseId", "garmin_unknown"),
                    exerciseName = matched?.name ?: name.ifBlank { "Garmin lift" },
                    weightKg = weight,
                    reps = reps,
                    rir = if (s.has("rir") && !s.isNull("rir")) s.optInt("rir") else null,
                    timestamp = parseTime(s.optString("timestamp")) ?: startedAt
                )
            }

            if (sets.isEmpty()) return@mapNotNull null

            val durationMs = raw.optLong("duration", 0L) * 1000L
            Session(
                id = raw.optString("id").ifBlank { "imported_$startedAt" },
                startedAt = startedAt,
                endedAt = if (durationMs > 0) startedAt + durationMs else null,
                sets = sets
            )
        }
    }

    /** Accepts an offset timestamp, a local one, or a bare date. */
    private fun parseTime(value: String?): Long? {
        if (value.isNullOrBlank()) return null

        runCatching { return OffsetDateTime.parse(value).toInstant().toEpochMilli() }
        runCatching { return LocalDateTime.parse(value).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli() }
        runCatching {
            return LocalDate.parse(value.take(10)).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        }
        return null
    }
}
