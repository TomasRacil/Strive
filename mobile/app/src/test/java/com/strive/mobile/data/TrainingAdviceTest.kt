package com.strive.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The seam between the app's session history and the engine: which rows are fed
 * in, what the screen ends up showing, and the order the picker offers lifts in.
 *
 * The engine's own maths is covered by [EngineTest] against the shared vectors;
 * this is about mapping history onto it correctly, which is where a wiring bug
 * would hide. Nothing here reads the wall clock: every timestamp is fixed.
 */
class TrainingAdviceTest {

    private val day = 24L * 60 * 60 * 1000
    private val now = 1_760_000_000_000L

    private val bench = Seed.exercises.first { it.id == "bench_press" }
    private val squats = Seed.exercises.first { it.id == "squats" }
    private val pullUps = Seed.exercises.first { it.id == "pull_ups" }

    private fun set(exerciseId: String, name: String, kg: Double, reps: Int, rir: Int?, at: Long) =
        SetEntry(
            exerciseId = exerciseId,
            exerciseName = name,
            weightKg = kg,
            reps = reps,
            rir = rir,
            timestamp = at
        )

    private fun session(id: String, startedAt: Long, vararg sets: SetEntry) =
        Session(id = id, startedAt = startedAt, endedAt = startedAt + 3_600_000, sets = sets.toList())

    private fun benchSet(kg: Double, reps: Int, rir: Int?, at: Long) =
        set("bench_press", "Bench Press", kg, reps, rir, at)

    // ---- suggested weight ------------------------------------------------

    @Test
    fun topOfTheRangeWithReserveRaisesTheLoad() {
        val at = now - day
        val last = session(
            "s1", at,
            benchSet(80.0, 10, 2, at),
            benchSet(80.0, 10, 2, at),
            benchSet(80.0, 10, 2, at)
        )

        val advice = TrainingAdvice.advice(bench, listOf(last), 20.0, 80.0)

        // Ten reps at two in reserve is the top of the 6-10 range: one 2.5 kg
        // step, and the target drops back to the bottom of the range to earn it.
        assertEquals(82.5, advice.weightKg, 0.001)
        assertEquals(6, advice.targetReps)
    }

    @Test
    fun failureBelowTheRangeLowersTheLoad() {
        val at = now - day
        val last = session("s1", at, benchSet(80.0, 4, 0, at))

        val advice = TrainingAdvice.advice(bench, listOf(last), 20.0, 80.0)

        // Four reps at failure is under the range: deload a step, and rebuild
        // from the bottom of the range rather than straight back to the top.
        assertEquals(77.5, advice.weightKg, 0.001)
        assertEquals(6, advice.targetReps)
    }

    @Test
    fun historyIsTheMostRecentSessionNotTheBestEver() {
        val old = session("s0", now - 10 * day, benchSet(100.0, 10, 3, now - 10 * day))
        val recent = session("s1", now - day, benchSet(70.0, 8, 3, now - day))

        // List order must not matter: the engine reads what happened last, so a
        // heavy month-old session cannot drag today's suggestion up.
        val advice = TrainingAdvice.advice(bench, listOf(old, recent), 20.0, 80.0)

        assertEquals(70.0, advice.weightKg, 0.001)
        assertEquals(10, advice.targetReps)
    }

    @Test
    fun aLiftWithNoHistoryStartsAtTheSeed() {
        val advice = TrainingAdvice.advice(bench, emptyList(), 20.0, 80.0)

        assertEquals(20.0, advice.weightKg, 0.001)
        assertEquals(10, advice.targetReps)
    }

    @Test
    fun bodyweightLiftIsPricedWithBodyMassAndDoesNotComeBackAsZero() {
        val at = now - day
        // The bodyweight set is the better one - 12 reps with three in reserve -
        // but it only outranks the 5 kg set once body mass is priced in. Without
        // that, weight 0 scores e1rm 0, the 5 kg set wins, and the advice holds
        // an external load that was never lifted.
        val last = session(
            "s1", at,
            set("pull_ups", "Pull-ups", 0.0, 12, 3, at),
            set("pull_ups", "Pull-ups", 5.0, 4, 0, at)
        )

        val advice = TrainingAdvice.advice(pullUps, listOf(last), 20.0, 80.0)

        assertEquals(2.5, advice.weightKg, 0.001)
        assertTrue("a bodyweight lift must not suggest 0 kg", advice.weightKg > 0.0)
    }

    // ---- set count -------------------------------------------------------

    @Test
    fun aLiftNeverTrainedStaysAtThreeSets() {
        assertEquals(3, TrainingAdvice.targetSets(emptyList(), Seed.exercises, bench, now))
    }

    @Test
    fun aLightWeekForTheMuscleAddsAFourthSet() {
        val at = now - day
        val last = session("s1", at, benchSet(80.0, 8, 2, at), benchSet(80.0, 8, 2, at))

        // Three effective sets of chest this week is under the engine's eight.
        assertEquals(4, TrainingAdvice.targetSets(listOf(last), Seed.exercises, bench, now))
    }

    @Test
    fun aSpentMuscleHoldsAtThreeSets() {
        val at = now - day
        val hard = Array(10) { benchSet(80.0, 8, 0, at) }
        val last = session("s1", at, *hard)

        assertEquals(3, TrainingAdvice.targetSets(listOf(last), Seed.exercises, bench, now))
    }

    // ---- ordering --------------------------------------------------------

    @Test
    fun freshMuscleRanksAboveASpentOne() {
        val at = now - 3_600_000
        // Six hard sets of bench today: the chest is worked, the legs are not.
        val today = session("s1", at, *Array(6) { benchSet(80.0, 8, 0, at) })

        val order = TrainingAdvice.order(Seed.exercises, listOf(today), now)
        val squatIndex = order.indexOfFirst { it.id == squats.id }
        val benchIndex = order.indexOfFirst { it.id == bench.id }

        assertTrue("both lifts must be offered", squatIndex >= 0 && benchIndex >= 0)
        assertTrue(
            "squats ($squatIndex) should be offered before the worked chest ($benchIndex)",
            squatIndex < benchIndex
        )
    }

    @Test
    fun aLiftTheEngineDropsForRecoveryIsStillOfferedLast() {
        val at = now - 3_600_000
        // Twelve hard sets: the chest cannot do another hard set, so rank drops
        // the bench. Hiding it from the picker would be a regression, so it goes
        // to the back instead.
        val today = session("s1", at, *Array(12) { benchSet(80.0, 8, 0, at) })

        val order = TrainingAdvice.order(Seed.exercises, listOf(today), now)

        assertEquals(Seed.exercises.size, order.size)
        assertEquals(bench.id, order.last().id)
    }

    @Test
    fun anEmptyLibraryIsNotAnError() {
        assertTrue(TrainingAdvice.order(emptyList(), emptyList(), now).isEmpty())
    }
}
