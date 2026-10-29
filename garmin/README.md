# Garmin bridge

Connects Strive to a Garmin watch **without** Connect IQ development, a partner
program, or store review. It uses Garmin Connect's own web API through the
`garminconnect` Python package:

- **push** — your Strive routines become structured Garmin strength workouts.
  They appear on the watch inside the native strength app, with sets, reps and
  rest, so the watch tells you what to do next.
- **pull** — strength activities recorded on the watch come back as Strive
  sessions, including per-set weight and reps.

## Why this and not a custom watch app

| Approach | Works today | Cost | Notes |
|---|---|---|---|
| **This bridge** (Garmin Connect API) | yes | an afternoon | Uses the built-in strength app. No watch-side install. |
| Connect IQ watch app (Monkey C) | yes, sideloaded | 2-4 weeks | Needs the Connect IQ SDK, a developer key, and a companion phone app for sync. Only worth it if you need a UI Garmin doesn't have. |
| Garmin Health API | no | business partner approval | Enterprise only. |
| FIT/TCX import | yes | minutes | Manual export from Garmin Connect, loses set structure. |

## Setup

```bash
py -3.12 -m venv garmin/.venv
garmin/.venv/Scripts/python.exe -m pip install -r garmin/requirements.txt
```

First run needs credentials once; a session token is cached afterwards.

```bash
# bash / macOS / Linux
export GARMIN_EMAIL="you@example.com"
export GARMIN_PASSWORD="..."

# PowerShell
$env:GARMIN_EMAIL="you@example.com"
$env:GARMIN_PASSWORD="..."
```

The token store defaults to `~/.strive_garmin_tokens` (override with
`GARMIN_TOKENSTORE`). Delete that file to force a fresh login.

## Push a plan

1. In the app: **Profile → Garmin → Routines for Garmin**. This downloads
   `strive_garmin_routines.json`.
2. Push it:

```bash
garmin/.venv/Scripts/python.exe garmin/bridge.py push strive_garmin_routines.json
```

Options:

```bash
--schedule 2026-11-02   # schedule the first workout on that date, then daily
--prefix "Strive "      # prefix workout names to keep them grouped
--push-to-device        # also push straight to the paired watch
--dry-run               # print the Garmin JSON, touch nothing
```

After a push, open Garmin Connect → Training → Workouts, or find it on the
watch under **Training → Workouts**. On watch models with the strength profile
it runs as a guided set-by-set workout with rest timers.

## Pull finished sessions

```bash
garmin/.venv/Scripts/python.exe garmin/bridge.py pull --days 14 --out garmin_sessions.json
```

Then in the app: **Profile → Garmin → Import Garmin Sessions**.

Imports are idempotent — the session id is the Garmin activity id, so pulling
the same window twice does not duplicate anything.

## What the mapping does

- Exercise names map through a curated table (`convert.EXERCISE_MAP`), then a
  keyword heuristic, then a generic category. An unknown lift still produces a
  usable workout instead of failing.
- Override any exercise explicitly by adding a `garmin` object to it:
  `{"name": "Close-grip Bench", "garmin": {"category": "BENCH_PRESS", "exercise": "CLOSE_GRIP_BARBELL_BENCH_PRESS"}}`.
- Weight is exported in grams with a kilogram unit descriptor, which is what
  Garmin's workout API expects.
- On import, a Garmin exercise that is not in your library is kept under its
  Garmin name, so history never shows a blank row.

## Tests

The converter is pure — no network, no credentials:

```bash
garmin/.venv/Scripts/python.exe -m unittest garmin/test_convert.py -v
```

One test asserts the generated JSON is byte-identical to what `garminconnect`
itself builds, so a library upgrade that changes the schema fails loudly.

## Limits worth knowing

- `garminconnect` is an unofficial client. Garmin can change the private API at
  any time; if push/pull starts failing after a library upgrade, that is why.
- Garmin's exercise-set weight field is not documented. Values >= 500 are read
  as grams, below that as kilograms. Check the first import before trusting it.
- Scheduled workouts appear in Garmin Connect's calendar, which the watch syncs
  on its next phone sync — not instantly.
