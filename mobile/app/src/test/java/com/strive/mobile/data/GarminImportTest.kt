package com.strive.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The import path has to match what garmin/bridge.py actually writes: `weight`
 * rather than `weightKg`, and ISO-8601 timestamps rather than epoch millis.
 */
class GarminImportTest {

    private val library = listOf(
        Exercise("bench_press", "Bench Press", "Chest", 8, 150),
        Exercise("squats", "Squats", "Legs", 6, 180),
        Exercise("overhead_press", "Overhead Press", "Shoulders", 8, 120),
        Exercise("pull_ups", "Pull-ups", "Back", 8, 120),
        Exercise("bicep_curls", "Curls", "Arms", 10, 90)
    )

    private val sample = """
        {
          "version": "1.2",
          "source": "garmin",
          "sessions": [
            {
              "id": "garmin_987",
              "timestamp": "2026-10-28T18:30:00.0",
              "duration": 3600,
              "goal": "build_muscle",
              "source": "garmin",
              "sets": [
                {
                  "exerciseId": "garmin_bench_press",
                  "exerciseName": "Bench Press",
                  "weight": 80.0,
                  "reps": 8,
                  "rir": null,
                  "timestamp": "2026-10-28T18:35:00.0"
                },
                {
                  "exerciseId": "garmin_unknown_thing",
                  "exerciseName": "Cable Fly",
                  "weight": 25.0,
                  "reps": 12,
                  "rir": null,
                  "timestamp": "2026-10-28T18:45:00.0"
                }
              ]
            }
          ]
        }
    """.trimIndent()

    @Test
    fun parsesASessionAndItsSets() {
        val result = GarminImport.parse(sample, library)
        val sessions = result.sessions

        assertEquals(1, sessions.size)
        val session = sessions.first()

        assertEquals("garmin_987", session.id)
        assertEquals(2, session.sets.size)
        assertTrue("startedAt should be a real timestamp", session.startedAt > 0L)
        assertNotNull("duration should become an end time", session.endedAt)
    }

    @Test
    fun mapsGarminExerciseNamesOntoTheLibrary() {
        val result = GarminImport.parse(sample, library)
        val sets = result.sessions.first().sets

        // Known lift: rewritten to our own id so stats and progression apply.
        assertEquals("bench_press", sets[0].exerciseId)
        assertEquals("Bench Press", sets[0].exerciseName)
        assertEquals(80.0, sets[0].weightKg, 0.001)
        assertEquals(8, sets[0].reps)

        // Unknown lift: a library entry is created with inferred muscles rather
        // than leaving the set orphaned.
        assertEquals("Cable Fly", sets[1].exerciseName)
        assertEquals(25.0, sets[1].weightKg, 0.001)
        assertTrue(
            "Cable Fly should get a muscle mapping",
            result.newExercises.any { it.name == "Cable Fly" && it.primary.isNotEmpty() }
        )
    }

    @Test
    fun matchesGarminStyleNamesToShortLibraryNames() {
        // The real-world case: long equipment-prefixed names against short ones.
        assertEquals("squats", ExerciseMatcher.match("Barbell Back Squat", library)?.id)
        assertEquals("bench_press", ExerciseMatcher.match("Barbell Bench Press", library)?.id)
        assertEquals("overhead_press", ExerciseMatcher.match("Military Press", library)?.id)
        assertEquals("pull_ups", ExerciseMatcher.match("Pull Up", library)?.id)
        assertEquals("bicep_curls", ExerciseMatcher.match("Standing Ez Bar Biceps Curl", library)?.id)
    }

    @Test
    fun keepsPressIntactWhenNormalising() {
        // "press" must not be de-pluralised to "pres".
        assertEquals("bench press", ExerciseMatcher.normalize("Barbell Bench Press"))
        assertEquals("squat", ExerciseMatcher.normalize("Barbell Back Squats"))
    }

    @Test
    fun rejectsFilesThatAreNotExports() {
        try {
            GarminImport.parse("{\"unrelated\": true}", library)
            throw AssertionError("expected ImportException")
        } catch (expected: GarminImport.ImportException) {
            assertTrue(expected.message!!.contains("sessions"))
        }
    }

    @Test
    fun skipsSetsWithNoReps() {
        val json = """
            {"sessions":[{"id":"g","timestamp":"2026-10-28T18:30:00.0","sets":[
              {"exerciseName":"Bench Press","weight":80,"reps":0}
            ]}]}
        """.trimIndent()

        assertEquals(0, GarminImport.parse(json, library).sessions.size)
    }
}
