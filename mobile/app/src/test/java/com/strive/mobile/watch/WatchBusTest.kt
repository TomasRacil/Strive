package com.strive.mobile.watch

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The phone half of protocol v1, tested on the JVM with no Connect IQ SDK.
 *
 * The transport is the only thing swapped out, so what is covered here is the
 * framing, the chunking, the reassembly, the acks, the retry schedule, the
 * dedupe and a full phone-to-watch-to-phone exchange.
 */
class WatchBusTest {

    /** Records what would have gone out and hands it to a peer bus, if any. */
    private class FakeTransport : WatchTransport {
        val sent = mutableListOf<String>()
        var peer: WatchBus? = null
        var drop = false

        override fun send(text: String) {
            sent.add(text)
            if (!drop) {
                peer?.onIncoming(text)
            }
        }
    }

    private var now = 1_000_000L

    private fun bus(transport: WatchTransport = FakeTransport()) =
        WatchBus(transport = transport, clock = { now })

    private fun framesFor(body: String): List<String> {
        val chunks = bus().chunk(body)
        return chunks.mapIndexed { i, chunk -> "1|abc12345|$i|${chunks.size}|$chunk" }
    }

    private fun planPayload(): JSONObject = JSONObject()
        .put("v", 7)
        .put("wid", "w-1")
        .put("name", "Push A")
        .put(
            "items", JSONArray().put(
                JSONObject().put("ex", "bench_press").put("sets", 3).put("lo", 6)
                    .put("hi", 8).put("rest", 150).put("ss", 0)
            )
        )

    // ---- chunking --------------------------------------------------------

    @Test
    fun `chunks are at most 400 units and rejoin to the original`() {
        val body = "x".repeat(1000)
        val chunks = bus().chunk(body)

        assertEquals(3, chunks.size)
        assertTrue(chunks.all { it.length <= WatchBus.CHUNK_UNITS })
        assertEquals(body, chunks.joinToString(""))
    }

    @Test
    fun `a chunk never splits a surrogate pair`() {
        // 399 filler units put the 400-unit boundary inside the pair.
        val body = "a".repeat(399) + "\uD83D\uDE00" + "tail"
        val chunks = bus().chunk(body)

        assertEquals(2, chunks.size)
        assertEquals(399, chunks[0].length)
        assertEquals(6, chunks[1].length)
        assertEquals(body, chunks.joinToString(""))
    }

    // ---- reassembly ------------------------------------------------------

    @Test
    fun `a multi-chunk message is reassembled, applied and acked`() {
        val transport = FakeTransport()
        val bus = bus(transport)
        var applied: String? = null
        bus.onMessage = { kind, _ -> applied = kind }

        // Long enough to need more than one 400-unit chunk, which is the normal
        // case for a library snapshot.
        val library = JSONObject().put("v", 1)
        val exercises = JSONArray()
        (1..20).forEach { i ->
            exercises.put(
                JSONObject().put("id", "ex_$i").put("name", "Exercise number $i")
                    .put("short", "E$i").put("lo", 6).put("hi", 10).put("rest", 150)
            )
        }
        library.put("ex", exercises)

        val frames = framesFor(
            JSONObject().put("k", "plan").put("n", 1).put("t", 0).put("p", library).toString()
        )

        assertTrue("body must need more than one chunk", frames.size > 1)
        frames.forEach { bus.onIncoming(it) }

        assertEquals("plan", applied)
        assertTrue(transport.sent.any { it == "A|abc12345|${frames.size}" })
    }

    @Test
    fun `chunks that arrive out of order still reassemble`() {
        val bus = bus()
        var applied: String? = null
        bus.onMessage = { kind, _ -> applied = kind }

        val frames = framesFor(JSONObject().put("k", "lib").put("n", 1).put("t", 0)
            .put("p", JSONObject().put("v", 1).put("ex", JSONArray())).toString())

        frames.reversed().forEach { bus.onIncoming(it) }

        assertEquals("lib", applied)
        assertEquals(0, bus.partialCount)
    }

    @Test
    fun `a partial message times out`() {
        val bus = bus()
        val frames = framesFor("{\"k\":\"lib\",\"n\":1,\"t\":0,\"p\":{\"v\":1,\"ex\":["
            + (1..40).joinToString(",") { "{\"id\":\"ex_$it\",\"name\":\"Exercise $it\"}" } + "]}}")

        assertTrue(frames.size > 1)
        bus.onIncoming(frames[0])
        assertEquals(1, bus.partialCount)

        now += WatchBus.PARTIAL_TIMEOUT_MS + 1
        bus.tick(now)

        assertEquals(0, bus.partialCount)
    }

    // ---- acknowledgement and dedupe --------------------------------------

