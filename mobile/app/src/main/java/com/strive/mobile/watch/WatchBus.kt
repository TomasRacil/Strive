package com.strive.mobile.watch

import org.json.JSONException
import org.json.JSONObject
import java.util.ArrayDeque

/**
 * Where framed messages leave the bus.
 *
 * The real implementation is `ConnectIQ.sendMessage`; a test supplies an object
 * that hands the string to another bus, which is what makes a phone-to-watch-to-
 * phone exchange testable without the Connect IQ SDK on the classpath.
 */
interface WatchTransport {
    fun send(text: String)
}

/**
 * The phone half of the Strive watch protocol, version 1. See
 * docs/watch-protocol.md.
 *
 * The bus drops bursts silently and reports success anyway, so delivery is only
 * ever inferred from an acknowledgement: a message stays queued until an `A|`
 * arrives for it, and is retried at +3 s, +6 s and +12 s before being given up
 * on. The same envelope, chunking and ack rules apply in both directions.
 *
 * Time is injected, so the retry schedule is tested against a clock rather than
 * a sleep.
 */
class WatchBus(
    private val transport: WatchTransport,
    private val clock: () -> Long = { System.currentTimeMillis() },
    private val log: (String) -> Unit = {}
) {

    companion object {
        const val VERSION = "1"

        /** 400 UTF-16 code units per chunk, never inside a surrogate pair. */
        const val CHUNK_UNITS = 400

        /** A body over this is refused by the sender rather than truncated. */
        const val MAX_BODY = 6000

        const val PARTIAL_TIMEOUT_MS = 120_000L

        /** How many applied ids are remembered, so a replay is not re-applied. */
        const val SEEN_MAX = 32

        const val GAP_MS = 400L

        val RETRY_MS = longArrayOf(3_000, 6_000, 12_000)

        private const val HEX = "0123456789abcdef"
    }

    /** One message on its way out: everything needed to resend it unchanged. */
    private class Outgoing(
        val id: String,
        val body: String,
        var tries: Int = 0,
        var lastSentAt: Long = 0,
        var failed: Boolean = false
    ) {
        var chunks: List<String> = emptyList()
        var nextChunk: Int = 0
    }

    private class Partial(val count: Int, val startedAt: Long) {
        val chunks = HashMap<Int, String>()
    }

    private val queue = ArrayDeque<Outgoing>()
    private val acks = ArrayDeque<String>()
    private val partials = HashMap<String, Partial>()
    private val seen = ArrayDeque<String>()

    private var active: Outgoing? = null
    private var sequence = 0L
    private var lastSentAt = Long.MIN_VALUE / 2

    /** Called for every message that was applied, with its payload. */
    var onMessage: ((kind: String, payload: JSONObject?) -> Unit)? = null

    /** Snapshots the phone owns, re-sent when the watch says it is alive. */
    private val snapshots = LinkedHashMap<String, JSONObject>()

    /** Number of messages sent and not yet acknowledged. */
    val pendingCount: Int
        get() = queue.count { !it.failed }

    val failedCount: Int
        get() = queue.count { it.failed }

    fun pendingIds(): List<String> = queue.filter { !it.failed }.map { it.id }

    // ---- sending ---------------------------------------------------------

    /**
     * Queues one message and returns its id, or null when the body is too long
     * to send at all. Refusing is deliberate: half a library is worse than none.
     */
    fun send(kind: String, payload: JSONObject?): String? {
        val body = buildBody(kind, payload)
        if (body.length > MAX_BODY) {
            log("refused $kind: ${body.length} units")
            return null
        }

        val id = newId()
        queue.addLast(Outgoing(id, body))
        pump(clock())
        return id
    }

    /**
     * Sends a snapshot kind and remembers it, so a reconnect can re-send it
     * without the user asking. `lib`, `plan` and `hist` are the snapshots.
     */
    fun sendSnapshot(kind: String, payload: JSONObject): String? {
        val id = send(kind, payload)
        if (id != null) {
            snapshots[kind] = payload
        }
        return id
    }

    private fun buildBody(kind: String, payload: JSONObject?): String {
        val body = JSONObject()
        body.put("k", kind)
        body.put("n", ++sequence)
        body.put("t", clock() / 1000)
        if (payload != null) {
            body.put("p", payload)
        }
        return body.toString()
    }

    private fun newId(): String {
        // Eight lowercase hex characters. Uniqueness per sender is the whole
        // requirement; the clock is mixed in only so two senders do not collide.
        var mixed = (clock() xor (sequence * 0x9E3779B9L)) and 0xFFFFFFFFL
        val out = StringBuilder(8)
        for (i in 0 until 8) {
            out.append(HEX[(mixed and 0xF).toInt()])
            mixed = mixed shr 4
        }
        return out.toString()
    }

    // ---- receiving -------------------------------------------------------

    /**
     * Handles one raw string from the watch. Returns the kind that was applied,
     * or null when nothing was (a partial chunk, a duplicate, a rejection).
     */
    fun onIncoming(raw: String): String? {
        // Acks and rejections are bare frames, not JSON documents: they are the
        // only thing that stops a sender retrying, so they are parsed first and
        // are never themselves acked.
        if (raw.startsWith("A|")) {
            val id = raw.substring(2).substringBefore('|')
            acknowledge(id)
            log("ack $id")
            return "ack"
        }
        if (raw.startsWith("N|")) {
            val body = raw.substring(2)
            val id = body.substringBefore('|')
            val reason = body.substringAfter('|', "")
            rejectReceived(id, reason)
            return "reject"
        }

        val envelope = parseEnvelope(raw)
        if (envelope == null) {
            log("rx junk")
            return null
        }

        if (envelope.version != VERSION) {
            reject(envelope.id, "ver")
            return null
        }

        val body = if (envelope.count == 1) {
            envelope.chunk
        } else {
            reassemble(envelope) ?: return null
        }

        if (body.length > MAX_BODY) {
            reject(envelope.id, "len")
            return null
        }

        val document = try {
            JSONObject(body)
        } catch (e: JSONException) {
            reject(envelope.id, "json")
            return null
        }

        val kind = document.optString("k", "")
        if (kind.isEmpty()) {
            reject(envelope.id, "json")
            return null
        }

        // A repeat is acked again: the first ack may be what got lost, and the
        // sender is still retrying until it hears one.
        if (isSeen(envelope.id)) {
            ack(envelope.id, envelope.count)
            log("dup $kind")
            return null
        }

        val payload = document.optJSONObject("p")

        if (kind == "ack") {
            acknowledge(payload?.optString("id", "") ?: "")
            return "ack"
        }

        val applied = apply(kind, payload)
        if (applied == null) {
            reject(envelope.id, "apply")
            return null
        }

        remember(envelope.id)
        ack(envelope.id, envelope.count)
        appliedCount += 1
        log("ok $kind")
        return applied
    }

    private class Envelope(
        val version: String,
        val id: String,
        val index: Int,
        val count: Int,
        val chunk: String
    )

    /**
     * The chunk is the last field and may itself contain "|", so the first four
     * separators are found by position and the rest is the chunk.
     */
    private fun parseEnvelope(raw: String): Envelope? {
        val p1 = raw.indexOf('|')
        if (p1 < 0) return null
        val p2 = raw.indexOf('|', p1 + 1)
        if (p2 < 0) return null
        val p3 = raw.indexOf('|', p2 + 1)
        if (p3 < 0) return null
        val p4 = raw.indexOf('|', p3 + 1)
        if (p4 < 0) return null

        val index = raw.substring(p2 + 1, p3).toIntOrNull() ?: return null
        val count = raw.substring(p3 + 1, p4).toIntOrNull() ?: return null
        if (count < 1 || index < 0 || index >= count) return null

        return Envelope(
            version = raw.substring(0, p1),
            id = raw.substring(p1 + 1, p2),
            index = index,
            count = count,
            chunk = raw.substring(p4 + 1)
        )
    }

    private fun reassemble(envelope: Envelope): String? {
        val now = clock()
        val partial = partials[envelope.id]
            ?.takeIf { it.count == envelope.count && now - it.startedAt <= PARTIAL_TIMEOUT_MS }
            ?: Partial(envelope.count, now).also { partials[envelope.id] = it }

        partial.chunks[envelope.index] = envelope.chunk
        if (partial.chunks.size < envelope.count) {
            return null
        }

        val body = StringBuilder()
        for (i in 0 until envelope.count) {
            body.append(partial.chunks[i] ?: return null)
        }
        partials.remove(envelope.id)
        return body.toString()
    }

    // ---- dispatch --------------------------------------------------------

    private fun apply(kind: String, payload: JSONObject?): String? {
        when (kind) {
            // The watch says it is alive and speaking v1. What to re-send is the
            // listener's call, not the bus's: only the phone knows which of its
            // snapshots is newer than the versions the watch reports. A bus with
            // nobody listening still re-sends everything, so a bare transport
            // test keeps the reconnect behaviour.
            "hello", "ready" -> {
                val listener = onMessage
                if (listener == null) resendSnapshots() else listener.invoke(kind, payload)
                return kind
            }
            "ping" -> {
                send("pong", null)
                return kind
            }
            "profile", "lib", "plan", "rec", "hist" -> {
                if (payload == null) return null
                onMessage?.invoke(kind, payload)
                return kind
            }
            "start", "set", "end", "bench" -> {
                onMessage?.invoke(kind, payload)
                return kind
            }
            else -> {
                // A newer watch may say something this build does not know yet;
                // that is not an error, and acking it stops the retries.
                log("skip $kind")
                return kind
            }
        }
    }

    private fun resendSnapshots() {
        for ((kind, payload) in snapshots) {
            send(kind, payload)
        }
    }

    // ---- acknowledgements ------------------------------------------------

    private fun ack(id: String, count: Int) {
        acks.addLast("A|$id|$count")
        pump(clock())
    }

    private fun reject(id: String, reason: String) {
        log("N $reason")
        acks.addLast("N|$id|$reason")
        pump(clock())
    }

    private fun acknowledge(id: String) {
        if (id.isEmpty()) return
        val kept = queue.filter { it.id != id }
        queue.clear()
        queue.addAll(kept)
        if (active?.id == id) {
            active = null
        }
    }

    /**
     * The other side refused the message (bad version, bad JSON, could not
     * apply it). Retrying the same bytes would only be refused again, so it is
     * marked failed and the queue moves on.
     */
    private fun rejectReceived(id: String, reason: String) {
        log("rejected $id: $reason")
        if (id.isEmpty()) return
        queue.filter { it.id == id }.forEach { it.failed = true }
        if (active?.id == id) {
            active = null
        }
    }

    // ---- dedupe ----------------------------------------------------------

    private fun isSeen(id: String) = seen.contains(id)

    private fun remember(id: String) {
        seen.addLast(id)
        while (seen.size > SEEN_MAX) {
            seen.removeFirst()
        }
    }

    // ---- pacing and retries ---------------------------------------------

    /** Drives the queue. Called on a timer, and after anything that queues work. */
    fun tick(now: Long = clock()) {
        expirePartials(now)
        pump(now)
    }

    private fun expirePartials(now: Long) {
        val dead = partials.filterValues { now - it.startedAt > PARTIAL_TIMEOUT_MS }.keys
        dead.forEach { partials.remove(it) }
    }

    private fun pump(now: Long) {
        if (now - lastSentAt < GAP_MS) return

        val next = nextFrame(now) ?: return
        transport.send(next)
        lastFrame = next
        lastSentAt = now
    }

    /**
     * One frame to put on the wire: an ack, the next chunk of the message in
     * flight, the first chunk of a new one, or a retry. Retries come last so a
     * long queue is not starved by a message the watch may simply have dropped.
     */
    private fun nextFrame(now: Long): String? {
        acks.pollFirst()?.let { return it }

        active?.let { entry ->
            if (entry.nextChunk < entry.chunks.size) {
                return chunkFrame(entry, now)
            }
            active = null
        }

        queue.firstOrNull { it.tries == 0 && !it.failed }?.let { entry ->
            entry.chunks = chunk(entry.body)
            entry.nextChunk = 0
            active = entry
            return chunkFrame(entry, now)
        }

        for (entry in queue) {
            if (entry.failed || entry.tries == 0) continue
            val waited = now - entry.lastSentAt

            if (entry.tries > RETRY_MS.size) {
                if (waited >= RETRY_MS.last()) {
                    entry.failed = true
                    log("fail ${entry.id}")
                }
                continue
            }

            if (waited >= RETRY_MS[entry.tries - 1]) {
                entry.chunks = chunk(entry.body)
                entry.nextChunk = 0
                active = entry
                return chunkFrame(entry, now)
            }
        }
        return null
    }

    private fun chunkFrame(entry: Outgoing, now: Long): String {
        val index = entry.nextChunk
        entry.nextChunk = index + 1

        if (index == 0) {
            entry.tries += 1
            entry.lastSentAt = now
        }

        return "$VERSION|${entry.id}|$index|${entry.chunks.size}|${entry.chunks[index]}"
    }

    /**
     * Cuts a body on UTF-16 code units, never inside a surrogate pair: a split
     * pair arrives as two replacement characters and the watch stores a mangled
     * exercise name.
     */
    fun chunk(body: String): List<String> {
        val out = ArrayList<String>()
        var start = 0

        while (start < body.length) {
            var end = minOf(start + CHUNK_UNITS, body.length)
            if (end < body.length && Character.isHighSurrogate(body[end - 1])) {
                end -= 1
            }
            out.add(body.substring(start, end))
            start = end
        }

        if (out.isEmpty()) out.add("")
        return out
    }

    // ---- diagnostics -----------------------------------------------------

    /** Number of messages applied since the bus was created. */
    var appliedCount: Int = 0
        private set

    /** Number of partial messages currently held. */
    val partialCount: Int
        get() = partials.size

    /** Last frame the bus put on the wire. */
    var lastFrame: String? = null
        private set
}
