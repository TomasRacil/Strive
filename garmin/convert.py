"""Pure conversion between Strive JSON and Garmin Connect workout JSON.

Deliberately free of network calls and of the ``garminconnect`` import so the
mapping can be unit tested without an account. ``bridge.py`` is the thin layer
that logs in and talks to Garmin.

Two directions:

  strive_routine_to_garmin(routine)  ->  a strength workout Garmin Connect accepts
  garmin_activity_to_strive(activity) -> a Strive session you can import

Garmin strength workouts are modelled as one RepeatGroupDTO per exercise:
``sets`` iterations of a reps-terminated step followed by a timed rest step.
Step orders must be unique across the segment and advance by 3 per exercise.
"""

from __future__ import annotations

import re
import unicodedata

SPORT_STRENGTH = {
    "sportTypeId": 5,
    "sportTypeKey": "strength_training",
    "displayOrder": 5,
}

KILOGRAM_UNIT = {"unitId": 8, "unitKey": "kilogram", "factor": 1000.0}

# Defaults applied when a routine does not carry per-exercise targets.
DEFAULT_REPS = 8
DEFAULT_SETS = 3
DEFAULT_REST_SECONDS = 90.0

# Curated mappings for the exercises that ship with Strive. Anything not listed
# falls through to keyword heuristics, and finally to a generic category, so an
# unknown lift still produces a usable workout instead of an error.
EXERCISE_MAP = {
    "bench press": ("BENCH_PRESS", "BENCH_PRESS"),
    "barbell bench press": ("BENCH_PRESS", "BARBELL_BENCH_PRESS"),
    "incline bench press": ("BENCH_PRESS", "INCLINE_BARBELL_BENCH_PRESS"),
    "dumbbell bench press": ("BENCH_PRESS", "DUMBBELL_BENCH_PRESS"),
    "barbell squats": ("SQUAT", "BARBELL_BACK_SQUAT"),
    "squats": ("SQUAT", "BARBELL_BACK_SQUAT"),
    "squat": ("SQUAT", "BARBELL_BACK_SQUAT"),
    "front squat": ("SQUAT", "BARBELL_FRONT_SQUAT"),
    "deadlift": ("DEADLIFT", "DEADLIFT"),
    "romanian deadlift": ("DEADLIFT", "ROMANIAN_DEADLIFT"),
    "overhead press": ("SHOULDER_PRESS", "OVERHEAD_BARBELL_PRESS"),
    "military press": ("SHOULDER_PRESS", "MILITARY_PRESS"),
    "shoulder press": ("SHOULDER_PRESS", "SHOULDER_PRESS"),
    "pull-ups": ("PULL_UP", "PULL_UP"),
    "pull ups": ("PULL_UP", "PULL_UP"),
    "pull-up": ("PULL_UP", "PULL_UP"),
    "chin-up": ("PULL_UP", "CHIN_UP"),
    "lat pulldown": ("PULL_UP", "LAT_PULLDOWN"),
    "lat pull-down": ("PULL_UP", "LAT_PULLDOWN"),
    "weighted dips": ("TRICEPS_EXTENSION", "BODY_WEIGHT_DIP"),
    "dips": ("TRICEPS_EXTENSION", "BODY_WEIGHT_DIP"),
    "bicep curls": ("CURL", "DUMBBELL_BICEPS_CURL"),
    "dumbbell curls": ("CURL", "DUMBBELL_BICEPS_CURL"),
    "barbell curl": ("CURL", "BARBELL_BICEPS_CURL"),
    "hammer curl": ("CURL", "DUMBBELL_HAMMER_CURL"),
    "bulgarian split squats": ("LUNGE", "BARBELL_BULGARIAN_SPLIT_SQUAT"),
    "bulgarian split squat": ("LUNGE", "BARBELL_BULGARIAN_SPLIT_SQUAT"),
    "lunge": ("LUNGE", "BARBELL_LUNGE"),
    "leg press": ("SQUAT", "LEG_PRESS"),
    "leg curl": ("LEG_CURL", "LEG_CURL"),
    "calf raise": ("CALF_RAISE", "CALF_RAISES"),
    "bent over row": ("ROW", "BARBELL_BENT_OVER_ROW"),
    "barbell row": ("ROW", "BARBELL_BENT_OVER_ROW"),
    "face pull": ("ROW", "FACE_PULL"),
    "cable fly": ("FLYE", "CABLE_CHEST_FLY"),
    "plank": ("PLANK", "PLANK"),
    "crunch": ("CRUNCH", "CRUNCH"),
    "sit-up": ("SIT_UP", "SIT_UP"),
    "farmers carry": ("CARRY", "FARMERS_CARRY"),
}

