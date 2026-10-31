package com.strive.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Session tonnage with body mass priced in.
 *
 * The old `Session.volumeKg` was external weight times reps, which reports a
 * session of pull-ups as 0 kg. These cases pin the two halves of the fix: body
 * mass counts for a bodyweight movement, and a loaded lift is untouched by it.
 */
class SessionVolumeTest {

    private val library = listOf(
        Exercise(id = "pull_ups", name = "Pull Ups", muscle = "Back", targetReps = 8, restSeconds = 120),
        Exercise(id = "bench_press", name = "Bench Press", muscle = "Chest", targetReps = 8, restSeconds = 150)
    )

    private fun set(exerciseId: String, kg: Double, reps: Int) = SetEntry(
        exerciseId = exerciseId,
        exerciseName = exerciseId,
        weightKg = kg,
        reps = reps,
        rir = 2,
        timestamp = 0L
    )

    private fun session(vararg sets: SetEntry) = Session(
        id = "s1",
        startedAt = 0L,
        endedAt = 3_600_000L,
        sets = sets.toList()
    )

    @Test
    fun pureCalisthenicsCountsTheBodyItMoved() {
        // Ten pull-ups at 80 kg is 800 kg of work, not nothing.
        val volume = session(set("pull_ups", 0.0, 10)).volumeKg(library, bodyKg = 80.0)
        assertEquals(800.0, volume, 0.001)
    }

    @Test
    fun aPlateIsAddedToBodyMass() {
        // 80 kg plus a 2.5 kg plate, eight reps, and an unweighted set of eight.
        val volume = session(
            set("pull_ups", 2.5, 8),
            set("pull_ups", 0.0, 8)
        ).volumeKg(library, bodyKg = 80.0)
        assertEquals(82.5 * 8 + 80.0 * 8, volume, 0.001)
    }

    @Test
    fun aLoadedLiftIgnoresBodyMass() {
        val light = session(set("bench_press", 100.0, 5)).volumeKg(library, bodyKg = 60.0)
        val heavy = session(set("bench_press", 100.0, 5)).volumeKg(library, bodyKg = 110.0)
        assertEquals(500.0, light, 0.001)
        assertEquals(light, heavy, 0.001)
    }

    @Test
    fun aLiftTheLibraryNoLongerHasCountsOnlyItsExternalLoad() {
        // History outlives the library: no fraction left, so body mass cannot be
        // guessed for it.
        val volume = session(set("deleted_lift", 40.0, 10)).volumeKg(library, bodyKg = 80.0)
        assertEquals(400.0, volume, 0.001)
    }
}
