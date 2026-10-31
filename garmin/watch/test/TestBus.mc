using Toybox.Application as App;
using Toybox.Lang;
using Toybox.Test;
using Toybox.Time as Time;

// Unit tests for the framed bus, the outbox and the library it fills.
//
// Everything here runs with Wire in test mode, so nothing claims anything about
// the radio: what is covered is the framing, the reassembly, the acks, the
// dedupe and the fact that a queued message survives a restart.

function busClear() as Void {
    Wire.reset();
    StriveApp.outbox.reset();

    App.Storage.deleteValue("bus_seen");
    App.Storage.deleteValue("bus_seq");
    App.Storage.deleteValue("lib_json");
    App.Storage.deleteValue("lib_v");
    App.Storage.deleteValue("plan_json");
    App.Storage.deleteValue("plan_v");
    App.Storage.deleteValue("plan_wid");
    App.Storage.deleteValue("plan_name");
    App.Storage.deleteValue("rec_json");
    App.Storage.deleteValue("hist_json");
    App.Storage.deleteValue("p_bench_press");
    App.Storage.deleteValue("p_squats");

    Library.Cache.lib = null;
    Library.Cache.libV = -1;
    Library.Cache.plan = null;
    Library.Cache.planV = -1;
}

function busSentCount() as Lang.Number {
    return Wire.sent == null ? 0 : Wire.sent.size();
}

function busAcked(id, count) as Lang.Boolean {
    var wanted = "A|" + id + "|" + count.toString();
    for (var i = 0; i < busSentCount(); i++) {
        if (Text.same(Wire.sent[i], wanted)) {
            return true;
        }
    }
    return false;
}

function busRejected(id, reason) as Lang.Boolean {
    var wanted = "N|" + id + "|" + reason;
    for (var i = 0; i < busSentCount(); i++) {
        if (Text.same(Wire.sent[i], wanted)) {
            return true;
        }
    }
    return false;
}

// A lib body comfortably over one chunk, in the shape the phone sends.
function busLibBody() as Lang.String {
    var items = "";
    for (var i = 0; i < 8; i++) {
        if (i > 0) {
            items = items + ",";
        }
        items = items + "{\"id\":\"ex_" + i.toString() + "\",\"name\":\"Exercise number " + i.toString() +
            "\",\"short\":\"E" + i.toString() + "\",\"mus\":[[\"chest\",0.8]],\"lo\":6,\"hi\":10," +
            "\"rest\":150,\"inc\":2.5,\"minW\":20}";
    }
    return "{\"k\":\"lib\",\"n\":1,\"t\":0,\"p\":{\"v\":4,\"ex\":[" + items + "]}}";
}

// ---- chunking ------------------------------------------------------------

(:test)
function testBusChunkSizes(logger) as Lang.Boolean {
    var body = busLibBody();
    var chunks = Bus.chunk(body);

    logger.debug("body=" + body.length().toString() + " chunks=" + chunks.size().toString());
    if (body.length() <= Bus.CHUNK_UNITS || chunks.size() < 2) {
        return false;
    }

    var joined = "";
    var ok = true;
    for (var i = 0; i < chunks.size(); i++) {
        if (chunks[i].length() > Bus.CHUNK_UNITS) {
            ok = false;
        }
        joined = joined + chunks[i];
    }
    return ok && Text.same(joined, body);
}

// A chunk cut through a surrogate pair arrives as two replacement characters.
// 399 filler units put the 400-unit boundary exactly inside the pair.
(:test)
function testBusChunkKeepsSurrogatePairs(logger) as Lang.Boolean {
    var prefix = "";
    for (var i = 0; i < 399; i++) {
        prefix = prefix + "a";
    }

    var body = prefix + 0xD83D.toChar() + 0xDE00.toChar() + "tail";
    var chunks = Bus.chunk(body);

    logger.debug("units=" + body.length().toString() + " first=" + chunks[0].length().toString());
    return body.length() == 405 &&
        chunks.size() == 2 &&
        chunks[0].length() == 399 &&
        chunks[1].length() == 6 &&
        Text.same(chunks[0] + chunks[1], body);
}

// ---- reassembly ----------------------------------------------------------

