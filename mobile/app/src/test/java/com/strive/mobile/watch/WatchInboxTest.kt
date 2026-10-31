package com.strive.mobile.watch

import com.strive.mobile.data.Session
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The watch's session messages turned into history, on the JVM.
 *
 * The payloads are the ones `Bus.mc` actually builds, field for field, because
 * the point of this class is that the two sides agree on them. Nothing here
 * touches Android or the Connect IQ SDK.
 */
class WatchInboxTest {

    private var now = 1_700_000_000_000L

    private val names = mapOf("bench_press" to "Bench press", "squats" to "Squats")

    private fun inbox() = WatchInbox(nameOf = { id -> names[id] ?: id }, clock = { now })

    /**
     * Stands in for StriveStore, which needs a Context. Its one relevant
     * property is that sessions are upserted by id, so that is what this keeps.
     */
    private class History {
        val byId = LinkedHashMap<String, Session>()

        fun collect(effect: WatchInbox.Effect?) {
            if (effect is WatchInbox.Effect.Save) byId[effect.session.id] = effect.session
        }
    }

    // ---- payloads, as the watch builds them -------------------------------

    private fun start(sid: String = "s1", atSeconds: Long = 1_699_999_000L) = JSONObject()
        .put("sid", sid)
        .put("wid", "phone-1")
        .put("t", atSeconds)

    private fun set(
        sid: String = "s1",
        ex: String = "bench_press",
        weight: Double = 100.0,
        reps: Int = 8,
        index: Int = 0,
        rir: Int = -1
    ) = JSONObject()
        .put("sid", sid)
        .put("ex", ex)
        .put("w", weight)
        .put("reps", reps)
        .put("rir", rir)
        .put("i", index)
        .put("rest", 120)

    private fun end(
        sid: String = "s1",
        atSeconds: Long = 1_700_000_000L,
        dur: Int = 1800,
        log: List<List<Any>> = listOf(
            listOf("bench_press", 100.0, 8, -1),
            listOf("squats", 140.0, 6, -1)
        )
    ): JSONObject {
        val rows = JSONArray()
        log.forEach { row ->
            val one = JSONArray()
            row.forEach { one.put(it) }
            rows.put(one)
        }

        var volume = 0.0
        log.forEach { volume += (it[1] as Double) * (it[2] as Int) }

        return JSONObject()
            .put("sid", sid)
            .put("t", atSeconds)
            .put("dur", dur)
            .put("sets", log.size)
            .put("vol", volume)
            .put("log", rows)
    }

    private fun ready(libV: Long = -1, planV: Long = -1) = JSONObject()
        .put("seq", 4)
        .put("libV", libV)
        .put("planV", planV)
        .put("pending", 0)
        .put("bench", false)

    // ---- upserts ----------------------------------------------------------

    @Test
    fun `a set arriving twice is one set`() {
        val inbox = inbox()
        inbox.apply("start", start())

        inbox.apply("set", set(index = 0, reps = 8))
        // The same frame again: the watch resends after a reconnect, and the
        // bus may also deliver a chunk twice.
        inbox.apply("set", set(index = 0, reps = 8))

        val live = inbox.liveSets("s1")
        assertEquals(1, live?.size)
        assertEquals(8, live?.first()?.reps)
    }

    @Test
    fun `a repeated start does not open a second session or lose its sets`() {
        val inbox = inbox()
        inbox.apply("start", start())
        inbox.apply("set", set(index = 0))

        inbox.apply("start", start())

        assertEquals(1, inbox.liveCount())
        assertEquals(1, inbox.liveSets("s1")?.size)
    }

    @Test
    fun `end arriving twice writes one session`() {
        val inbox = inbox()
        val history = History()

        inbox.apply("start", start())
        inbox.apply("set", set(index = 0))
        history.collect(inbox.apply("end", end()))

        // A replay of the same `end`, which is what a lost ack produces.
        history.collect(inbox.apply("end", end()))

        assertEquals(1, history.byId.size)
        assertEquals(2, history.byId.getValue("s1").sets.size)
    }

    // ---- a whole session --------------------------------------------------

