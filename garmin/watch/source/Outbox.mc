using Toybox.Application as App;
using Toybox.Communications as Comm;
using Toybox.Lang;
using Toybox.System as Sys;
using Toybox.Time as Time;
using Toybox.Timer as Timer;

// The one place that calls transmit.
//
// The transport drops bursts silently - 18 sends arrived as 12, with no error -
// so nothing may be sent while another send is in flight, and every send waits
// out a gap. Routing all of it through one object is also what lets a unit test
// capture what would have gone out without a radio, and without a timer.
// A real transmit in the simulator raises a modal "no data connection" dialog
// that blocks the whole run, so the radio is OFF unless the app asks for it.
// Defaulting to the stub means a test that forgets to reset still cannot wedge
// the suite; StriveApp.onStart turns the radio back on.
module Wire {

    var testing = true;
    var sent = null;

    function useRadio() as Void {
        testing = false;
    }

    function reset() as Void {
        testing = true;
        sent = [] as Lang.Array<Lang.String>;
    }

    function send(text) as Void {
        if (testing) {
            if (sent == null) {
                sent = [] as Lang.Array<Lang.String>;
            }
            sent.add(text);
            return;
        }
        Comm.transmit(text, null, new PhoneListener());
    }
}

// The bound on the queue.
//
// A session is one `start`, its `set`s and one `end`; 40 sets is a long workout,
// so 42 frames is the worst realistic session and the cap has to clear it with
// room for the next session's opening. 64 leaves a full session plus 22 frames of
// the next. At roughly 200 bytes of persisted JSON per `set` that bounds the
// queue to about 13 KB, which fits the 32 KB object store a fenix gives an app; a
// queue of nothing but `end`s would not, which is what the storage guard is for.
// Unbounded, an offline week grows the queue until setValue throws and every
// later set is lost.
//
// A module constant rather than a class one: Monkey C resolves a class constant
// only inside its own class, and the tests must assert against this number rather
// than restate it.
module OutboxLimits {
    const PENDING = 64;
}

// The persistent outbound queue.
//
// A message is written to Storage before transmit is called and removed only
// when the phone acknowledges it, so a session log survives a killed app, a flat
// battery and a phone that is not there. Nothing here treats a transmit callback
// as delivery.
//
// Two things bound the damage when the phone stays away. The queue is capped, so
// an offline week cannot grow it until Storage throws; and every write tolerates
// a full store, because an exception escaping a set being logged costs the
// workout, which is worse than losing the tail of the queue.
class Outbox {

    // Measured: faster than this and the receiver silently drops messages.
    const GAP_MS = 400;

    // If the transmit callback never arrives, do not stall the queue for ever.
    const STALL_MS = 2000;

    // +3 s, +6 s, +12 s, then give up on the message and move on.
    const RETRY_SECONDS = [3, 6, 12];

    const IDS_KEY = "ob_ids";
    const ENTRY_PREFIX = "ob_";

    // Messages, in send order. Each is a Dictionary: id, body, tries, at, failed,
    // end. `end` is stamped from the body when the frame is queued: the drop
    // policy needs to know which frames close a session, and re-reading the body
    // on every eviction would be work in the one place that must stay cheap.
    var order;

    // Acks and rejections, sent once and never retried: if one is lost the
    // sender simply asks again, and the repeat is acked then.
    var raw;

    // The message currently being cut into chunks.
    var active;

    var cursor;
    var sending;
    var lastSentAt;
    var timer;

    // Set once Storage has refused a write or a delete: the queue is still
    // correct in memory, but it is no longer certain to survive a restart, and
    // the UI has to be able to say so.
    var storageFailedFlag;

    // Frames given up to keep the queue inside its cap, this session.
    var dropped;

    // Test seam. Monkey C has no mock framework and no way to fill the object
    // store from a unit test cheaply, so a test flips this and every write
    // behaves as if the store were full.
    var simulateFull;

    function initialize() {
        order = [] as Lang.Array;
        raw = [] as Lang.Array<Lang.String>;
        active = null;
        cursor = 0;
        sending = false;
        // Start "one gap ago" so the first message goes out immediately.
        lastSentAt = Sys.getTimer() - GAP_MS;
        timer = null;
        storageFailedFlag = false;
        dropped = 0;
        simulateFull = false;
    }

    // ---- queue -----------------------------------------------------------

