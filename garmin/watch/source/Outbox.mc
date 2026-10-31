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
module Wire {

    var testing = false;
    var sent = null;

    function reset() as Void {
        testing = true;
        sent = [] as Lang.Array<Lang.String>;
    }

    function send(text) as Void {
        if (testing) {
            sent.add(text);
            return;
        }
        Comm.transmit(text, null, new PhoneListener());
    }
}

// The persistent outbound queue.
//
// A message is written to Storage before transmit is called and removed only
// when the phone acknowledges it, so a session log survives a killed app, a flat
// battery and a phone that is not there. Nothing here treats a transmit callback
// as delivery.
class Outbox {

    // Measured: faster than this and the receiver silently drops messages.
    const GAP_MS = 400;

    // If the transmit callback never arrives, do not stall the queue for ever.
    const STALL_MS = 2000;

    // +3 s, +6 s, +12 s, then give up on the message and move on.
    const RETRY_SECONDS = [3, 6, 12];

    const IDS_KEY = "ob_ids";
    const ENTRY_PREFIX = "ob_";

    // Messages, in send order. Each is a Dictionary: id, body, tries, at, failed.
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

    function initialize() {
        order = [] as Lang.Array;
        raw = [] as Lang.Array<Lang.String>;
        active = null;
        cursor = 0;
        sending = false;
        // Start "one gap ago" so the first message goes out immediately.
        lastSentAt = Sys.getTimer() - GAP_MS;
        timer = null;
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
            "failed" => false
        };

        persist(entry);
        order.add(entry);
        saveOrder();
        pump();
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
                App.Storage.deleteValue(ENTRY_PREFIX + ids[i]);
                continue;
            }

            if (parsed["f"] == true) {
                App.Storage.deleteValue(ENTRY_PREFIX + ids[i]);
                continue;
            }

            order.add({
                "id" => ids[i],
                "body" => parsed["b"],
                "tries" => 0,
                "at" => 0,
                "failed" => false
            });
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
                    Bus.note("fail " + Bus.shortId(entry["id"]));
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

    function persist(entry) as Void {
        App.Storage.setValue(
            ENTRY_PREFIX + entry["id"],
            Json.write({
                "b" => entry["body"],
                "f" => entry["failed"],
                "r" => entry["tries"]
            })
        );
    }

    function forget(entry) as Void {
        App.Storage.deleteValue(ENTRY_PREFIX + entry["id"]);
    }

    function saveOrder() as Void {
        var ids = [] as Lang.Array<Lang.String>;
        for (var i = 0; i < order.size(); i++) {
            if (!order[i]["failed"]) {
                ids.add(order[i]["id"]);
            }
        }
        App.Storage.setValue(IDS_KEY, Bus.join(ids));
    }

    // Test seam: everything this queue has ever written, dropped.
    function reset() as Void {
        var stored = App.Storage.getValue(IDS_KEY);
        if (stored != null) {
            var ids = Text.split(stored, ",");
            for (var i = 0; i < ids.size(); i++) {
                App.Storage.deleteValue(ENTRY_PREFIX + ids[i]);
            }
        }
        App.Storage.deleteValue(IDS_KEY);

        order = [] as Lang.Array;
        raw = [] as Lang.Array<Lang.String>;
        active = null;
        cursor = 0;
        sending = false;
        lastSentAt = Sys.getTimer() - GAP_MS;
        if (timer != null) {
            timer.stop();
        }
    }
}
