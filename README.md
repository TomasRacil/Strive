# Strive - Premium Fitness Training Engine

Strive is a local-first training app for lifters who want goal-oriented coaching,
precise telemetry, and a real bridge to their Garmin watch.

Runs as a web app, installs as a PWA on Android and iOS (Add to Home Screen),
and works offline.

## Quick start

```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # production bundle + service worker
npm test         # unit tests for the engine and stats
npm run lint
```

## Features

### Core experience
- **Responsive design** — glassmorphism UI, bottom sheets on mobile, fluid desktop layout.
- **Interactive dashboard** — streak, total workouts, weekly volume per muscle group, recent activity with tonnage and duration.
- **Library management** — custom exercises, muscle-group weighting, execution-form tracking.

### Intelligence engine
- **Goal-oriented progression** — next load and reps derived from your last performance and RIR (Build Muscle / Build Strength / Maintain).
- **History-based auto-fill** — inputs seed from what you actually lifted last time for that exercise, falling back to a saved template.
- **Strength test** — progressive Big-5 battery calibrated from bodyweight and RIR feedback.
- **1RM estimation** — Brzycki formula, clamped to the range where it is valid.

### Session telemetry
- **Dual timers** — rest timer counts down to your programmed rest and beeps/vibrates when it is up; session timer runs independently.
- **PR detection** — every logged set is compared against your best estimated 1RM for that lift, flagged in the log, and announced when you beat it.
- **Crash-safe sessions** — the in-flight workout is written to disk on every set, so a locked phone or a killed tab resumes where you left off.
- **Live logging** — session log grouped by exercise, newest first.
- **Routine targets** — sets, reps and rest per exercise, used both in-session and for Garmin export.

### Progress
- **Per-exercise trend** — estimated 1RM per session as a sparkline, with change since your first session (Library → chart icon).
- **Weekly volume per muscle group** — tonnage split by each exercise's engagement weighting.

### Data and privacy
- **Local-first** — everything lives in `localStorage`. No account, no server.
- **Versioned export/import** — JSON backup with migration handling.

### Garmin
- **Push plans** — routines become structured Garmin strength workouts on the watch.
- **Recommended loads** — the plan carries the weight the engine recommends for each lift, derived from your last session and RIR. Garmin's strength app displays a planned weight but never chooses it; this does.
- **Pull sessions** — watch-recorded sets (weight and reps) import back into history.

See [garmin/README.md](garmin/README.md) for setup and the trade-offs against a
custom Connect IQ watch app.

## Roadmap
- [ ] Per-muscle weekly volume targets and deload detection
- [ ] Optional cloud sync for cross-device history
- [ ] Connect IQ watch app, if the native strength UI proves too limiting

## Deployment

Pushing to `master` deploys automatically via `.github/workflows/deploy.yml`
(GitHub Actions → Pages). The workflow runs lint, tests and the build before
publishing, so a broken commit cannot go live.

Pages for this repo is configured with `build_type: workflow`, which means the
site is published from an Actions artifact. Pushing a build to a `gh-pages`
branch does nothing here — an earlier `npm run deploy` script did exactly that
and silently had no effect.

## Architecture

```
src/
  pages/       Dashboard, Training, Exercises, Profile
  components/  modals, timer, selectors
  hooks/       useExercises, useHistory, useRoutines (localStorage-backed)
  utils/       engine.js (progression math), stats.js (streak, volume)
garmin/
  convert.py   pure Strive <-> Garmin JSON mapping
  bridge.py    CLI: login, push workouts, pull activities
  test_convert.py
tests/         node:test unit tests
```

`src/utils/` is intentionally React-free so the logic can be unit tested in Node.
