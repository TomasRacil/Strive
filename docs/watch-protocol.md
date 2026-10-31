# Strive watch ⇄ phone protocol, version 1

The only transport is the Garmin companion message bus (`Comm.transmit` from the
watch, `sendMessage` from the phone). Direct BLE is retired; see
`mobile/README.md` for why.

Everything here is measured or enforced by a test. Where a claim is an estimate,
it says so.

## Why a framed protocol

Measured behaviour of the bus, from the probe work that preceded this document:

- Messages sent faster than roughly one per 350-400 ms are silently dropped, and
  `transmit` still reports success. A burst of 18 arrived as 12 with no error.
- The receiving side can be killed mid-flight, so nothing may be assumed
  delivered until it is acknowledged.
- Payload size limits are undocumented. `String` is the only payload type
  proven in both directions, so v1 sends Strings only.

So: one message is a JSON document, split into chunks, reassembled, acknowledged,
and retried. The outbox that holds it survives the app being killed.

## Envelope

Every message on the wire, in both directions, is a single String:

    1|<id>|<i>|<n>|<chunk>

- `1` — protocol version. A receiver that sees anything else replies
  `N|<id>|ver` and ignores the rest.
- `id` — 8 lowercase hex characters, unique per message per sender.
- `i` — chunk index, 0-based.
- `n` — chunk count. `n = 1` means an unfragmented message.
- `chunk` — a slice of the UTF-8 JSON body, **split on UTF-16 code units**, never
  inside a surrogate pair. Maximum 400 code units per chunk. A body longer than
  6000 code units is refused by the sender (`BUS_TOO_LONG`), not truncated.

Reassembly is keyed by `id` and lives in `Application.Storage`, so a message that
is half-arrived when the app dies is completed after the restart rather than
lost. Partial state is dropped after 120 s.

## Acknowledgement

    A|<id>|<n>       whole message received, reassembled, parsed, applied
    N|<id>|<reason>  rejected: ver | json | len | apply

A sender retries an unacknowledged message at +3 s, +6 s and +12 s, then marks it
failed and moves on. Failed outbound messages are kept in the outbox with a
`failed` flag for the session and dropped on the next app start, so a poisoned
message cannot wedge the queue forever.

Both directions use the same envelope, the same chunking and the same ack rules.
An `ack` message is itself an ordinary message and is never itself acked
(`n = 1`, kind `ack`), which is what stops an ack storm.

## Body

    {"k": "<kind>", "n": <senderSeq>, "t": <epochSeconds>, "p": { ... }}

- `k` — message kind, the table below.
- `n` — monotonic per-sender counter. Used only for ordering and for detecting a
  lost tail; the receiver does not require it to be contiguous.
- `t` — sender's wall clock, seconds. Advisory: the watch and the phone clocks
  are not synchronised, so a receiver stores its own arrival time and uses `t`
  only to stamp history.
- `p` — kind-specific payload. Absent for kinds with no payload.

The receiver keeps the ids of the last 32 applied messages and drops a repeat
without applying it. Applying the same message twice must be harmless anyway —
that is a property of the kinds below, not a substitute for the dedupe.

## Phone → watch

| kind      | payload | meaning |
|-----------|---------|---------|
| `hello`   | `{pv, app}` | phone is alive and speaking v1. Watch answers `ready`. |
| `profile` | `{units, lang, bodyKg, maxHr, restHr, age, incUp, incLo}` | settings the watch needs to compute offline. |
| `lib`     | `{v, ex:[{id, name, short, mus:[[m,share],...], lo, hi, rest, inc, minW}]}` | full exercise library snapshot, replaces what the watch has. |
| `plan`    | `{v, wid, name, items:[{ex, sets, lo, hi, rest, ss}]}` | the workout to run now. Empty `items` clears it. |
| `rec`     | `{at, items:[{ex, w, reps, sets, why}]}` | phone-computed recommendation, used while connected. |
| `hist`    | `{ex:{<id>:[[w,reps,rir,ageDays],...]}}` | last 3 sets per exercise, up to 40 exercises, so the watch can recommend offline. |
| `ping`    | — | keepalive; watch answers `pong`. |

`lib`, `plan` and `hist` are snapshots: applying one replaces the previous one
wholesale. A version number that is not newer than the stored one is still
applied (the phone is authoritative) but the watch does not re-render unless
something changed.

## Watch → phone

| kind     | payload | meaning |
|----------|---------|---------|
| `ready`  | `{seq, libV, planV, pending, bench}` | watch is alive, here is what it holds. |
| `start`  | `{sid, wid, t}` | a session began. `sid` is the watch's session id. |
| `set`    | `{sid, ex, w, reps, rir, i, rest}` | one set banked. `i` is its index in the session. |
| `end`    | `{sid, t, dur, sets, vol, log:[[ex,w,reps,rir],...]}` | session finished, full log attached. |
| `bench`  | `{t, bodyKg, items:[{ex, reps, rir}]}` | calibration result. |
| `ack`    | `{id}` | acknowledges a phone message. |
| `pong`   | — | answer to `ping`. |

`set` and `end` are the only messages whose loss costs the user work, and they
are the reason the outbox is persistent. Both are upserts on the phone keyed by
(`sid`, `ex`, `i`) and (`sid`), so a replay after a reconnect converges instead
of duplicating.

## Offline behaviour

The watch never waits for the phone. Every message it emits is written to the
outbox before `transmit` is called, and the outbox is drained on app start, on
`onShow`, and whenever a `hello` or `pong` arrives. A session done entirely
offline produces a `start`, its `set`s and an `end` in that order, delivered
minutes or days later.

The outbox holds at most 64 pending frames (`OutboxLimits.PENDING`). A session is
one `start`, its `set`s and one `end`, so the cap clears the longest realistic
workout with room for the next one to begin. When the queue is full the oldest
frame is dropped and counted — with one exception: an `end` is never dropped to
make room for a `set`, and when nothing but `end`s is left the incoming `set` is
the frame that goes. A drop is named in `ble_dbg` and counted by
`droppedCount()`.

A full object store does not cost a set. Every write in the outbox is guarded, so
a refused write leaves the frame in memory for the rest of the session and raises
`storageFailed()`, which the UI reads to say the queue will not survive a
restart.

The phone does the same in reverse: `lib`, `plan` and `hist` are stored, so a
reconnect re-sends them without the user asking.

## What the watch must never assume

- That a `transmit` callback means delivery. Only an `A|` does.
- That a message arrives whole. `n > 1` is the normal case for `lib`.
- That the phone is there. Recommendation, rest timing and set logging all work
  from watch-local state alone.