(:test)
function testBusReassemblesLongBody(logger) as Lang.Boolean {
    busClear();

    var id = "aaaa0001";
    var body = busLibBody();
    var chunks = Bus.chunk(body);

    var applied = null;
    for (var i = 0; i < chunks.size(); i++) {
        applied = Bus.receive(Bus.envelope(id, i, chunks.size(), chunks[i]));
    }

    var ok = Text.same(applied, "lib") &&
        Library.libVersion() == 4 &&
        Library.exercises().size() == 8 &&
        Text.same(Library.exerciseById("ex_3")["name"], "Exercise number 3") &&
        busAcked(id, chunks.size());

    logger.debug("applied=" + (applied == null ? "null" : applied) + " libV=" + Library.libVersion().toString());
    return ok;
}

// The transport reorders. A body rebuilt in arrival order is garbage that parses
// as garbage, so chunks are stored by index.
(:test)
function testBusReassemblesOutOfOrder(logger) as Lang.Boolean {
    busClear();

    var id = "aaaa0002";
    var body = busLibBody();
    var chunks = Bus.chunk(body);

    var applied = null;
    for (var i = chunks.size() - 1; i >= 0; i--) {
        applied = Bus.receive(Bus.envelope(id, i, chunks.size(), chunks[i]));
    }

    var ok = Text.same(applied, "lib") && Library.exercises().size() == 8;
    logger.debug("out of order applied=" + (applied == null ? "null" : applied));
    return ok;
}

// A repeat chunk must not count twice: the message would complete with a hole in
// the middle and the JSON would not parse.
(:test)
function testBusRepeatChunkDoesNotComplete(logger) as Lang.Boolean {
    busClear();

    var id = "aaaa0003";
    var body = busLibBody();
    var chunks = Bus.chunk(body);

    Bus.receive(Bus.envelope(id, 0, chunks.size(), chunks[0]));
    Bus.receive(Bus.envelope(id, 0, chunks.size(), chunks[0]));
    var applied = Bus.receive(Bus.envelope(id, 1, chunks.size(), chunks[1]));

    logger.debug("repeat chunk applied=" + (applied == null ? "null" : applied));
    return applied == null && !busAcked(id, chunks.size());
}

(:test)
function testBusCzechName(logger) as Lang.Boolean {
    busClear();

    var id = "aaaa0004";
    var body = "{\"k\":\"lib\",\"n\":1,\"t\":0,\"p\":{\"v\":5,\"ex\":[{\"id\":\"squats\"," +
        "\"name\":\"Předklon s činkou\",\"short\":\"Předklon\",\"mus\":[[\"quads\",0.7]]," +
        "\"lo\":6,\"hi\":8,\"rest\":180,\"inc\":2.5,\"minW\":20}]}}";

    var chunks = Bus.chunk(body);
    for (var i = 0; i < chunks.size(); i++) {
        Bus.receive(Bus.envelope(id, i, chunks.size(), chunks[i]));
    }

    var exercise = Library.exerciseById("squats");
    if (exercise == null) {
        logger.debug("no squats");
        return false;
    }

    var name = exercise["name"];
    logger.debug("name len=" + name.length().toString() + " = " + name);
    return Text.same(name, "Předklon s činkou") && name.length() == 17;
}

(:test)
function testBusDuplicateMessageIgnored(logger) as Lang.Boolean {
    busClear();

    var id = "aaaa0005";
    var body = "{\"k\":\"rec\",\"n\":1,\"t\":0,\"p\":{\"at\":0,\"items\":[{\"ex\":\"bench_press\",\"w\":82.5,\"reps\":8,\"sets\":3,\"why\":\"top set\"}]}}";

    var first = Bus.receive(Bus.envelope(id, 0, 1, body));
    var second = Bus.receive(Bus.envelope(id, 0, 1, body));

    var ok = Text.same(first, "rec") && second == null && busAcked(id, 1);
    ok = ok && Plan.weightFor("bench_press") > 82.4 && Plan.weightFor("bench_press") < 82.6;

    logger.debug("first=" + (first == null ? "null" : first) + " second=" + (second == null ? "null" : second));
    return ok;
}