    @Test
    fun `start, two sets and end match what the watch reported`() {
        val inbox = inbox()
        val history = History()

        inbox.apply("start", start())
        inbox.apply("set", set(ex = "bench_press", weight = 100.0, reps = 8, index = 0))
        inbox.apply("set", set(ex = "squats", weight = 140.0, reps = 6, index = 1))
        history.collect(inbox.apply("end", end()))

        val session = history.byId.getValue("s1")

        assertEquals(listOf("bench_press", "squats"), session.sets.map { it.exerciseId })
        assertEquals(listOf("Bench press", "Squats"), session.sets.map { it.exerciseName })
        // 100 x 8 + 140 x 6 = 1640, the same tonnage the watch's summary shows.
        assertEquals(1640.0, session.volumeKg, 0.001)
        // `dur` is what the watch measured; history derives duration from start
        // and end, so the start has to be back-dated from it.
        assertEquals(1800L, session.durationSeconds)
        assertEquals(1_700_000_000L * 1000 - 1800_000L, session.startedAt)
        assertEquals(1_700_000_000L * 1000, session.endedAt)
        // The live entry is gone once the session is closed.
        assertEquals(0, inbox.liveCount())
    }

    @Test
    fun `the log in end wins over the sets that arrived before it`() {
        val inbox = inbox()

        inbox.apply("start", start())
        inbox.apply("set", set(ex = "bench_press", weight = 90.0, reps = 5, index = 0))

        // The watch's log is the whole session, so a `set` that arrived with a
        // stale weight is corrected by the end that follows it.
        val effect = inbox.apply("end", end()) as WatchInbox.Effect.Save

        assertEquals(2, effect.session.sets.size)
        assertEquals(100.0, effect.session.sets.first().weightKg, 0.001)
    }

    // ---- a watch that restarted -------------------------------------------

    @Test
    fun `a set for an unknown sid opens a session instead of throwing`() {
        val inbox = inbox()

        // No `start`: the watch restarted mid-session, or the start was lost.
        // Dropping the set would lose the user's work, so the sid is adopted and
        // the session is stamped with the set's arrival time. The `end` that
        // follows carries the real start and duration, so nothing is lost.
        inbox.apply("set", set(sid = "lost", ex = "squats", weight = 120.0, reps = 5, index = 0))

        assertEquals(1, inbox.liveCount())
        assertEquals(1, inbox.liveSets("lost")?.size)

        val effect = inbox.apply("end", end(sid = "lost")) as WatchInbox.Effect.Save
        assertEquals("lost", effect.session.id)
        assertEquals(2, effect.session.sets.size)
    }

    @Test
    fun `an end with no start still produces the whole session`() {
        val inbox = inbox()

        // Every earlier message was lost, but `end` carries the full log, so the
        // workout still reaches history.
        val effect = inbox.apply("end", end(sid = "solo", dur = 900)) as WatchInbox.Effect.Save

        assertEquals("solo", effect.session.id)
        assertEquals(2, effect.session.sets.size)
        assertEquals(900L, effect.session.durationSeconds)
    }

    @Test
    fun `an end with neither a log nor live sets writes nothing`() {
        val inbox = inbox()

        assertNull(inbox.apply("end", end(log = emptyList())))
    }

    @Test
    fun `unknown kinds and missing payloads are ignored`() {
        val inbox = inbox()

        assertNull(inbox.apply("bench", JSONObject().put("t", 1)))
        assertNull(inbox.apply("set", null))
        assertNull(inbox.apply("end", JSONObject()))
        assertEquals(0, inbox.liveCount())
    }

    // ---- ready ------------------------------------------------------------

    @Test
    fun `ready with an older plan version re-sends plan and rec`() {
        val inbox = inbox()

        val effect = inbox.apply(
            "ready",
            ready(libV = -1, planV = 1_600_000_000),
            WatchInbox.Held(planVersion = 1_700_000_000, hasHistory = true)
        ) as WatchInbox.Effect.Resend

        // rec travels with plan: a plan without its load is not trainable.
        assertEquals(listOf("plan", "rec", "hist"), effect.kinds)
    }

    @Test
    fun `ready with an older library version re-sends lib`() {
        val inbox = inbox()

        val effect = inbox.apply(
            "ready",
            ready(libV = 3, planV = 9),
            WatchInbox.Held(libVersion = 4, planVersion = 9)
        ) as WatchInbox.Effect.Resend

        assertEquals(listOf("lib"), effect.kinds)
    }

    @Test
    fun `ready with nothing behind sends nothing`() {
        val inbox = inbox()

        assertNull(inbox.apply("ready", ready(libV = 9, planV = 9), WatchInbox.Held()))
    }
}
