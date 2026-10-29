package com.strive.mobile.data

/**
 * Weights are always stored in kilograms. The display unit is a formatting
 * concern only, so switching kg/lb never rewrites history.
 */
data class Exercise(
    val id: String,
    val name: String,
    val muscle: String,
    val targetReps: Int,
    val restSeconds: Int
)

data class SetEntry(
    val exerciseId: String,
    val exerciseName: String,
    val weightKg: Double,
    val reps: Int,
    val rir: Int?,
    val timestamp: Long
)

data class Session(
    val id: String,
    val startedAt: Long,
    val endedAt: Long?,
    val sets: List<SetEntry>
) {
    val volumeKg: Double get() = sets.sumOf { it.weightKg * it.reps }
    val durationSeconds: Long get() = endedAt?.let { (it - startedAt) / 1000 } ?: 0
}

/** Theme mode, weight unit and language, as the brief specifies. */
data class Settings(
    val theme: String = "system",   // system | dark | light
    val unit: String = "kg",        // kg | lb
    val lang: String = "en"         // en | cs
)

/**
 * Per-exercise progression state: the load last used and whether the target
 * sets were completed at it.
 */
data class ProgressionEntry(
    val weightKg: Double,
    val completed: Boolean
)
