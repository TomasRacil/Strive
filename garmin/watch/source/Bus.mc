using Toybox.Application as App;
using Toybox.Lang;
using Toybox.System as Sys;
using Toybox.Time as Time;

// The framed message bus, protocol v1. See docs/watch-protocol.md.
//
// The transport drops messages silently and reports success anyway, so delivery
// is only ever inferred from an acknowledgement. One message is one JSON
// document, cut into 400-code-unit chunks, reassembled from Storage so a
// half-arrived message survives the app being killed, applied, and then acked.
//
// Every failure path here is silent on purpose: this runs inside
// onPhoneAppMessage, and an exception there takes the app down with it.
module Bus {

    const VERSION = "1";

    // 400 code units per chunk, and a body over 6000 is refused rather than
    // truncated - half a library is worse than no library.
    const CHUNK_UNITS = 400;
    const MAX_BODY = 6000;

    // A partial message older than this is dropped. Two minutes is longer than
    // any sane transfer and shorter than a workout.
    const PARTIAL_TIMEOUT_S = 120;

    // Enough to cover a reconnect replay without growing without bound.
    const SEEN_MAX = 32;

    const SEQ_KEY = "bus_seq";
    const SEEN_KEY = "bus_seen";
    const PARTS_KEY = "bus_parts";
    const DEBUG_KEY = "ble_dbg";

    // ---- identity --------------------------------------------------------

    function nextSeq() as Lang.Number {
        var value = App.Storage.getValue(SEQ_KEY);
        var seq = value == null ? 1 : value + 1;
        App.Storage.setValue(SEQ_KEY, seq);
        return seq;
    }

    // 8 lowercase hex characters. Uniqueness per sender is what matters, and
    // seconds + a counter + the app timer is enough for one watch talking to one
    // phone; nothing here needs to be cryptographic.
    function newId() as Lang.String {
        var seq = nextSeq();
        var base = Time.now().value() % 65521;
        var mixed = (base * 40503 + seq * 7919 + Sys.getTimer()) % 65536;
        return Json.hex4(base % 65536) + Json.hex4(mixed);
    }

    // ---- sending ---------------------------------------------------------

    function body(kind, payload) as Lang.String {
        var doc = {
            "k" => kind,
            "n" => nextSeq(),
            "t" => Time.now().value()
        };
        if (payload != null) {
            doc["p"] = payload;
        }
        return Json.write(doc);
    }

    // Queues a message. False means the body was too long to send at all, which
    // the caller reports rather than the bus silently shrinking.
    function send(kind, payload) as Lang.Boolean {
        var text = body(kind, payload);
        if (text.length() > MAX_BODY) {
            note("too long " + text.length().toString());
            return false;
        }
        StriveApp.enqueue(newId(), text);
        return true;
    }

    // Cuts a body on UTF-16 code units, never inside a surrogate pair: a split
    // pair arrives as two replacement characters and the phone stores a mangled
    // exercise name.
    function chunk(text) as Lang.Array {
        var out = [] as Lang.Array<Lang.String>;
        var size = text.length();
        var start = 0;

        while (start < size) {
            var end = start + CHUNK_UNITS;
            if (end > size) {
                end = size;
            } else {
                var last = text.substring(end - 1, end).toCharArray()[0].toNumber();
                if (last >= 55296 && last <= 56319) {
                    end -= 1;
                }
            }
            out.add(text.substring(start, end));
            start = end;
        }

        if (out.size() == 0) {
            out.add("");
        }
        return out;
    }

    function envelope(id, index, count, chunkText) as Lang.String {
        return VERSION + "|" + id + "|" + index.toString() + "|" + count.toString() + "|" + chunkText;
    }

    function ack(id, count) as Void {
        StriveApp.enqueueRaw("A|" + id + "|" + count.toString());
    }

    function reject(id, reason) as Void {
        note("N " + reason);
        StriveApp.enqueueRaw("N|" + id + "|" + reason);
    }

    // ---- receiving -------------------------------------------------------

