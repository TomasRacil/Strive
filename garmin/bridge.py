#!/usr/bin/env python3
"""Strive <-> Garmin Connect bridge.

Pushes Strive routines to Garmin Connect as structured strength workouts (they
then show up on the watch in the native strength app), and pulls completed
strength activities back as Strive sessions you can import.

This uses Garmin Connect's own web API through the `garminconnect` package, so
it works with a normal Garmin account: no Connect IQ development, no partner
program, no store review.

    python bridge.py push routines.json --schedule 2026-11-02
    python bridge.py pull --days 14 --out garmin_sessions.json
    python bridge.py push routines.json --dry-run

Credentials: GARMIN_EMAIL / GARMIN_PASSWORD, or a cached token store created on
first login (GARMIN_TOKENSTORE, default ~/.strive_garmin_tokens).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import NoReturn

import convert

DEFAULT_TOKENSTORE = "~/.strive_garmin_tokens"


def die(message: str) -> NoReturn:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: str):
    try:
        return json.loads(Path(path).expanduser().read_text(encoding="utf-8"))
    except FileNotFoundError:
        die(f"file not found: {path}")
    except json.JSONDecodeError as exc:
        die(f"{path} is not valid JSON: {exc}")


def make_client(args):
    try:
        from garminconnect import Garmin
    except ImportError:
        die("garminconnect is not installed. Run: pip install -r garmin/requirements.txt")

    tokenstore = Path(
        args.tokenstore or os.getenv("GARMIN_TOKENSTORE") or DEFAULT_TOKENSTORE
    ).expanduser()

    email = args.email or os.getenv("GARMIN_EMAIL")
    password = args.password or os.getenv("GARMIN_PASSWORD")

    if not tokenstore.exists() and not (email and password):
        die(
            "no cached session and no credentials.\n"
            "Set GARMIN_EMAIL and GARMIN_PASSWORD for the first run "
            f"(a session is then cached in {tokenstore})."
        )

    client = Garmin(
        email=email,
        password=password,
        prompt_mfa=lambda: input("Garmin MFA code: ").strip(),
    )

    try:
        client.login(str(tokenstore))
    except Exception as exc:  # noqa: BLE001 - surfaced verbatim to the user
        die(f"Garmin login failed: {exc}")

    try:
        tokenstore.parent.mkdir(parents=True, exist_ok=True)
        client.garth.dump(str(tokenstore))
    except Exception:  # noqa: BLE001 - caching is best-effort
        pass

    return client


def cmd_push(args) -> int:
    payload = load_json(args.file)
    workouts = convert.strive_export_to_garmin_bundle(payload, name_prefix=args.prefix)

    if not workouts:
        die("no routines found in the file")

    if args.dry_run:
        print(json.dumps(workouts, indent=2))
        return 0

    client = make_client(args)
    schedule_day = date.fromisoformat(args.schedule) if args.schedule else None

    for index, workout in enumerate(workouts):
        try:
            result = client.upload_workout(workout)
        except Exception as exc:  # noqa: BLE001
            print(f"  FAILED  {workout['workoutName']}: {exc}", file=sys.stderr)
            continue

        workout_id = (result or {}).get("workoutId")
        print(f"  pushed  {workout['workoutName']}  (workoutId={workout_id})")

        if schedule_day and workout_id:
            day = schedule_day + timedelta(days=index)
            try:
                client.schedule_workout(workout_id, day.isoformat())
                print(f"          scheduled for {day.isoformat()}")
            except Exception as exc:  # noqa: BLE001
                print(f"          schedule failed: {exc}", file=sys.stderr)

        if args.push_to_device and workout_id:
            try:
                client.push_workout_to_device(workout_id)
                print("          pushed to device")
            except Exception as exc:  # noqa: BLE001
                print(f"          device push failed: {exc}", file=sys.stderr)

    return 0


def cmd_pull(args) -> int:
    client = make_client(args)
    end = date.today()
    start = end - timedelta(days=args.days)

    # Garmin rejects an activity sub type in this filter ("Activity type cannot
    # be an activity sub type"), so ask for everything in the window and filter
    # here instead. Also version-proof against their taxonomy changing.
    try:
        activities = client.get_activities_by_date(start.isoformat(), end.isoformat())
    except Exception as exc:  # noqa: BLE001
        die(f"could not list activities: {exc}")

    activities = [
        activity
        for activity in (activities or [])
        if ((activity.get("activityType") or {}).get("typeKey") or "") == "strength_training"
    ]

    sessions = []
    for activity in activities or []:
        activity_id = activity.get("activityId")
        detail = dict(activity)
        try:
            detail["exerciseSets"] = (
                client.get_activity_exercise_sets(activity_id).get("exerciseSets", [])
            )
        except Exception as exc:  # noqa: BLE001
            print(f"  warning: no exercise sets for {activity_id}: {exc}", file=sys.stderr)
            continue

        session = convert.garmin_activity_to_strive(detail)
        if session["sets"]:
            sessions.append(session)

    sessions.sort(key=lambda s: s.get("timestamp") or "", reverse=True)

    output = {"version": "1.2", "source": "garmin", "sessions": sessions}
    out_path = Path(args.out).expanduser()
    out_path.write_text(json.dumps(output, indent=2), encoding="utf-8")

    print(f"  {len(sessions)} session(s), {sum(len(s['sets']) for s in sessions)} set(s) -> {out_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Strive <-> Garmin Connect bridge")
    parser.add_argument("--email", help="Garmin email (or GARMIN_EMAIL)")
    parser.add_argument("--password", help="Garmin password (or GARMIN_PASSWORD)")
    parser.add_argument("--tokenstore", help=f"cached session path (default {DEFAULT_TOKENSTORE})")

    sub = parser.add_subparsers(dest="command", required=True)

    push = sub.add_parser("push", help="upload routines as Garmin strength workouts")
    push.add_argument("file", help="Strive routines export (or a full backup file)")
    push.add_argument("--prefix", default="", help="prefix added to each workout name")
    push.add_argument("--schedule", help="schedule the first workout on this date (YYYY-MM-DD)")
    push.add_argument("--push-to-device", action="store_true", help="also push to the paired watch")
    push.add_argument("--dry-run", action="store_true", help="print the payload, touch nothing")
    push.set_defaults(func=cmd_push)

    pull = sub.add_parser("pull", help="download strength activities as Strive sessions")
    pull.add_argument("--days", type=int, default=14, help="how far back to look (default 14)")
    pull.add_argument("--out", default="garmin_sessions.json", help="output file")
    pull.set_defaults(func=cmd_pull)

    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
