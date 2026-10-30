package com.strive.mobile.ui

import com.strive.mobile.data.Session
import com.strive.mobile.data.SetEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The history card's "did I get better?" line is pure maths, so it is tested
 * here rather than through the UI: which lift is compared, what counts as the
 * previous session, and the neutral cases that must not crash or invent a delta.
 */
class StatsProgressTest {

    private fun set(exerciseId: String, name: String, kg: Double, reps: Int = 5) = SetEntry(
        exerciseId = exerciseId,
        exerciseName = name,
        weightKg = kg,
        reps = reps,
        rir = null,
        timestamp = 0L
    )

    private fun session(id: String, startedAt: Long, vararg sets: SetEntry) = Session(
        id = id,
        startedAt = startedAt,
        endedAt = startedAt + 3_600_000,
        sets = sets.toList()
    )

    @Test
    fun mainLiftIsTheOneWithMostSets() {
        val workout = session(
            "s1", 1_000L,
            set("bench", "Bench Press", 80.0),
            set("bench", "Bench Press", 80.0),
            set("bench", "Bench Press", 80.0),
            set("curl", "Curls", 15.0)
        )

        assertEquals("bench", Stats.mainLiftId(workout))
    }

    @Test
    fun setCountBreaksTiesBeforeVolume() {
        // Two sets each: the heavier lift carries the session.
        val workout = session(
            "s1", 1_000L,
            set("squat", "Squats", 120.0, reps = 5),
            set("squat", "Squats", 120.0, reps = 5),
            set("calf", "Calf Raise", 20.0, reps = 5),
            set("calf", "Calf Raise", 20.0, reps = 5)
        )

        assertEquals("squat", Stats.mainLiftId(workout))
    }

    @Test
    fun comparesAgainstTheLastSessionThatTrainedTheSameLift() {
        val oldest = session("s1", 1_000L, set("bench", "Bench Press", 75.0))
        val other = session("s2", 2_000L, set("squat", "Squats", 140.0))
        val newest = session(
            "s3", 3_000L,
            set("bench", "Bench Press", 80.0),
            set("bench", "Bench Press", 77.5)
        )

        val progress = Stats.liftProgress(newest, listOf(newest, other, oldest))!!

        assertEquals("bench", progress.exerciseId)
        assertEquals(80.0, progress.bestKg, 0.001)
        assertEquals(75.0, progress.previousBestKg!!, 0.001)
        assertEquals(5.0, progress.deltaKg!!, 0.001)
        // The squat session never trained bench, so it is not in the trend.
        assertEquals(listOf(75.0, 80.0), progress.history)
    }

    @Test
    fun reportsARegressionAsANegativeDelta() {
        val before = session("s1", 1_000L, set("bench", "Bench Press", 90.0))
        val after = session("s2", 2_000L, set("bench", "Bench Press", 85.0))

        val progress = Stats.liftProgress(after, listOf(after, before))!!

        assertEquals(-5.0, progress.deltaKg!!, 0.001)
    }

    @Test
    fun firstTimeOnALiftHasNoDelta() {
        val workout = session("s1", 1_000L, set("bench", "Bench Press", 80.0))

        val progress = Stats.liftProgress(workout, listOf(workout))!!

        assertNull(progress.previousBestKg)
        assertNull(progress.deltaKg)
        assertEquals(listOf(80.0), progress.history)
    }

    @Test
    fun anEmptySessionHasNothingToCompare() {
        val empty = Session(id = "s1", startedAt = 1_000L, endedAt = null, sets = emptyList())

        assertNull(Stats.mainLiftId(empty))
        assertNull(Stats.liftProgress(empty, listOf(empty)))
    }

    @Test
    fun aSessionNeverComparesAgainstItself() {
        // Same list, same session: there is no earlier copy, so no delta.
        val workout = session("s1", 1_000L, set("bench", "Bench Press", 80.0))

        val progress = Stats.liftProgress(workout, listOf(workout))!!

        assertNull(progress.deltaKg)
    }

    @Test
    fun topLiftsAreOrderedByContributionAndCapped() {
        val workout = session(
            "s1", 1_000L,
            set("curl", "Curls", 15.0),
            set("bench", "Bench Press", 80.0),
            set("bench", "Bench Press", 80.0),
            set("bench", "Bench Press", 80.0),
            set("squat", "Squats", 120.0),
            set("squat", "Squats", 120.0),
            set("row", "Row", 60.0)
        )

        assertEquals(
            listOf("Bench Press", "Squats", "Row"),
            Stats.topLifts(workout, limit = 3)
        )
        assertTrue(Stats.topLifts(workout, limit = 2).size == 2)
    }

    @Test
    fun historyIsCappedToTheMostRecentSessions() {
        val sessions = (0 until 12).map { index ->
            session("s$index", 1_000L + index * 1_000L, set("bench", "Bench Press", 60.0 + index))
        }

        val progress = Stats.liftProgress(sessions.last(), sessions, historyLimit = 8)!!

        assertEquals(8, progress.history.size)
        assertEquals(71.0, progress.history.last(), 0.001)
        assertEquals(64.0, progress.history.first(), 0.001)
    }
}