    // Handles one raw string from the phone. Returns the applied message kind so
    // the screen can redraw, or null when nothing was applied.
    function receive(raw) as Lang.String or Null {
        if (raw == null || raw.length() == 0) {
            return null;
        }

        // Acks and rejections are bare frames, not JSON documents. They are the
        // only thing that takes a message out of the outbox, so they are handled
        // before anything else and are never themselves acked.
        if (raw.length() >= 2) {
            var head = raw.substring(0, 2);
            if (Text.same(head, "A|")) {
                var ackId = raw.substring(2, raw.length());
                var bar = Text.indexOf(ackId, "|", 0);
                if (bar != null) {
                    ackId = ackId.substring(0, bar);
                }
                StriveApp.acked(ackId);
                note("A " + shortId(ackId));
                return "ack";
            }
            if (Text.same(head, "N|")) {
                var body = raw.substring(2, raw.length());
                var bar = Text.indexOf(body, "|", 0);
                var rejected = bar == null ? body : body.substring(0, bar);
                StriveApp.rejected(rejected);
                note("N rx");
                return "reject";
            }
        }

        var parts = splitEnvelope(raw);
        if (parts == null) {
            note("rx?");
            return null;
        }

        var id = parts["id"];
        var count = parts["n"];

        if (!Text.same(parts["v"], VERSION)) {
            reject(id, "ver");
            return null;
        }

        var text = null;
        if (count == 1) {
            text = parts["chunk"];
        } else {
            text = assemble(id, parts["i"], count, parts["chunk"]);
            if (text == null) {
                return null;
            }
        }

        if (text.length() > MAX_BODY) {
            reject(id, "len");
            return null;
        }

        var doc = Json.parse(text);
        if (doc == null || !(doc instanceof Lang.Dictionary)) {
            reject(id, "json");
            return null;
        }

        var kind = doc["k"];
        if (kind == null || !(kind instanceof Lang.String)) {
            reject(id, "json");
            return null;
        }

        // A repeat is acked again: the first ack may be what got lost, and the
        // sender is still retrying until it hears one.
        if (seen(id)) {
            ack(id, count);
            note("dup " + kind);
            return null;
        }

        var applied = apply(kind, doc["p"]);

        if (Text.same(kind, "ack")) {
            // Never acked, or two watches that each ack the other's ack never
            // stop talking.
            note("A " + shortId(id));
            return applied;
        }

        if (applied == null) {
            reject(id, "apply");
            return null;
        }

        remember(id);
        ack(id, count);
        note("ok " + kind);
        return applied;
    }

    // The chunk is the last field and may itself contain "|", so the first four
    // separators are found by position and everything after the fourth is the
    // chunk.
    function splitEnvelope(raw) as Lang.Dictionary or Null {
        var p1 = Text.indexOf(raw, "|", 0);
        if (p1 == null) {
            return null;
        }
        var p2 = Text.indexOf(raw, "|", p1 + 1);
        if (p2 == null) {
            return null;
        }
        var p3 = Text.indexOf(raw, "|", p2 + 1);
        if (p3 == null) {
            return null;
        }
        var p4 = Text.indexOf(raw, "|", p3 + 1);
        if (p4 == null) {
            return null;
        }

        var index = raw.substring(p2 + 1, p3).toNumber();
        var count = raw.substring(p3 + 1, p4).toNumber();
        if (index == null || count == null || count < 1 || index < 0 || index >= count) {
            return null;
        }

        return {
            "v" => raw.substring(0, p1),
            "id" => raw.substring(p1 + 1, p2),
            "i" => index,
            "n" => count,
            "chunk" => raw.substring(p4 + 1, raw.length())
        };
    }

    // Partial state lives in Storage, one key per chunk, keyed by message id, so
    // a message that is half-arrived when the app dies is finished after the
    // restart instead of being lost. Chunks are stored by index rather than
    // appended in arrival order: the transport reorders, and a body rebuilt in
    // arrival order parses as garbage without saying why.
    function chunkKey(id, index) as Lang.String {
        return "bus_c_" + id + "_" + index.toString();
    }

