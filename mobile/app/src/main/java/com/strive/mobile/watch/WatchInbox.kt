package com.strive.mobile.watch

import com.strive.mobile.data.SetEntry
import com.strive.mobile.data.Session
import org.json.JSONObject

/**
 * The watch's session messages turned into phone history.
 *
 * Deliberately free of Android types and of the store, in the same spirit as
 * `TrainingAdvice`: a payload goes in and a [Session] comes out, so the mapping
 * is unit-tested on the JVM without the Connect IQ SDK or a Context.
 *
 * Every kind is an upsert, because the bus may deliver the same message twice
 * and the watch re-sends after a reconnect: `start` keys a live session by
 * `sid`, `set` keys a set by (`sid`, exercise, index) and `end` keys history by
 * `sid`. Applying any of them twice converges on the same state rather than
 * duplicating the user's work.
 */
class WatchInbox(
    /** Exercise id to display name. The watch only ever sends ids. */
    private val nameOf: (String) -> String = { it },
    /** Arrival time, used where the payload carries no usable clock. */
    private val clock: () -> Long = { System.currentTimeMillis() }
) {

    /** What the phone holds, in the version currency `ready` reports. */
    data class Held(
        val libVersion: Long = 0,
        val planVersion: Long = 0,
        val hasHistory: Boolean = false
    )

    /** What one applied message asks the phone to do next. */
    sealed class Effect {
        /** Write this session into history, upserting by [Session.id]. */
        data class Save(val session: Session) : Effect()

        /** Re-send these snapshot kinds; the phone holds newer copies. */
        data class Resend(val kinds: List<String>) : Effect()
    }

    /** One set as the watch banked it, before it becomes a [SetEntry]. */
    private class WatchSet(
        val exerciseId: String,
        val index: Int,
        val weightKg: Double,
        val reps: Int,
        val rir: Int?,
        val at: Long
    )

    private class Live(val sid: String, val startedAt: Long) {
        /** Keyed by exercise and index, so the same set delivered twice is one set. */
        val sets = LinkedHashMap<String, WatchSet>()
    }

    /** Sessions the watch has started and not yet ended, by sid. */
    private val live = HashMap<String, Live>()

    /**
     * Sids already written to history. Kept so a replayed `end` costs nothing
     * even before the store is consulted; the store's own upsert by id is the
     * guard that survives a process restart.
     */
    private val ended = HashSet<String>()

    /**
     * Applies one message from the watch. Returns the effect the phone still has
     * to carry out, or null when the message only changed live state (or was a
     * repeat of something already applied).
     */
    fun apply(kind: String, payload: JSONObject?, held: Held = Held()): Effect? = when (kind) {
        "start" -> {
            start(payload)
            null
        }
        "set" -> {
            set(payload)
            null
        }
        "end" -> end(payload)?.let { Effect.Save(it) }
        "ready" -> resendFor(payload, held)?.let { Effect.Resend(it) }
        else -> null
    }

    /** Sets banked for [sid] so far, in index order. Null when no session is live. */
    fun liveSets(sid: String): List<SetEntry>? = live[sid]?.let { entriesOf(it.sets.values) }

    /** How many sessions the watch has running. */
    fun liveCount(): Int = live.size

    // ---- start -----------------------------------------------------------

    private fun start(payload: JSONObject?) {
        val sid = payload?.optString("sid").orEmpty()
        if (sid.isEmpty()) return

        // A repeat after a reconnect must not reset a session that is already
        // running, and a `start` replayed after its own `end` must not resurrect
        // it: either would throw away sets the user has already banked.
        if (sid in ended || live.containsKey(sid)) return

        live[sid] = Live(sid, startedAtOf(payload))
    }

    /** `t` is the watch's wall clock in seconds; the two clocks are not in sync. */
    private fun startedAtOf(payload: JSONObject?): Long {
        val seconds = payload?.optLong("t", 0L) ?: 0L
        return if (seconds > 0) seconds * 1000 else clock()
    }

    // ---- set -------------------------------------------------------------

    private fun set(payload: JSONObject?) {
        if (payload == null) return
        val sid = payload.optString("sid").orEmpty()
        val exerciseId = payload.optString("ex").orEmpty()
        if (sid.isEmpty() || exerciseId.isEmpty()) return

        // The watch restarted mid-session, or its `start` never made it across.
        // The set is the user's work, so it opens the session here instead of
        // being dropped; `end` still supplies the real start time and duration.
        val session = live.getOrPut(sid) { Live(sid, clock()) }

        val index = payload.optInt("i", session.sets.size)
        val key = "$exerciseId#$index"

        // The arrival time of the first delivery is kept: a replay is the same
        // set, and history should not show it as having happened later.
        val at = session.sets[key]?.at ?: clock()

        session.sets[key] = WatchSet(
            exerciseId = exerciseId,
            index = index,
            weightKg = payload.optDouble("w", 0.0),
            reps = payload.optInt("reps", 0),
            // The watch has no RIR entry yet and sends -1 for "unknown".
            rir = payload.optInt("rir", -1).takeIf { it >= 0 },
            at = at
        )
    }

    // ---- end -------------------------------------------------------------

    private fun end(payload: JSONObject?): Session? {
        val body = payload ?: return null
        val sid = body.optString("sid").orEmpty()
        if (sid.isEmpty()) return null

        // Idempotent by sid: a replayed `end` must not produce a second workout.
        if (!ended.add(sid)) return null

        val running = live.remove(sid)

        val endedAt = body.optLong("t", 0L).takeIf { it > 0 }?.times(1000) ?: clock()
        val duration = body.optInt("dur", 0).coerceAtLeast(0)

        // History derives its duration from start and end, so the start is
        // back-dated from the duration the watch measured. Its own start time is
        // only a fallback: a watch clock that is a minute out would otherwise
        // stretch or shrink every session.
        val startedAt = when {
            duration > 0 -> endedAt - duration * 1000L
            running != null -> running.startedAt
            else -> endedAt
        }

        // The log in `end` is the whole session, so it wins even when every
        // earlier `set` was lost. The live sets are the fallback for a watch
        // build that ends a session without attaching one.
        val sets = logOf(body, startedAt)
            .ifEmpty { running?.let { entriesOf(it.sets.values) }.orEmpty() }

        if (sets.isEmpty()) return null

        return Session(id = sid, startedAt = startedAt, endedAt = endedAt, sets = sets)
    }

    /** `log` is `[[ex, w, reps, rir], ...]` in the order the sets were done. */
    private fun logOf(payload: JSONObject, at: Long): List<SetEntry> {
        val log = payload.optJSONArray("log") ?: return emptyList()
        val out = ArrayList<SetEntry>(log.length())

        for (i in 0 until log.length()) {
            val row = log.optJSONArray(i) ?: continue
            val exerciseId = row.optString(0).orEmpty()
            if (exerciseId.isEmpty()) continue

            out.add(
                SetEntry(
                    exerciseId = exerciseId,
                    exerciseName = nameOf(exerciseId),
                    weightKg = row.optDouble(1, 0.0),
                    reps = row.optInt(2, 0),
                    rir = row.optInt(3, -1).takeIf { it >= 0 },
                    // The log carries no per-set time, so the whole session is
                    // stamped with its start rather than a guessed spread.
                    timestamp = at
                )
            )
        }

        return out
    }

    // ---- ready -----------------------------------------------------------

    /**
     * Which snapshots the phone should re-send. `ready` reports what the watch
     * holds; anything the phone has newer is pushed again, so a reconnect heals
     * itself without the user asking.
     */
    private fun resendFor(payload: JSONObject?, held: Held): List<String>? {
        if (payload == null) return null
        val kinds = ArrayList<String>(4)

        // A zero on either side means "nothing held", not "version zero": the
        // watch reports -1 for a library it has never stored, and the phone has
        // no library snapshot to send at all.
        if (held.libVersion > 0 && held.libVersion > payload.optLong("libV", 0L)) {
            kinds.add("lib")
        }

        // `rec` travels with `plan`: a plan without its load is the plan the
        // user cannot train, and both are built from the same list.
        if (held.planVersion > 0 && held.planVersion > payload.optLong("planV", 0L)) {
            kinds.add("plan")
            kinds.add("rec")
        }

        // The protocol has no hist version, so history is re-sent whenever the
        // phone has any: it is the cheapest snapshot to repeat and the only
        // input the watch's offline recommendation has.
        if (held.hasHistory) kinds.add("hist")

        return kinds.ifEmpty { null }
    }

    // ---- mapping ---------------------------------------------------------

    private fun entriesOf(sets: Collection<WatchSet>): List<SetEntry> =
        sets.sortedBy { it.index }.map { set ->
            SetEntry(
                exerciseId = set.exerciseId,
                exerciseName = nameOf(set.exerciseId),
                weightKg = set.weightKg,
                reps = set.reps,
                rir = set.rir,
                timestamp = set.at
            )
        }
}