(:test)
function testBusRejectsMalformedJson(logger) as Lang.Boolean {
    busClear();

    var id = "aaaa0006";
    var applied = Bus.receive(Bus.envelope(id, 0, 1, "{\"k\":\"plan\","));

    logger.debug("malformed applied=" + (applied == null ? "null" : applied));
    return applied == null && busRejected(id, "json") && !busAcked(id, 1);
}

(:test)
function testBusRejectsWrongVersion(logger) as Lang.Boolean {
    busClear();

    var id = "aaaa0007";
    var applied = Bus.receive("2|" + id + "|0|1|{\"k\":\"plan\"}");

    logger.debug("wrong version applied=" + (applied == null ? "null" : applied));
    return applied == null && busRejected(id, "ver");
}

(:test)
function testBusIgnoresNonEnvelope(logger) as Lang.Boolean {
    busClear();

    // The old probe strings and anything else without the four separators must
    // be ignored, not thrown on: this runs inside onPhoneAppMessage.
    var a = Bus.receive("L200:xxxxxxxx");
    var b = Bus.receive("ping 1700000000");
    var c = Bus.receive("");
    return a == null && b == null && c == null && busSentCount() == 0;
}

(:test)
function testBusRefusesTooLongBody(logger) as Lang.Boolean {
    busClear();

    var big = "";
    for (var i = 0; i < 700; i++) {
        big = big + "0123456789";
    }

    var accepted = Bus.send("end", {"log" => big});
    logger.debug("too long accepted=" + accepted.toString());
    return !accepted && StriveApp.outbox.pending() == 0;
}

// ---- outbox --------------------------------------------------------------

(:test)
function testOutboxSurvivesRestart(logger) as Lang.Boolean {
    busClear();

    var id = "bbbb0001";
    var box = new Outbox();
    box.add(id, "{\"k\":\"set\",\"n\":1,\"t\":0,\"p\":{}}");

    if (box.pending() != 1 || busSentCount() != 1) {
        logger.debug("not queued: pending=" + box.pending().toString());
        return false;
    }

    // A restart is a new object reading the same Storage.
    var restarted = new Outbox();
    restarted.load();

    logger.debug("after restart pending=" + restarted.pending().toString());
    return restarted.pending() == 1 && restarted.triesFor(id) == 1 && busSentCount() == 2;
}

(:test)
function testOutboxAckRemovesEntry(logger) as Lang.Boolean {
    busClear();

    var id = "bbbb0002";
    var box = new Outbox();
    box.add(id, "{\"k\":\"end\",\"n\":1,\"t\":0,\"p\":{}}");

    if (App.Storage.getValue("ob_" + id) == null) {
        logger.debug("nothing persisted");
        return false;
    }

    box.acked(id);

    var ok = box.pending() == 0 &&
        App.Storage.getValue("ob_" + id) == null &&
        App.Storage.getValue("ob_ids") == null;
    logger.debug("pending after ack=" + box.pending().toString());
    return ok;
}

(:test)
function testOutboxRetryCounter(logger) as Lang.Boolean {
    busClear();

    var id = "bbbb0003";
    var box = new Outbox();
    box.add(id, "{\"k\":\"set\",\"n\":1,\"t\":0,\"p\":{}}");

    if (box.triesFor(id) != 1) {
        logger.debug("tries after first send=" + box.triesFor(id).toString());
        return false;
    }

    // Pretend the first attempt was 4 s ago: the +3 s retry is due.
    var before = busSentCount();
    box.order[0]["at"] = Time.now().value() - 4;
    box.serviceRetries();

    var ok = box.triesFor(id) == 2 && busSentCount() > before && !box.isFailed(id);
    logger.debug("tries after retry=" + box.triesFor(id).toString() + " sent=" + busSentCount().toString());
    return ok;
}

(:test)
function testOutboxGivesUpAfterSchedule(logger) as Lang.Boolean {
    busClear();

    var id = "bbbb0004";
    var box = new Outbox();
    box.add(id, "{\"k\":\"set\",\"n\":1,\"t\":0,\"p\":{}}");

    // Four attempts and then the last window: the message is marked failed and
    // dropped from Storage so the next start does not replay it.
    box.order[0]["tries"] = 4;
    box.order[0]["at"] = Time.now().value() - 13;
    box.serviceRetries();

    var restarted = new Outbox();
    restarted.load();

    var ok = box.isFailed(id) &&
        box.failedCount() == 1 &&
        box.pending() == 0 &&
        restarted.pending() == 0 &&
        App.Storage.getValue("ob_" + id) == null;

    logger.debug("failed=" + box.isFailed(id).toString() + " restarted=" + restarted.pending().toString());
    return ok;
}