    @Test
    fun `an ack removes the message from the queue`() {
        val transport = FakeTransport()
        val bus = bus(transport)

        val id = bus.send("plan", planPayload())
        assertNotNull(id)
        assertEquals(1, bus.pendingCount)
        assertEquals(1, transport.sent.size)

        now += WatchBus.GAP_MS
        bus.onIncoming("A|$id|1")

        assertEquals(0, bus.pendingCount)
    }

    @Test
    fun `a repeated message is acked again but applied once`() {
        val transport = FakeTransport()
        val bus = bus(transport)
        var applies = 0
        bus.onMessage = { _, _ -> applies += 1 }

        val frame = "1|dup00001|0|1|{\"k\":\"plan\",\"n\":1,\"t\":0,\"p\":{\"items\":[]}}"
        assertEquals("plan", bus.onIncoming(frame))

        now += WatchBus.GAP_MS
        assertNull(bus.onIncoming(frame))

        assertEquals(1, applies)
        // Two acks, so a sender that lost the first one stops retrying.
        assertEquals(2, transport.sent.count { it == "A|dup00001|1" })
    }

    @Test
    fun `malformed json is rejected and not applied`() {
        val transport = FakeTransport()
        val bus = bus(transport)
        var applies = 0
        bus.onMessage = { _, _ -> applies += 1 }

        assertNull(bus.onIncoming("1|bad00001|0|1|{\"k\":\"plan\","))
        assertEquals(0, applies)
        assertTrue(transport.sent.contains("N|bad00001|json"))
    }

    @Test
    fun `a wrong protocol version is rejected`() {
        val transport = FakeTransport()
        val bus = bus(transport)

        assertNull(bus.onIncoming("2|ver00001|0|1|{\"k\":\"plan\"}"))
        assertTrue(transport.sent.contains("N|ver00001|ver"))
    }

    @Test
    fun `junk without an envelope is ignored`() {
        val transport = FakeTransport()
        val bus = bus(transport)

        assertNull(bus.onIncoming("bench_press=27.5"))
        assertNull(bus.onIncoming(""))
        assertEquals(0, transport.sent.size)
    }

    @Test
    fun `a body over the limit is refused rather than truncated`() {
        val bus = bus()
        val huge = JSONObject().put("log", "0".repeat(WatchBus.MAX_BODY))
        assertNull(bus.send("end", huge))
        assertEquals(0, bus.pendingCount)
    }

    // ---- retries ---------------------------------------------------------

    @Test
    fun `an unacked message is retried at three, six and twelve seconds`() {
        val transport = FakeTransport()
        transport.drop = true
        val bus = bus(transport)

        bus.send("set", JSONObject().put("ex", "squats"))
        assertEquals(1, transport.sent.size)

        now += 400
        bus.tick(now)
        assertEquals("nothing due yet", 1, transport.sent.size)

        now += 2_800
        bus.tick(now)
        assertEquals("first retry at +3 s", 2, transport.sent.size)

        now += 6_000
        bus.tick(now)
        assertEquals("second retry at +6 s", 3, transport.sent.size)

        now += 12_000
        bus.tick(now)
        assertEquals("third retry at +12 s", 4, transport.sent.size)

        now += 12_000
        bus.tick(now)
        assertEquals(1, bus.failedCount)
        assertEquals(0, bus.pendingCount)
    }

    @Test
    fun `an ack stops the retries`() {
        val transport = FakeTransport()
        transport.drop = true
        val bus = bus(transport)

        val id = bus.send("set", JSONObject().put("ex", "squats"))
        now += 3_100
        bus.tick(now)
        assertEquals(2, transport.sent.size)

        bus.onIncoming("A|$id|1")
        now += 30_000
        bus.tick(now)

        // Only the ack may leave after this point, never another data frame.
        assertEquals("no more data frames after the ack", 2, transport.sent.count { it.startsWith("1|") })
        assertEquals(0, bus.failedCount)
        assertEquals(0, bus.pendingCount)
    }

    // ---- pacing ----------------------------------------------------------

    @Test
    fun `messages are paced at one per gap`() {
        val transport = FakeTransport()
        val bus = bus(transport)

        bus.send("start", JSONObject().put("sid", "s1"))
        bus.send("set", JSONObject().put("ex", "squats"))
        bus.send("end", JSONObject().put("sid", "s1"))

        assertEquals("only one frame leaves inside a gap", 1, transport.sent.size)

        now += WatchBus.GAP_MS
        bus.tick(now)
        assertEquals(2, transport.sent.size)

        now += WatchBus.GAP_MS
        bus.tick(now)
        assertEquals(3, transport.sent.size)
    }

    // ---- end to end ------------------------------------------------------