# Keyword -> category, evaluated in order. First match wins.
KEYWORD_CATEGORIES = [
    ("bench", "BENCH_PRESS"),
    ("chest press", "BENCH_PRESS"),
    ("fly", "FLYE"),
    ("squat", "SQUAT"),
    ("deadlift", "DEADLIFT"),
    ("rdl", "DEADLIFT"),
    ("pull-up", "PULL_UP"),
    ("pull up", "PULL_UP"),
    ("chin", "PULL_UP"),
    ("pulldown", "PULL_UP"),
    ("pull-down", "PULL_UP"),
    ("row", "ROW"),
    ("curl", "CURL"),
    ("dip", "TRICEPS_EXTENSION"),
    ("triceps", "TRICEPS_EXTENSION"),
    ("pressdown", "TRICEPS_EXTENSION"),
    ("skull", "TRICEPS_EXTENSION"),
    ("shoulder press", "SHOULDER_PRESS"),
    ("overhead press", "SHOULDER_PRESS"),
    ("military", "SHOULDER_PRESS"),
    ("press", "SHOULDER_PRESS"),
    ("lunge", "LUNGE"),
    ("split squat", "LUNGE"),
    ("calf", "CALF_RAISE"),
    ("leg curl", "LEG_CURL"),
    ("hamstring", "LEG_CURL"),
    ("raise", "LATERAL_RAISE"),
    ("plank", "PLANK"),
    ("crunch", "CRUNCH"),
    ("sit-up", "SIT_UP"),
    ("ab ", "CORE"),
    ("carry", "CARRY"),
]

FALLBACK_CATEGORY = "TOTAL_BODY"