    // Persists first, then transmits. The order matters: a message that was sent
    // but never written down is exactly the work that gets lost.
    function add(id, body) as Void {
        var entry = {
            "id" => id,
            "body" => body,
            "tries" => 0,
            "at" => 0,
            "failed" => false,
            "end" => Text.same(kindOf(body), "end")
        };

        // Make room before writing, so the frame that goes is gone from Storage
        // before the new one needs the space.
        if (!makeRoom(entry["end"])) {
            // Nothing left to sacrifice that is worth less than this frame: a
            // queue of nothing but `end`s and another `set` arriving. The `set`
            // is the one that loses.
            dropped += 1;
            note("drop full " + Bus.shortId(id));
            return;
        }

        persist(entry);
        order.add(entry);
        saveOrder();
        pump();
    }

    // The kind of a message, read off the front of its body.
    //
    // Bus writes the body with a top-level `k` field before the payload, so the
    // scan for the marker finds it; parsing the whole document would build a
    // log-sized dictionary just to read one word. A body with no marker is
    // treated as an ordinary frame, which is the safe side: it may be dropped.
    function kindOf(body) as Lang.String {
        var marker = "\"k\":\"";
        var at = body.find(marker);
        if (at == null) {
            return "";
        }

        var start = at + marker.length();
        // Kinds are a handful of characters, so the closing quote is close by
        // and the search does not need a copy of the whole body.
        var limit = start + 12;
        if (limit > body.length()) {
            limit = body.length();
        }
        var tail = body.substring(start, limit);
        var stop = tail.find("\"");
        if (stop == null) {
            return "";
        }
        return tail.substring(0, stop);
    }

    // Index of the frame to give up: the oldest one that is not an `end`, or the
    // oldest at all when every frame is an `end` and an `end` is what needs the
    // room. -1 means there is nothing to give up.
    function victimIndex(allowEnd) as Lang.Number {
        for (var i = 0; i < order.size(); i++) {
            if (!order[i]["end"]) {
                return i;
            }
        }
        if (allowEnd && order.size() > 0) {
            return 0;
        }
        return -1;
    }

    // FIFO, with one exception that is the whole point: a stale `set` is worth
    // less than the `end` that closes the session, so an `end` is never dropped
    // to make room for a `set`. Returns false when the incoming frame has to be
    // the one that goes.
    function makeRoom(incomingIsEnd) as Lang.Boolean {
        while (order.size() >= OutboxLimits.PENDING) {
            var victim = victimIndex(incomingIsEnd);
            if (victim < 0) {
                return false;
            }
            drop(victim);
        }
        return true;
    }

    // A dropped frame is counted and named, never silently forgotten: "the queue
    // was full" is the only explanation for a session that reaches the phone
    // with a hole in it.
    function drop(index) as Void {
        var entry = order[index];

        var kept = [] as Lang.Array;
        for (var i = 0; i < order.size(); i++) {
            if (i != index) {
                kept.add(order[i]);
            }
        }
        order = kept;

        // The cursor counts positions in `order`, so removing anything the
        // sender has already passed moves it back with the frames.
        if (index < cursor) {
            cursor -= 1;
        }
        if (active != null && Text.same(active["id"], entry["id"])) {
            active = null;
        }

        forget(entry);
        dropped += 1;
        note("drop " + Bus.shortId(entry["id"]));
    }

    function droppedCount() as Lang.Number {
        return dropped;
    }

    // Acks jump the queue: the other side is holding a retry timer open.
    function addRaw(text) as Void {
        raw.add(text);
        pump();
    }

    // The phone has the message; an ack is the only thing that removes it.
    function acked(id) as Void {
        var kept = [] as Lang.Array;
        for (var i = 0; i < order.size(); i++) {
            if (Text.same(order[i]["id"], id)) {
                forget(order[i]);
                if (active != null && Text.same(active["id"], id)) {
                    active = null;
                }
                continue;
            }
            kept.add(order[i]);
        }
        order = kept;
        saveOrder();
    }

    function pending() as Lang.Number {
        var count = 0;
        for (var i = 0; i < order.size(); i++) {
            if (!order[i]["failed"]) {
                count += 1;
            }
        }
        return count;
    }

    function failedCount() as Lang.Number {
        var count = 0;
        for (var i = 0; i < order.size(); i++) {
            if (order[i]["failed"]) {
                count += 1;
            }
        }
        return count;
    }

    function triesFor(id) as Lang.Number {
        for (var i = 0; i < order.size(); i++) {
            if (Text.same(order[i]["id"], id)) {
                return order[i]["tries"];
            }
        }
        return -1;
    }

    function isFailed(id) as Lang.Boolean {
        for (var i = 0; i < order.size(); i++) {
            if (Text.same(order[i]["id"], id)) {
                return order[i]["failed"];
            }
        }
        return false;
    }

    // The phone refused the message outright, so resending the same bytes would
    // only be refused again. Marked failed and dropped from Storage at once.
    function failed(id) as Void {
        for (var i = 0; i < order.size(); i++) {
            if (Text.same(order[i]["id"], id)) {
                order[i]["failed"] = true;
                forget(order[i]);
                if (active != null && Text.same(active["id"], id)) {
                    active = null;
                }
            }
        }
        saveOrder();
    }