    @Test
    fun `a full exchange over a fake transport converges`() {
        val phoneFrames = FakeTransport()
        val watchFrames = FakeTransport()
        val phone = bus(phoneFrames)
        val watch = bus(watchFrames)

        phoneFrames.peer = watch
        watchFrames.peer = phone

        var received: JSONObject? = null
        var receivedKind: String? = null
        watch.onMessage = { kind, payload ->
            receivedKind = kind
            received = payload
        }

        val id = phone.sendSnapshot("plan", planPayload())
        assertNotNull(id)

        // Both sides pump once per gap until nothing is outstanding.
        var guard = 0
        while ((phone.pendingCount > 0 || phoneFrames.sent.size < 2) && guard < 40) {
            now += WatchBus.GAP_MS
            phone.tick(now)
            watch.tick(now)
            guard += 1
        }

        assertEquals("plan", receivedKind)
        assertEquals("w-1", received?.optString("wid"))
        assertEquals("the watch acked, so nothing is outstanding", 0, phone.pendingCount)
        assertEquals(0, phone.failedCount)
        assertTrue(watchFrames.sent.any { it.startsWith("A|$id|") })
    }

    @Test
    fun `a watch message reaches the phone and is acked`() {
        val phoneFrames = FakeTransport()
        val watchFrames = FakeTransport()
        val phone = bus(phoneFrames)
        val watch = bus(watchFrames)

        phoneFrames.peer = watch
        watchFrames.peer = phone

        var kind: String? = null
        phone.onMessage = { k, _ -> kind = k }

        val sid = watch.send("end", JSONObject().put("sid", "s-9").put("sets", 4))
        assertNotNull(sid)

        var guard = 0
        while (watch.pendingCount > 0 && guard < 20) {
            now += WatchBus.GAP_MS
            watch.tick(now)
            phone.tick(now)
            guard += 1
        }

        assertEquals("end", kind)
        assertEquals(0, watch.pendingCount)
    }

    @Test
    fun `a rejection from the watch fails the message instead of retrying it`() {
        val transport = FakeTransport()
        transport.drop = true
        val bus = bus(transport)

        val id = bus.send("plan", planPayload())
        now += WatchBus.GAP_MS
        bus.onIncoming("N|$id|json")

        assertEquals(0, bus.pendingCount)
        assertEquals(1, bus.failedCount)
    }

    // ---- reconnect --------------------------------------------------------

    @Test
    fun `ready is handed to the listener with the versions the watch holds`() {
        val transport = FakeTransport()
        val bus = bus(transport)

        var kind: String? = null
        var payload: JSONObject? = null
        bus.onMessage = { k, p ->
            kind = k
            payload = p
        }

        bus.onIncoming(
            "1|ready001|0|1|{\"k\":\"ready\",\"n\":1,\"t\":0," +
                "\"p\":{\"seq\":4,\"libV\":2,\"planV\":3,\"pending\":0,\"bench\":false}}"
        )

        // What to re-send depends on what the phone holds, which only the
        // listener knows, so the payload has to reach it.
        assertEquals("ready", kind)
        assertEquals(3L, payload?.optLong("planV"))
        assertTrue("the frame is still acked", transport.sent.any { it.startsWith("A|ready001|") })
    }

    @Test
    fun `hello with a listener is not answered by the bus itself`() {
        val transport = FakeTransport()
        val bus = bus(transport)
        bus.onMessage = { _, _ -> }

        bus.sendSnapshot("plan", planPayload())
        assertEquals(1, transport.sent.size)

        // The bus must not push every snapshot behind the listener's back: the
        // listener decides, and a second copy would only be a burst.
        now += WatchBus.GAP_MS
        bus.onIncoming("1|hello001|0|1|{\"k\":\"hello\",\"n\":1,\"t\":0}")

        assertEquals("only the ack leaves", 2, transport.sent.size)
        assertTrue(transport.sent[1].startsWith("A|hello001|"))
    }

    @Test
    fun `hello with nobody listening still re-sends the snapshots`() {
        val transport = FakeTransport()
        val bus = bus(transport)

        bus.sendSnapshot("plan", planPayload())
        now += WatchBus.GAP_MS
        bus.onIncoming("1|hello001|0|1|{\"k\":\"hello\",\"n\":1,\"t\":0}")

        // Two frames of the same plan: the original, then the re-send the bare
        // bus does on its own so a reconnect is never a silent dead end.
        val planFrames = transport.sent.count { it.contains("\"k\":\"plan\"") }
        assertEquals(2, planFrames)
    }

    // ---- body shape ------------------------------------------------------

    @Test
    fun `the envelope carries version, id, index and count`() {
        val transport = FakeTransport()
        val bus = bus(transport)
        val id = bus.send("plan", planPayload())

        val frame = transport.sent.first()
        val parts = frame.split("|", limit = 5)

        assertEquals("1", parts[0])
        assertEquals(id, parts[1])
        assertEquals("0", parts[2])
        assertEquals("1", parts[3])

        // org.json does not promise key order, so the body is parsed rather than
        // compared as text.
        val body = JSONObject(parts[4])
        assertEquals("plan", body.optString("k"))
        assertEquals("w-1", body.getJSONObject("p").optString("wid"))
    }
}
