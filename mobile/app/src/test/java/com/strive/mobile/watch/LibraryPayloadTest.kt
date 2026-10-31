package com.strive.mobile.watch

import com.strive.mobile.data.Exercise
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The `lib` snapshot, encoded and decoded the way it travels.
 *
 * The assertion is on what the watch would actually parse, not on the object the
 * builder returned: a field that exists in memory and is lost in the frame is
 * exactly the bug #18 and #19 were, so the payload goes through the real bus -
 * framing, chunking, reassembly - before anything is read back.
 */
class LibraryPayloadTest {

    /** Records what would have gone out and hands it to a peer bus, if any. */
    private class FakeTransport : WatchTransport {
        val sent = mutableListOf<String>()
        var peer: WatchBus? = null

        override fun send(text: String) {
            sent.add(text)
            peer?.onIncoming(text)
        }
    }

    private var now = 1_000_000L

    private fun bus(transport: WatchTransport) = WatchBus(transport = transport, clock = { now })

    /** A user-added calisthenics movement: bodyweight, with a stabiliser. */
    private fun ringDip() = Exercise(
        id = "ring_dip",
        name = "Ring Dip",
        muscle = "Chest",
        targetReps = 8,
        restSeconds = 120,
        primary = mapOf("chest" to 1.0, "triceps" to 0.8),
        secondary = mapOf("front_delts" to 0.5),
        bodyweightFraction = 1.0
    )

    /** Sends [exercises] over a phone bus and returns what the watch bus applied. */
    private fun roundTrip(exercises: List<Exercise>): JSONObject {
        val phoneFrames = FakeTransport()
        val watchFrames = FakeTransport()
        val phone = bus(phoneFrames)
        val watch = bus(watchFrames)
        phoneFrames.peer = watch
        watchFrames.peer = phone

        var receivedKind: String? = null
        var received: JSONObject? = null
        watch.onMessage = { kind, payload ->
            receivedKind = kind
            received = payload
        }

        assertNotNull(phone.sendSnapshot("lib", LibraryPayload.of(exercises, version = 5)))

        var guard = 0
        while ((phone.pendingCount > 0 || received == null) && guard < 40) {
            now += WatchBus.GAP_MS
            phone.tick(now)
            watch.tick(now)
            guard += 1
        }

        assertEquals("lib", receivedKind)
        return received ?: throw AssertionError("the watch applied nothing")
    }

    @Test
    fun `a bodyweight fraction survives the encoder`() {
        val payload = roundTrip(listOf(ringDip()))

        val row = payload.getJSONArray("ex").getJSONObject(0)
        assertEquals("ring_dip", row.getString("id"))
        assertEquals(1.0, row.getDouble("bw"), 0.0001)
    }

    @Test
    fun `primary and secondary shares travel as two groups`() {
        val payload = roundTrip(listOf(ringDip()))

        val row = payload.getJSONArray("ex").getJSONObject(0)
        val primary = sharesOf(row.getJSONArray("mus"))
        val secondary = sharesOf(row.getJSONArray("sec"))

        assertEquals(mapOf("chest" to 1.0, "triceps" to 0.8), primary)
        assertEquals(mapOf("front_delts" to 0.5), secondary)
        // The watch reads `mus` as prime movers and discounts `sec`; a muscle in
        // both would be counted twice.
        assertTrue("primary and secondary must not overlap", primary.keys.none { it in secondary })
    }

    @Test
    fun `an exercise with no muscle maps still carries empty groups`() {
        val bare = ringDip().copy(primary = emptyMap(), secondary = emptyMap(), bodyweightFraction = null)

        val row = roundTrip(listOf(bare)).getJSONArray("ex").getJSONObject(0)

        assertEquals(0, row.getJSONArray("mus").length())
        assertEquals(0, row.getJSONArray("sec").length())
        // No fraction on the entry: the shipped table has nothing for this id,
        // so it travels as a loaded lift rather than as null.
        assertEquals(0.0, row.getDouble("bw"), 0.0001)
    }

    @Test
    fun `a shipped lift keeps the fraction from the table`() {
        val pullUps = ringDip().copy(id = "pull_ups", name = "Pull-ups", bodyweightFraction = null)

        val row = roundTrip(listOf(pullUps)).getJSONArray("ex").getJSONObject(0)

        assertEquals(1.0, row.getDouble("bw"), 0.0001)
    }

    /** `[[muscle, share], ...]` as a map, the way the watch's sharesOf reads it. */
    private fun sharesOf(pairs: org.json.JSONArray): Map<String, Double> {
        val out = LinkedHashMap<String, Double>()
        (0 until pairs.length()).forEach { i ->
            val pair = pairs.getJSONArray(i)
            out[pair.getString(0)] = pair.getDouble(1)
        }
        return out
    }
}