    // Reads the queue back after a restart. A message that was already marked
    // failed is dropped here rather than kept: a poisoned message must not be
    // able to wedge the queue for ever.
    function load() as Void {
        order = [] as Lang.Array;
        active = null;
        cursor = 0;

        var stored = App.Storage.getValue(IDS_KEY);
        if (stored == null) {
            return;
        }

        var ids = Text.split(stored, ",");
        for (var i = 0; i < ids.size(); i++) {
            var text = App.Storage.getValue(ENTRY_PREFIX + ids[i]);
            if (text == null) {
                continue;
            }

            var parsed = Json.parse(text);
            if (parsed == null || !(parsed instanceof Lang.Dictionary)) {
                writeDelete(ENTRY_PREFIX + ids[i]);
                continue;
            }

            if (parsed["f"] == true) {
                writeDelete(ENTRY_PREFIX + ids[i]);
                continue;
            }

            order.add({
                "id" => ids[i],
                "body" => parsed["b"],
                "tries" => 0,
                "at" => 0,
                "failed" => false,
                // The stored format carries no kind, so it is read back off the
                // body: a queue written by an older build must still know which
                // of its frames are `end`s before it can drop anything.
                "end" => Text.same(kindOf(parsed["b"]), "end")
            });
        }

        // A store written before the cap existed, or by a build with a larger
        // one, can come back longer than OutboxLimits.PENDING.
        while (order.size() > OutboxLimits.PENDING) {
            var victim = victimIndex(true);
            if (victim < 0) {
                break;
            }
            drop(victim);
        }

        saveOrder();
        pump();
    }

    // ---- transport -------------------------------------------------------

    function pump() as Void {
        // A unit test has no radio and no event loop: send everything now, in
        // order, and let the test read Wire.sent.
        if (Wire.testing) {
            var guard = 0;
            while (step() && guard < 256) {
                guard += 1;
            }
            return;
        }

        // Nothing to talk to. Pushing bytes at an absent phone costs nothing on
        // hardware but the simulator answers with a modal "no data connection"
        // dialog, and a modal dialog stops the queue dead. The queue is
        // persistent, so this is a wait rather than a loss: it drains again on
        // onShow, on `hello` and on `pong`.
        if (!Sys.getDeviceSettings().phoneConnected) {
            return;
        }

        if (timer == null) {
            timer = new Timer.Timer();
        }

        var now = Sys.getTimer();
        if (sending && now - lastSentAt < STALL_MS) {
            arm(GAP_MS);
            return;
        }
        sending = false;

        var gapLeft = GAP_MS - (now - lastSentAt);
        if (gapLeft > 0) {
            arm(gapLeft);
            return;
        }

        if (step()) {
            return;
        }
        if (serviceRetries()) {
            return;
        }
        if (hasWork()) {
            arm(GAP_MS);
        }
    }

    // One unit of work: one ack, one chunk, or the first chunk of the next
    // message. Returns false when there is nothing queued to send.
    function step() as Lang.Boolean {
        if (raw.size() > 0) {
            var text = raw[0];
            raw = raw.slice(1, raw.size());
            deliver(text);
            return true;
        }

        if (active != null && active["ci"] < active["chunks"].size()) {
            sendChunk(active);
            return true;
        }

        if (cursor < order.size()) {
            active = order[cursor];
            cursor += 1;
            active["chunks"] = Bus.chunk(active["body"]);
            active["ci"] = 0;
            sendChunk(active);
            return true;
        }

        return false;
    }

    function arm(delayMs) as Void {
        if (timer == null) {
            timer = new Timer.Timer();
        }
        timer.start(method(:onTick), delayMs < 0 ? 0 : delayMs, false);
    }

    function onTick() as Void {
        pump();
    }

    // Called from the transmit listener, success or failure alike: the queue
    // waits out the gap, never for the phone.
    function onSent() as Void {
        sending = false;
        pump();
    }

    function deliver(text) as Void {
        if (Wire.testing) {
            Wire.send(text);
            return;
        }

        sending = true;
        lastSentAt = Sys.getTimer();
        Wire.send(text);
        arm(GAP_MS);
    }

    function sendChunk(entry) as Void {
        var chunks = entry["chunks"];
        var index = entry["ci"];
        entry["ci"] = index + 1;

        // The attempt is stamped on its first chunk, so the retry clock starts
        // when the message starts going out rather than when it finishes.
        if (index == 0) {
            entry["tries"] = entry["tries"] + 1;
            entry["at"] = Time.now().value();
            persist(entry);
        }

        deliver(Bus.envelope(entry["id"], index, chunks.size(), chunks[index]));
    }

