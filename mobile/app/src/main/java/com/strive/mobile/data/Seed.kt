package com.strive.mobile.data

/**
 * Seed library. Mirrors the six lifts the watch app ships with, so the phone and
 * the wrist agree on ids and rest durations.
 */
object Seed {
    val exercises: List<Exercise> = listOf(
        Exercise("bench_press", "Bench Press", "Chest", 8, 150),
        Exercise("squats", "Squats", "Legs", 6, 180),
        Exercise("deadlift", "Deadlift", "Back", 5, 180),
        Exercise("overhead_press", "Overhead Press", "Shoulders", 8, 120),
        Exercise("pull_ups", "Pull-ups", "Back", 8, 120),
        Exercise("bicep_curls", "Curls", "Arms", 10, 90)
    )
}
