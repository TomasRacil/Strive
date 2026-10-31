package com.strive.mobile.watch

import com.strive.mobile.data.EngineSpec
import com.strive.mobile.data.Exercise
import org.json.JSONArray
import org.json.JSONObject

/**
 * The `lib` snapshot: the whole exercise library, in the shape the watch's
 * `Library.mc` reads.
 *
 * Three things here exist because the watch cannot derive them:
 *
 * - `bw` (bodyweight fraction). Without it the watch prices a bodyweight set at
 *   the external load alone, so a custom calisthenics movement the user added
 *   arrives as an external lift whose sets score 0 kg and never progress. The
 *   compiled table in `Exercises.mc` is only the offline fallback now.
 * - `mus` and `sec`, kept apart. The watch discounts a stabiliser's fatigue by
 *   40% in `Engine.loadByMuscle()`, which it can only do if the payload says
 *   which shares are primary movers and which are stabilisers. A single flat
 *   list made every muscle a prime mover, so compounds were over-penalised.
 * - `v`, a version, so a watch that reconnects can say it is behind and be
 *   re-sent the snapshot.
 *
 * Kept out of [WatchRepository] and free of Android types so the encoding is
 * unit-tested on the JVM: the bus refuses a body over 6000 units rather than
 * truncating it, and a library that silently lost its tail would leave the watch
 * ranking a half-catalogue.
 */
internal object LibraryPayload {

    /**
     * Builds the payload for [exercises]. An exercise with no muscles still
     * travels: the watch can run it, it just cannot rank it.
     *
     * Every number comes from [EngineSpec.from], the same call the phone's own
     * engine uses. Re-deriving the rep range or the increment here would give
     * the watch a second opinion on the exercise, and the two trainers would
     * then disagree about the same lift.
     */
    fun of(exercises: List<Exercise>, version: Long): JSONObject {
        val rows = JSONArray()
        exercises.forEach { exercise ->
            val spec = EngineSpec.from(exercise)
            rows.put(
                JSONObject()
                    .put("id", exercise.id)
                    .put("name", exercise.name)
                    // The library has no separate short name; the watch draws it
                    // in the picker row, so the full name is the honest value.
                    .put("short", exercise.name)
                    .put("mus", shares(spec.primary))
                    .put("sec", shares(spec.secondary))
                    .put("lo", spec.lo)
                    .put("hi", spec.hi)
                    .put("rest", spec.restSeconds)
                    .put("inc", spec.incrementKg)
                    .put("minW", spec.minWeightKg)
                    .put("bw", spec.bodyweightFraction)
            )
        }

        return JSONObject()
            .put("v", version)
            .put("ex", rows)
    }

    /**
     * A muscle map as `[[muscle, share], ...]`.
     *
     * Sorted, because a JSONObject's key order is not stable and the same
     * library must produce the same bytes twice: an unstable payload would make
     * every re-send look like a change.
     */
    private fun shares(map: Map<String, Double>): JSONArray {
        val out = JSONArray()
        map.entries.sortedBy { it.key }.forEach { (muscle, share) ->
            out.put(JSONArray().put(muscle).put(share))
        }
        return out
    }
}