    function serviceRetries() as Lang.Boolean {
        var now = Time.now().value();

        for (var i = 0; i < order.size(); i++) {
            var entry = order[i];
            if (entry["failed"] || entry["tries"] == 0) {
                continue;
            }

            var tries = entry["tries"];
            var waited = now - entry["at"];

            if (tries > RETRY_SECONDS.size()) {
                if (waited >= RETRY_SECONDS[RETRY_SECONDS.size() - 1]) {
                    // Kept in memory with the flag for this session, dropped from
                    // Storage straight away: nothing may replay a message that
                    // has already had every chance.
                    entry["failed"] = true;
                    forget(entry);
                    saveOrder();
                    note("fail " + Bus.shortId(entry["id"]));
                }
                continue;
            }

            if (waited >= RETRY_SECONDS[tries - 1]) {
                active = entry;
                entry["chunks"] = Bus.chunk(entry["body"]);
                entry["ci"] = 0;
                sendChunk(entry);
                return true;
            }
        }
        return false;
    }

    function hasWork() as Lang.Boolean {
        if (raw.size() > 0 || cursor < order.size()) {
            return true;
        }
        if (active != null && active["ci"] < active["chunks"].size()) {
            return true;
        }
        for (var i = 0; i < order.size(); i++) {
            if (!order[i]["failed"]) {
                return true;
            }
        }
        return false;
    }

    // ---- storage ---------------------------------------------------------

    // Every write in this class goes through here.
    //
    // Application.Storage throws StorageFullException when the object store's
    // quota is exhausted (and ObjectStoreAccessException from a background
    // process), and an exception escaping a `set` being logged takes the whole
    // workout down with it. A refused write is a smaller loss than that: the
    // queue keeps working in memory for the rest of the session, the flag goes
    // up so the UI can say the queue will not survive a restart, and the caller
    // is told so it can decide what to do next.
    function writeValue(key, value) as Lang.Boolean {
        if (simulateFull) {
            storageFailedFlag = true;
            return false;
        }

        try {
            App.Storage.setValue(key, value);
            return true;
        } catch (e instanceof Lang.Exception) {
            storageFailedFlag = true;
            return false;
        }
    }

    // Deletes cannot exhaust a quota, but they can still be refused. One that
    // fails leaves an acked or dropped frame on disk, which is exactly the state
    // this queue exists to avoid, so it raises the same flag.
    function writeDelete(key) as Void {
        if (simulateFull) {
            return;
        }

        try {
            App.Storage.deleteValue(key);
        } catch (e instanceof Lang.Exception) {
            storageFailedFlag = true;
        }
    }

    // Bus.note is a Storage write too, and it is called from inside the drop and
    // retry paths where a throw would abort the caller mid-queue.
    function note(text) as Void {
        try {
            Bus.note(text);
        } catch (e instanceof Lang.Exception) {
            storageFailedFlag = true;
        }
    }

    // True once Storage has refused a write or a delete. The UI reads this to
    // tell the user the queue is only in memory.
    function storageFailed() as Lang.Boolean {
        return storageFailedFlag;
    }

    function persist(entry) as Void {
        writeValue(
            ENTRY_PREFIX + entry["id"],
            Json.write({
                "b" => entry["body"],
                "f" => entry["failed"],
                "r" => entry["tries"]
            })
        );
    }

    function forget(entry) as Void {
        writeDelete(ENTRY_PREFIX + entry["id"]);
    }

    function saveOrder() as Void {
        var ids = [] as Lang.Array<Lang.String>;
        for (var i = 0; i < order.size(); i++) {
            if (!order[i]["failed"]) {
                ids.add(order[i]["id"]);
            }
        }

        // An empty queue deletes the index rather than storing "": a fully acked
        // outbox then holds no keys at all, which is what "purged" has to mean.
        if (ids.size() == 0) {
            writeDelete(IDS_KEY);
            return;
        }

        writeValue(IDS_KEY, Bus.join(ids));
    }

    // Test seam: everything this queue has ever written, dropped.
    function reset() as Void {
        var stored = App.Storage.getValue(IDS_KEY);
        if (stored != null) {
            var ids = Text.split(stored, ",");
            for (var i = 0; i < ids.size(); i++) {
                writeDelete(ENTRY_PREFIX + ids[i]);
            }
        }
        writeDelete(IDS_KEY);

        order = [] as Lang.Array;
        raw = [] as Lang.Array<Lang.String>;
        active = null;
        cursor = 0;
        sending = false;
        lastSentAt = Sys.getTimer() - GAP_MS;
        storageFailedFlag = false;
        dropped = 0;
        simulateFull = false;
        if (timer != null) {
            timer.stop();
        }
    }
}