// A session logged entirely offline leaves start, its sets and end in the queue,
// in that order, and all of it goes out on the next start.
(:test)
function testOutboxKeepsOrderAcrossRestart(logger) as Lang.Boolean {
    busClear();

    var box = new Outbox();
    box.add("cccc0001", "{\"k\":\"start\",\"n\":1,\"t\":0,\"p\":{}}");
    box.add("cccc0002", "{\"k\":\"set\",\"n\":2,\"t\":0,\"p\":{}}");
    box.add("cccc0003", "{\"k\":\"end\",\"n\":3,\"t\":0,\"p\":{}}");

    var restarted = new Outbox();
    restarted.load();

    var ok = restarted.pending() == 3;
    ok = ok && Text.same(restarted.order[0]["id"], "cccc0001");
    ok = ok && Text.same(restarted.order[1]["id"], "cccc0002");
    ok = ok && Text.same(restarted.order[2]["id"], "cccc0003");

    logger.debug("order size=" + restarted.order.size().toString());
    return ok;
}

// ---- outbox cap and storage guard ----------------------------------------

// A body in the shape Bus writes, with the kind the drop policy reads.
function outboxBody(kind, n) as Lang.String {
    return "{\"k\":\"" + kind + "\",\"n\":" + n.toString() + ",\"t\":0,\"p\":{}}";
}

function outboxId(prefix, n) as Lang.String {
    return prefix + n.toString();
}

// The queue is bounded: an offline week cannot grow it until Storage throws.
// The oldest frame goes first, because it is the one the phone is least likely
// to still want.
(:test)
function testOutboxCapDropsOldest(logger) as Lang.Boolean {
    busClear();

    var box = new Outbox();
    for (var i = 0; i < OutboxLimits.PENDING; i++) {
        box.add(outboxId("ca", i), outboxBody("set", i));
    }

    if (box.pending() != OutboxLimits.PENDING) {
        logger.debug("not filled: pending=" + box.pending().toString());
        return false;
    }

    box.add(outboxId("ca", 99), outboxBody("set", 99));

    var oldest = outboxId("ca", 0);
    var newest = outboxId("ca", 99);
    var ok = box.pending() == OutboxLimits.PENDING &&
        box.droppedCount() == 1 &&
        box.triesFor(oldest) == -1 &&
        box.triesFor(newest) != -1 &&
        App.Storage.getValue("ob_" + oldest) == null &&
        App.Storage.getValue("ob_" + newest) != null;

    logger.debug("cap pending=" + box.pending().toString() + " dropped=" + box.droppedCount().toString());
    return ok;
}

// An `end` closes a session, so it gets in even when the queue is full, and it
// gets in at the cost of a `set`.
(:test)
function testOutboxCapAdmitsEndOverSet(logger) as Lang.Boolean {
    busClear();

    var box = new Outbox();
    for (var i = 0; i < OutboxLimits.PENDING; i++) {
        box.add(outboxId("cb", i), outboxBody("set", i));
    }

    box.add("cbend", outboxBody("end", 100));

    var ok = box.pending() == OutboxLimits.PENDING &&
        box.triesFor("cbend") != -1 &&
        box.triesFor(outboxId("cb", 0)) == -1 &&
        box.droppedCount() == 1 &&
        App.Storage.getValue("ob_cbend") != null &&
        App.Storage.getValue("ob_" + outboxId("cb", 0)) == null;

    logger.debug("end admitted pending=" + box.pending().toString() + " dropped=" + box.droppedCount().toString());
    return ok;
}