    function assemble(id, index, count, text) as Lang.String or Null {
        var metaKey = "bus_m_" + id;
        var now = Time.now().value();

        var meta = App.Storage.getValue(metaKey);
        var fields = meta == null ? [] as Lang.Array<Lang.String> : Text.split(meta, ",");

        if (fields.size() < 2 || fields[0].toNumber() != count) {
            // A different count for the same id is a new message that reused an
            // id, or corrupted state; either way the old pieces are worthless.
            dropPartial(id);
            fields = [count.toString(), now.toString()];
        }

        var arrivedAt = fields[1].toNumber();
        if (arrivedAt == null || now - arrivedAt > PARTIAL_TIMEOUT_S) {
            dropPartial(id);
            fields = [count.toString(), now.toString()];
        }

        var received = [] as Lang.Array<Lang.String>;
        for (var i = 2; i < fields.size(); i++) {
            received.add(fields[i]);
        }

        // A repeat chunk is already stored; counting it again would finish the
        // message with a hole in it.
        for (var i = 0; i < received.size(); i++) {
            if (received[i].toNumber() == index) {
                return null;
            }
        }

        App.Storage.setValue(chunkKey(id, index), text);
        received.add(index.toString());

        var joined = count.toString() + "," + fields[1];
        for (var i = 0; i < received.size(); i++) {
            joined = joined + "," + received[i];
        }
        App.Storage.setValue(metaKey, joined);
        rememberPartial(id);

        if (received.size() < count) {
            return null;
        }

        var out = "";
        for (var i = 0; i < count; i++) {
            var piece = App.Storage.getValue(chunkKey(id, i));
            if (piece == null) {
                return null;
            }
            out = out + piece;
        }

        dropPartial(id);
        return out;
    }

    function rememberPartial(id) as Void {
        var list = App.Storage.getValue(PARTS_KEY);
        var ids = list == null ? [] as Lang.Array<Lang.String> : Text.split(list, ",");

        for (var i = 0; i < ids.size(); i++) {
            if (Text.same(ids[i], id)) {
                return;
            }
        }

        ids.add(id);
        App.Storage.setValue(PARTS_KEY, join(ids));
    }

    function forgetPartial(id) as Void {
        var list = App.Storage.getValue(PARTS_KEY);
        if (list == null) {
            return;
        }

        var ids = Text.split(list, ",");
        var keep = [] as Lang.Array<Lang.String>;
        for (var i = 0; i < ids.size(); i++) {
            if (!Text.same(ids[i], id)) {
                keep.add(ids[i]);
            }
        }
        App.Storage.setValue(PARTS_KEY, join(keep));
    }

    function dropPartial(id) as Void {
        var meta = App.Storage.getValue("bus_m_" + id);
        if (meta != null) {
            var fields = Text.split(meta, ",");
            if (fields.size() > 0) {
                var count = fields[0].toNumber();
                if (count != null) {
                    for (var i = 0; i < count; i++) {
                        App.Storage.deleteValue(chunkKey(id, i));
                    }
                }
            }
        }
        App.Storage.deleteValue("bus_m_" + id);
        forgetPartial(id);
    }

    // Drops every partial message older than the timeout. Called on start, so a
    // dead transfer does not sit in Storage for ever.
    function expirePartials() as Void {
        var list = App.Storage.getValue(PARTS_KEY);
        if (list == null) {
            return;
        }

        var ids = Text.split(list, ",");
        var keep = [] as Lang.Array<Lang.String>;
        var now = Time.now().value();

        for (var i = 0; i < ids.size(); i++) {
            var meta = App.Storage.getValue("bus_m_" + ids[i]);
            var alive = false;
            if (meta != null) {
                var fields = Text.split(meta, ",");
                if (fields.size() >= 2) {
                    var arrivedAt = fields[1].toNumber();
                    alive = arrivedAt != null && now - arrivedAt <= PARTIAL_TIMEOUT_S;
                }
            }
            if (alive) {
                keep.add(ids[i]);
            } else {
                dropPartial(ids[i]);
            }
        }

        App.Storage.setValue(PARTS_KEY, join(keep));
    }

    // ---- dedupe ----------------------------------------------------------

    function seenList() as Lang.Array {
        var stored = App.Storage.getValue(SEEN_KEY);
        if (stored == null || stored.length() == 0) {
            return [] as Lang.Array<Lang.String>;
        }
        return Text.split(stored, ",");
    }

    function seen(id) as Lang.Boolean {
        var ids = seenList();
        for (var i = 0; i < ids.size(); i++) {
            if (Text.same(ids[i], id)) {
                return true;
            }
        }
        return false;
    }