def normalise(name: str) -> str:
    """Lowercase, strip accents and collapse separators so lookups are stable."""
    text = unicodedata.normalize("NFKD", str(name or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.replace("-", " ").replace("_", " ")
    return re.sub(r"\s+", " ", text).strip().lower()


def resolve_garmin_exercise(name: str) -> tuple[str, str]:
    """Return ``(category, exerciseName)`` for a Strive exercise name.

    An exercise may carry an explicit override: ``{"garmin": {"category":
    "BENCH_PRESS", "exercise": "BARBELL_BENCH_PRESS"}}``.
    """
    key = normalise(name)
    if key in EXERCISE_MAP:
        return EXERCISE_MAP[key]

    # Singular/plural tolerance: "barbell squat" -> "barbell squats".
    if key.endswith("s") and key[:-1] in EXERCISE_MAP:
        return EXERCISE_MAP[key[:-1]]
    if key + "s" in EXERCISE_MAP:
        return EXERCISE_MAP[key + "s"]

    for keyword, category in KEYWORD_CATEGORIES:
        if keyword in key:
            return category, ""

    return FALLBACK_CATEGORY, ""


def slugify(value: str) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_") or "exercise"


def _exercise_step(
    category: str,
    exercise_name: str,
    reps: int,
    step_order: int,
    weight_kg: float | None,
    description: str | None,
) -> dict:
    step = {
        "type": "ExecutableStepDTO",
        "stepOrder": step_order,
        "stepType": {"stepTypeId": 3, "stepTypeKey": "interval", "displayOrder": 3},
        "endCondition": {
            "conditionTypeId": 10,
            "conditionTypeKey": "reps",
            "displayOrder": 10,
            "displayable": True,
        },
        "endConditionValue": float(reps),
        "targetType": {
            "workoutTargetTypeId": 1,
            "workoutTargetTypeKey": "no.target",
            "displayOrder": 1,
        },
        "targetValueOne": None,
        "targetValueTwo": None,
        "zoneNumber": None,
        "secondaryTargetType": None,
        "secondaryTargetValueOne": None,
        "secondaryTargetValueTwo": None,
        "secondaryZoneNumber": None,
        "strokeType": None,
        "equipmentType": None,
        "childStepId": None,
        "description": description,
        "category": category,
        "exerciseName": exercise_name or "",
    }
    if weight_kg:
        # Garmin stores weight in grams with a kilogram unit descriptor.
        step["weightValue"] = float(weight_kg) * 1000.0
        step["weightUnit"] = dict(KILOGRAM_UNIT)
    return step


def _rest_step(rest_seconds: float, step_order: int) -> dict:
    return {
        "type": "ExecutableStepDTO",
        "stepOrder": step_order,
        "stepType": {"stepTypeId": 5, "stepTypeKey": "rest", "displayOrder": 5},
        "endCondition": {
            "conditionTypeId": 2,
            "conditionTypeKey": "time",
            "displayOrder": 2,
            "displayable": True,
        },
        "endConditionValue": float(rest_seconds),
        "targetType": {
            "workoutTargetTypeId": 1,
            "workoutTargetTypeKey": "no.target",
            "displayOrder": 1,
        },
        "targetValueOne": None,
        "targetValueTwo": None,
        "zoneNumber": None,
        "secondaryTargetType": None,
        "secondaryTargetValueOne": None,
        "secondaryTargetValueTwo": None,
        "secondaryZoneNumber": None,
        "strokeType": None,
        "equipmentType": None,
        "childStepId": None,
        "description": None,
    }


def _repeat_group(
    category: str,
    exercise_name: str,
    sets: int,
    reps: int,
    rest_seconds: float,
    step_order: int,
    weight_kg: float | None = None,
    description: str | None = None,
) -> dict:
    return {
        "type": "RepeatGroupDTO",
        "stepOrder": step_order,
        "stepType": {"stepTypeId": 6, "stepTypeKey": "repeat", "displayOrder": 6},
        "numberOfIterations": int(sets),
        "workoutSteps": [
            _exercise_step(category, exercise_name, reps, step_order + 1, weight_kg, description),
            _rest_step(rest_seconds, step_order + 2),
        ],
        "endCondition": {
            "conditionTypeId": 7,
            "conditionTypeKey": "iterations",
            "displayOrder": 7,
            "displayable": False,
        },
        "endConditionValue": float(sets),
        "childStepId": None,
        "smartRepeat": False,
        "skipLastRestStep": None,
    }


def strive_routine_to_garmin(routine: dict, *, name_prefix: str = "") -> dict:
    """Convert one Strive routine into a Garmin strength workout dict."""
    name = (routine.get("name") or "Strive Routine").strip()
    workout_name = f"{name_prefix}{name}"[:60]

    steps: list[dict] = []
    order = 1
    estimated_seconds = 0.0

    for exercise in routine.get("exercises") or []:
        display_name = exercise.get("name") or exercise.get("exerciseName") or "Exercise"

        override = exercise.get("garmin") or {}
        if override.get("category"):
            category = override["category"]
            exercise_name = override.get("exercise", "")
        else:
            category, exercise_name = resolve_garmin_exercise(display_name)

        sets = int(exercise.get("targetSets") or DEFAULT_SETS)
        reps = int(exercise.get("targetReps") or DEFAULT_REPS)
        rest = float(exercise.get("restSeconds") or DEFAULT_REST_SECONDS)
        weight = exercise.get("weight")

        steps.append(_repeat_group(
            category,
            exercise_name,
            sets,
            reps,
            rest,
            order,
            weight_kg=weight,
            description=exercise.get("notes") or None,
        ))
        order += 3
        estimated_seconds += sets * (reps * 3 + rest)

    return {
        "workoutName": workout_name,
        "sportType": dict(SPORT_STRENGTH),
        "estimatedDurationInSecs": int(round(estimated_seconds)),
        "workoutSegments": [
            {
                "segmentOrder": 1,
                "sportType": {
                    "sportTypeId": SPORT_STRENGTH["sportTypeId"],
                    "sportTypeKey": SPORT_STRENGTH["sportTypeKey"],
                },
                "workoutSteps": steps,
            }
        ],
        "author": {},
        "description": routine.get("description") or None,
    }


def strive_export_to_garmin_bundle(payload, *, name_prefix: str = "") -> list[dict]:
    """Accept a backup file, a bare routine list, or a routines JSON string."""
    if isinstance(payload, str):
        import json

        payload = json.loads(payload or "[]")

    routines = payload.get("routines") if isinstance(payload, dict) else payload
    if routines is None:
        routines = []
    if isinstance(routines, str):
        import json

        routines = json.loads(routines or "[]")
    return [strive_routine_to_garmin(r, name_prefix=name_prefix) for r in routines or []]


def _weight_to_kg(raw) -> float | None:
    """Garmin reports exercise-set weight in grams; accept kg-shaped input too."""
    if raw in (None, "", 0):
        return None
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None
    # A 500 kg single set does not happen; a 500 g set does not either. This
    # boundary is the only sane way to tell the two conventions apart.
    return round(value / 1000.0, 2) if value >= 500 else round(value, 2)


def garmin_activity_to_strive(activity: dict, *, rir: int | None = None) -> dict:
    """Convert a Garmin activity (with exerciseSets) into an importable session."""
    sets = []
    exercise_sets = activity.get("exerciseSets") or activity.get("exercise_sets") or []

    for entry in exercise_sets:
        set_type = str(entry.get("setType") or entry.get("set_type") or "ACTIVE").upper()
        if set_type != "ACTIVE":
            continue  # skip REST / UNKNOWN markers

        reps = entry.get("repetitionCount") or entry.get("reps")
        if not reps:
            continue

        exercises = entry.get("exercises") or []
        first = exercises[0] if exercises else {}
        category = first.get("category") or first.get("name") or "UNKNOWN"
        display = first.get("name") or category

        sets.append({
            "exerciseId": f"garmin_{slugify(display)}",
            "exerciseName": _humanise(display),
            "weight": _weight_to_kg(entry.get("weight")) or 0,
            "reps": int(reps),
            "rir": rir,
            "form": "Garmin",
            "timestamp": entry.get("startTime") or activity.get("startTimeLocal"),
        })

    return {
        "id": f"garmin_{activity.get('activityId', 'unknown')}",
        "timestamp": activity.get("startTimeLocal") or activity.get("startTimeGMT"),
        "duration": int(activity.get("duration") or activity.get("elapsedDuration") or 0),
        "goal": "build_muscle",
        "routineName": activity.get("activityName"),
        "source": "garmin",
        "sets": sets,
        "version": "1.1",
    }


def _humanise(garmin_name: str) -> str:
    """BARBELL_BACK_SQUAT -> Barbell Back Squat."""
    return " ".join(part.capitalize() for part in str(garmin_name).split("_") if part)