// The other half of that rule: with nothing but `end`s left to give up, the
// incoming `set` is the frame that loses. A session whose log arrived without
// its closing frame is worse than a session with one set missing.
(:test)
function testOutboxCapRefusesSetWhenOnlyEndsRemain(logger) as Lang.Boolean {
    busClear();

    var box = new Outbox();
    for (var i = 0; i < OutboxLimits.PENDING; i++) {
        box.add(outboxId("cc", i), outboxBody("end", i));
    }

    box.add("ccset", outboxBody("set", 100));

    var ok = box.pending() == OutboxLimits.PENDING &&
        box.triesFor("ccset") == -1 &&
        box.triesFor(outboxId("cc", 0)) != -1 &&
        box.droppedCount() == 1 &&
        App.Storage.getValue("ob_ccset") == null;

    logger.debug("set refused pending=" + box.pending().toString() + " dropped=" + box.droppedCount().toString());
    return ok;
}

// A store written before the cap existed can come back longer than it.
(:test)
function testOutboxLoadTrimsToCap(logger) as Lang.Boolean {
    busClear();

    var ids = [] as Lang.Array<Lang.String>;
    var extra = 5;
    for (var i = 0; i < OutboxLimits.PENDING + extra; i++) {
        var id = outboxId("cd", i);
        App.Storage.setValue("ob_" + id, Json.write({"b" => outboxBody("set", i), "f" => false, "r" => 0}));
        ids.add(id);
    }
    App.Storage.setValue("ob_ids", Bus.join(ids));

    var box = new Outbox();
    box.load();

    var ok = box.pending() == OutboxLimits.PENDING &&
        box.droppedCount() == extra &&
        box.triesFor(outboxId("cd", 0)) == -1 &&
        box.triesFor(outboxId("cd", extra)) != -1 &&
        App.Storage.getValue("ob_" + outboxId("cd", 0)) == null;

    logger.debug("trimmed to " + box.pending().toString() + " dropped=" + box.droppedCount().toString());
    return ok;
}

// Application.Storage throws when the object store is full. A throw escaping a
// set being logged costs the workout, so every write here is guarded: the queue
// keeps working in memory and the flag tells the UI it will not survive a
// restart. The seam stands in for a full store, which a unit test cannot fill.
(:test)
function testOutboxSurvivesFullStorage(logger) as Lang.Boolean {
    busClear();

    var box = new Outbox();
    box.simulateFull = true;
    box.add("ce000001", outboxBody("set", 1));
    box.add("ce000002", outboxBody("set", 2));

    var ok = box.pending() == 2 &&
        box.storageFailed() &&
        App.Storage.getValue("ob_ce000001") == null &&
        App.Storage.getValue("ob_ids") == null;

    // An ack still empties the queue, and a store that recovers takes writes
    // again without the flag clearing by itself.
    box.acked("ce000001");
    box.simulateFull = false;
    box.add("ce000003", outboxBody("set", 3));

    ok = ok &&
        box.pending() == 2 &&
        box.storageFailed() &&
        App.Storage.getValue("ob_ce000003") != null;

    logger.debug("full storage pending=" + box.pending().toString() + " failed=" + box.storageFailed().toString());
    return ok;
}

// The purge the whole queue exists for: once the phone acks, nothing is left on
// the watch. Checked on a multi-chunk message acked while it was still going out,
// which is the case where a half-written entry could survive.
(:test)
function testOutboxAckLeavesNoKeys(logger) as Lang.Boolean {
    busClear();

    var log = "";
    for (var i = 0; i < 30; i++) {
        if (i > 0) {
            log = log + ",";
        }
        log = log + "[\"bench_press\"," + (60 + i).toString() + ",8,2]";
    }
    var body = "{\"k\":\"end\",\"n\":9,\"t\":0,\"p\":{\"log\":[" + log + "]}}";
    var id = "cf000001";

    var box = new Outbox();
    box.add(id, body);

    var chunks = Bus.chunk(body);
    if (chunks.size() < 2) {
        logger.debug("body did not chunk: size=" + chunks.size().toString());
        return false;
    }

    // Test mode drains the queue in one pump, so the mid-flight state is staged:
    // all but the last chunk out, the ack arriving now.
    box.active = box.order[0];
    box.order[0]["chunks"] = chunks;
    box.order[0]["ci"] = chunks.size() - 1;

    var persistedBefore = App.Storage.getValue("ob_" + id) != null;
    box.acked(id);

    var restarted = new Outbox();
    restarted.load();

    var ok = persistedBefore &&
        chunks.size() > 1 &&
        box.pending() == 0 &&
        box.active == null &&
        App.Storage.getValue("ob_" + id) == null &&
        App.Storage.getValue("ob_ids") == null &&
        restarted.pending() == 0;

    logger.debug("chunks=" + chunks.size().toString() + " pending after ack=" + box.pending().toString());
    return ok;
}