    function remember(id) as Void {
        var ids = seenList();
        ids.add(id);
        while (ids.size() > SEEN_MAX) {
            ids = ids.slice(1, ids.size());
        }
        App.Storage.setValue(SEEN_KEY, join(ids));
    }

    function join(ids) as Lang.String {
        var out = "";
        for (var i = 0; i < ids.size(); i++) {
            if (i > 0) {
                out = out + ",";
            }
            out = out + ids[i];
        }
        return out;
    }

    // ---- dispatch --------------------------------------------------------

    // Returns the kind that was applied, or null when the message could not be
    // applied. Unknown kinds are ignored rather than rejected: a newer phone may
    // say something this watch does not know yet, and that is not an error.
    function apply(kind, payload) as Lang.String or Null {
        if (Text.same(kind, "hello")) {
            sendReady();
            return "hello";
        }
        if (Text.same(kind, "ping")) {
            send("pong", null);
            return "ping";
        }
        if (Text.same(kind, "ack")) {
            var id = payload == null ? null : payload["id"];
            if (id == null) {
                return null;
            }
            StriveApp.acked(id.toString());
            return "ack";
        }
        if (Text.same(kind, "profile") || Text.same(kind, "lib") ||
            Text.same(kind, "plan") || Text.same(kind, "hist") ||
            Text.same(kind, "rec")) {
            if (!Library.apply(kind, payload)) {
                return null;
            }
            return kind;
        }
        note("skip " + kind);
        return null;
    }

    // ---- watch -> phone messages ----------------------------------------

    function sendReady() as Void {
        send("ready", {
            "seq" => nextSeq(),
            "libV" => Library.libVersion(),
            "planV" => Library.planVersion(),
            "pending" => StriveApp.outbox.pending(),
            "bench" => App.Storage.getValue("bench") != null
        });
    }

    function sendStart() as Void {
        send("start", {
            "sid" => Session.sid(),
            "wid" => Library.planWid(),
            "t" => Time.now().value()
        });
    }

    // `i` is the set's index in the session and the phone upserts on it, so a
    // replay converges instead of duplicating. The RIR is the one the user
    // confirmed on the sheet: without it the phone's e1rm is a guess and the
    // next load never moves. -1 means "not recorded", which is what the phone
    // already reads (WatchInbox takes `rir >= 0`), and a set the user left
    // alone must not claim a 2 it never answered.
    function sendSet(index) as Void {
        var entries = Session.entries();
        if (entries.size() == 0) {
            return;
        }
        var entry = entries[entries.size() - 1];
        var rir = entry[:rir];
        send("set", {
            "sid" => Session.sid(),
            "ex" => entry[:id],
            "w" => entry[:weight],
            "reps" => entry[:reps],
            "rir" => rir == null ? -1 : rir,
            "i" => index,
            "rest" => Library.restFor(entry[:id])
        });
    }

    // The whole session, log attached. Upserted on the phone by sid, so a replay
    // after a reconnect converges instead of duplicating the workout.
    //
    // The log rows carry the RIR the sheet recorded. -1 is the phone's "not
    // recorded" and is what a three-field entry from an older build reads back
    // as, so the two shapes converge on the phone instead of one of them
    // inventing a 2.
    function sendEnd(logText) as Void {
        var entries = Session.entries();
        var log = [] as Lang.Array;
        for (var i = 0; i < entries.size(); i++) {
            var rir = entries[i][:rir];
            log.add([entries[i][:id], entries[i][:weight], entries[i][:reps], rir == null ? -1 : rir]);
        }

        send("end", {
            "sid" => Session.sid(),
            "t" => Time.now().value(),
            "dur" => Session.elapsedSeconds(),
            "sets" => entries.size(),
            "vol" => Session.volume(),
            "log" => log
        });
    }

    // ---- diagnostics -----------------------------------------------------

    // One line on the training screen. Without it "nothing happened" and "the
    // message arrived and was wrong" look identical from the wrist.
    function note(text) as Void {
        App.Storage.setValue(DEBUG_KEY, text.length() > 16 ? text.substring(0, 16) : text);
    }

    function shortId(id) as Lang.String {
        return id.length() > 4 ? id.substring(0, 4) : id;
    }
}
