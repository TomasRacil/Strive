"""Tests for the pure converter. Run: garmin/.venv/Scripts/python -m unittest garmin/test_convert.py"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import convert  # noqa: E402


ROUTINE = {
    "id": "1",
    "name": "Push Day A",
    "exercises": [
        {"id": "bench_press", "name": "Bench Press", "targetSets": 4, "targetReps": 8, "restSeconds": 120},
        {"id": "overhead_press", "name": "Overhead Press", "targetSets": 3, "targetReps": 10, "restSeconds": 90},
    ],
}


class ResolveExerciseTests(unittest.TestCase):
    def test_known_exercises_map_exactly(self):
        self.assertEqual(convert.resolve_garmin_exercise("Bench Press"), ("BENCH_PRESS", "BENCH_PRESS"))
        self.assertEqual(convert.resolve_garmin_exercise("Barbell Squats"), ("SQUAT", "BARBELL_BACK_SQUAT"))
        self.assertEqual(convert.resolve_garmin_exercise("Pull-ups"), ("PULL_UP", "PULL_UP"))
        self.assertEqual(convert.resolve_garmin_exercise("Deadlift"), ("DEADLIFT", "DEADLIFT"))

    def test_matching_is_case_and_accent_insensitive(self):
        self.assertEqual(convert.resolve_garmin_exercise("BENCH PRESS"), ("BENCH_PRESS", "BENCH_PRESS"))
        self.assertEqual(convert.resolve_garmin_exercise("bench-press"), ("BENCH_PRESS", "BENCH_PRESS"))

    def test_unknown_exercise_falls_back_to_keyword_category(self):
        category, exercise = convert.resolve_garmin_exercise("Zercher Squat Variation")
        self.assertEqual(category, "SQUAT")
        self.assertEqual(exercise, "")

    def test_completely_unknown_exercise_still_produces_a_category(self):
        category, _ = convert.resolve_garmin_exercise("Interpretive Dance")
        self.assertEqual(category, convert.FALLBACK_CATEGORY)


class RoutineConversionTests(unittest.TestCase):
    def setUp(self):
        self.workout = convert.strive_routine_to_garmin(ROUTINE)

    def test_top_level_shape(self):
        self.assertEqual(self.workout["workoutName"], "Push Day A")
        self.assertEqual(self.workout["sportType"]["sportTypeKey"], "strength_training")
        self.assertEqual(self.workout["sportType"]["sportTypeId"], 5)
        self.assertEqual(len(self.workout["workoutSegments"]), 1)

    def test_one_repeat_group_per_exercise(self):
        steps = self.workout["workoutSegments"][0]["workoutSteps"]
        self.assertEqual(len(steps), 2)
        self.assertTrue(all(step["type"] == "RepeatGroupDTO" for step in steps))

    def test_step_orders_are_unique_and_advance_by_three(self):
        steps = self.workout["workoutSegments"][0]["workoutSteps"]
        self.assertEqual([step["stepOrder"] for step in steps], [1, 4])
        self.assertEqual([inner["stepOrder"] for inner in steps[0]["workoutSteps"]], [2, 3])
        self.assertEqual([inner["stepOrder"] for inner in steps[1]["workoutSteps"]], [5, 6])

    def test_sets_and_reps_are_carried_over(self):
        group = self.workout["workoutSegments"][0]["workoutSteps"][0]
        self.assertEqual(group["numberOfIterations"], 4)
        exercise_step = group["workoutSteps"][0]
        self.assertEqual(exercise_step["endConditionValue"], 8.0)
        self.assertEqual(exercise_step["endCondition"]["conditionTypeKey"], "reps")

    def test_rest_is_a_timed_step(self):
        rest = self.workout["workoutSegments"][0]["workoutSteps"][0]["workoutSteps"][1]
        self.assertEqual(rest["stepType"]["stepTypeKey"], "rest")
        self.assertEqual(rest["endConditionValue"], 120.0)

    def test_defaults_are_applied_when_targets_are_missing(self):
        workout = convert.strive_routine_to_garmin({"name": "Bare", "exercises": [{"name": "Deadlift"}]})
        group = workout["workoutSegments"][0]["workoutSteps"][0]
        self.assertEqual(group["numberOfIterations"], convert.DEFAULT_SETS)
        self.assertEqual(group["workoutSteps"][0]["endConditionValue"], float(convert.DEFAULT_REPS))
        self.assertEqual(group["workoutSteps"][1]["endConditionValue"], convert.DEFAULT_REST_SECONDS)

    def test_weight_is_exported_in_grams(self):
        workout = convert.strive_routine_to_garmin({
            "name": "Weighted",
            "exercises": [{"name": "Bench Press", "targetSets": 3, "targetReps": 5, "weight": 80}],
        })
        step = workout["workoutSegments"][0]["workoutSteps"][0]["workoutSteps"][0]
        self.assertEqual(step["weightValue"], 80000.0)
        self.assertEqual(step["weightUnit"]["unitKey"], "kilogram")

    def test_explicit_garmin_override_wins(self):
        workout = convert.strive_routine_to_garmin({
            "name": "Override",
            "exercises": [{
                "name": "My Weird Press",
                "targetSets": 3,
                "garmin": {"category": "BENCH_PRESS", "exercise": "CLOSE_GRIP_BARBELL_BENCH_PRESS"},
            }],
        })
        step = workout["workoutSegments"][0]["workoutSteps"][0]["workoutSteps"][0]
        self.assertEqual(step["category"], "BENCH_PRESS")
        self.assertEqual(step["exerciseName"], "CLOSE_GRIP_BARBELL_BENCH_PRESS")

    def test_empty_routine_produces_no_steps(self):
        workout = convert.strive_routine_to_garmin({"name": "Empty", "exercises": []})
        self.assertEqual(workout["workoutSegments"][0]["workoutSteps"], [])


class BundleTests(unittest.TestCase):
    def test_accepts_a_backup_file_with_routines(self):
        bundle = convert.strive_export_to_garmin_bundle({"version": "1.1", "routines": [ROUTINE]})
        self.assertEqual(len(bundle), 1)
        self.assertEqual(bundle[0]["workoutName"], "Push Day A")

    def test_accepts_a_bare_routine_list(self):
        bundle = convert.strive_export_to_garmin_bundle([ROUTINE, ROUTINE])
        self.assertEqual(len(bundle), 2)

    def test_accepts_routines_stored_as_a_json_string(self):
        bundle = convert.strive_export_to_garmin_bundle({"routines": json.dumps([ROUTINE])})
        self.assertEqual(len(bundle), 1)


class ActivityConversionTests(unittest.TestCase):
    def activity(self, **overrides):
        base = {
            "activityId": 987,
            "activityName": "Gym",
            "startTimeLocal": "2026-10-28 18:04:00",
            "duration": 3720,
            "exerciseSets": [
                {
                    "setType": "ACTIVE",
                    "repetitionCount": 8,
                    "weight": 60000,
                    "startTime": "2026-10-28 18:06:00",
                    "exercises": [{"category": "BENCH_PRESS", "name": "BARBELL_BENCH_PRESS"}],
                },
                {"setType": "REST", "duration": 90},
                {
                    "setType": "ACTIVE",
                    "repetitionCount": 10,
                    "weight": 40000,
                    "exercises": [{"category": "ROW", "name": "FACE_PULL"}],
                },
            ],
        }
        base.update(overrides)
        return base

    def test_active_sets_are_imported_and_rests_skipped(self):
        session = convert.garmin_activity_to_strive(self.activity())
        self.assertEqual(len(session["sets"]), 2)

    def test_weights_are_converted_from_grams(self):
        session = convert.garmin_activity_to_strive(self.activity())
        self.assertEqual(session["sets"][0]["weight"], 60.0)
        self.assertEqual(session["sets"][1]["weight"], 40.0)

    def test_exercise_names_are_humanised_and_slugged(self):
        session = convert.garmin_activity_to_strive(self.activity())
        self.assertEqual(session["sets"][0]["exerciseName"], "Barbell Bench Press")
        self.assertEqual(session["sets"][0]["exerciseId"], "garmin_barbell_bench_press")

    def test_session_metadata_is_preserved(self):
        session = convert.garmin_activity_to_strive(self.activity())
        self.assertEqual(session["id"], "garmin_987")
        self.assertEqual(session["duration"], 3720)
        self.assertEqual(session["source"], "garmin")
        self.assertEqual(session["timestamp"], "2026-10-28 18:04:00")

    def test_activity_without_sets_yields_an_empty_session(self):
        session = convert.garmin_activity_to_strive({"activityId": 1, "exerciseSets": []})
        self.assertEqual(session["sets"], [])


class LibraryParityTests(unittest.TestCase):
    """If garminconnect is installed, our JSON must match what it builds."""

    def setUp(self):
        try:
            from garminconnect.workout import (  # noqa: F401
                StrengthWorkout,
                WorkoutSegment,
                create_strength_set,
            )
        except Exception:
            self.skipTest("garminconnect not installed")

    def test_single_exercise_matches_library_output(self):
        from garminconnect.workout import StrengthWorkout, WorkoutSegment, create_strength_set

        expected = StrengthWorkout(
            workoutName="Push Day A",
            estimatedDurationInSecs=convert.strive_routine_to_garmin(ROUTINE)["estimatedDurationInSecs"],
            workoutSegments=[
                WorkoutSegment(
                    segmentOrder=1,
                    sportType={"sportTypeId": 5, "sportTypeKey": "strength_training"},
                    workoutSteps=[create_strength_set("BENCH_PRESS", 1, 4, 8, 120, exercise_name="BENCH_PRESS")],
                )
            ],
        ).model_dump()

        actual = convert.strive_routine_to_garmin({**ROUTINE, "exercises": ROUTINE["exercises"][:1]})

        self.assertEqual(actual["workoutSegments"][0]["workoutSteps"], expected["workoutSegments"][0]["workoutSteps"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