// ---- end to end ----------------------------------------------------------

// A phone-shaped exchange: hello in, ready out, acked; then a plan and a rec,
// which is what actually puts a weight on the watch's screen.
(:test)
function testBusHelloAndPlan(logger) as Lang.Boolean {
    busClear();

    var hello = Bus.receive(Bus.envelope("dddd0001", 0, 1, "{\"k\":\"hello\",\"n\":1,\"t\":0,\"p\":{\"pv\":1,\"app\":\"strive\"}}"));
    var readySent = false;
    for (var i = 0; i < busSentCount(); i++) {
        if (Wire.sent[i].find("ready") != null) {
            readySent = true;
        }
    }

    var planBody = "{\"k\":\"plan\",\"n\":2,\"t\":0,\"p\":{\"v\":2,\"wid\":\"w1\",\"name\":\"Push A\"," +
        "\"items\":[{\"ex\":\"bench_press\",\"sets\":3,\"lo\":6,\"hi\":8,\"rest\":150,\"ss\":0}," +
        "{\"ex\":\"squats\",\"sets\":3,\"lo\":5,\"hi\":6,\"rest\":180,\"ss\":0}]}}";
    var applied = Bus.receive(Bus.envelope("dddd0002", 0, 1, planBody));

    var recBody = "{\"k\":\"rec\",\"n\":3,\"t\":0,\"p\":{\"at\":0,\"items\":[{\"ex\":\"bench_press\",\"w\":85.0,\"reps\":8,\"sets\":3,\"why\":\"top set\"}]}}";
    var recApplied = Bus.receive(Bus.envelope("dddd0003", 0, 1, recBody));

    var ok = Text.same(hello, "hello") && readySent;
    ok = ok && Text.same(applied, "plan") && Library.planItems().size() == 2;
    ok = ok && Text.same(Library.planWid(), "w1");
    ok = ok && Text.same(recApplied, "rec");
    ok = ok && Plan.weightFor("bench_press") > 84.9 && Plan.weightFor("bench_press") < 85.1;

    logger.debug("hello=" + (hello == null ? "null" : hello) + " plan=" + (applied == null ? "null" : applied));
    return ok;
}

// ---- ack frames ----------------------------------------------------------

// The ack is the only thing that takes a message out of the outbox. If the
// watch does not understand "A|id|n" it retries for ever and the queue never
// drains, which is exactly the failure the queue exists to prevent.
(:test)
function testBusAckFrameClearsTheOutbox(logger) as Lang.Boolean {
    busClear();

    var id = "ffff0001";
    StriveApp.outbox.add(id, "{\"k\":\"set\",\"n\":1,\"t\":0,\"p\":{}}");

    if (StriveApp.outbox.pending() != 1) {
        logger.debug("nothing queued");
        return false;
    }

    var applied = Bus.receive("A|" + id + "|1");
    logger.debug("after ack pending=" + StriveApp.outbox.pending().toString());
    return Text.same(applied, "ack") && StriveApp.outbox.pending() == 0;
}

(:test)
function testBusRejectFrameFailsTheMessage(logger) as Lang.Boolean {
    busClear();

    var id = "ffff0002";
    StriveApp.outbox.add(id, "{\"k\":\"set\",\"n\":1,\"t\":0,\"p\":{}}");

    var applied = Bus.receive("N|" + id + "|json");
    logger.debug("after reject failed=" + StriveApp.outbox.isFailed(id).toString());
    return Text.same(applied, "reject") &&
        StriveApp.outbox.isFailed(id) &&
        StriveApp.outbox.pending() == 0;
}

// ---- diagnostics ---------------------------------------------------------

(:test)
function testBusNotesTheLastThingSeen(logger) as Lang.Boolean {
    busClear();

    Bus.receive(Bus.envelope("eeee0001", 0, 1, "{\"k\":\"ping\"}"));
    var note = App.Storage.getValue("ble_dbg");
    logger.debug("note=" + (note == null ? "null" : note.toString()));
    return note != null;
}
