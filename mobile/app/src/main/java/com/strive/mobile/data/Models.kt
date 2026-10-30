package com.strive.mobile.data

/**
 * One way of performing a lift. Same movement family, different setup - a
 * sumo deadlift trains the same lift with different emphasis, and the user can
 * add their own (their gym's cable stack, a machine variant, and so on).
 */
data class Variation(
    val id: String,
    val name: String,
    val note: String = "",
    val targetReps: Int? = null,
    val restSeconds: Int? = null
)

/**
 * Weights are always stored in kilograms. The display unit is a formatting
 * concern only, so switching kg/lb never rewrites history.
 *
 * `primary` and `secondary` map muscle id -> load share (0..1) relative to the
 * hardest-working muscle in the movement. See [Muscles] for the taxonomy.
 */
data class Exercise(
    val id: String,
    val name: String,
    val muscle: String,
    val targetReps: Int,
    val restSeconds: Int,
    val description: String = "",
    val primary: Map<String, Double> = emptyMap(),
    val secondary: Map<String, Double> = emptyMap(),
    val variations: List<Variation> = emptyList()
) {
    /**
     * Total load per muscle: primary at face value, secondary discounted to 60%,
     * because a stabiliser is not doing the same work as the prime mover.
     */
    fun loadByMuscle(): Map<String, Double> {
        val out = mutableMapOf<String, Double>()
        primary.forEach { (muscle, weight) -> out[muscle] = (out[muscle] ?: 0.0) + weight }
        secondary.forEach { (muscle, weight) -> out[muscle] = (out[muscle] ?: 0.0) + weight * 0.6 }
        return out
    }

    /** Highest load in the movement, used to scale the body map. */
    fun peakLoad(): Double = loadByMuscle().values.maxOrNull() ?: 1.0
}

data class SetEntry(
    val exerciseId: String,
    val exerciseName: String,
    val weightKg: Double,
    val reps: Int,
    val rir: Int?,
    val timestamp: Long,
    /** How long the set took, from "start set" to "end set". 0 if unknown. */
    val durationSeconds: Int = 0
)

/** A planned training session: a name and the lifts it contains, in order. */
data class Routine(
    val id: String,
    val name: String,
    val exerciseIds: List<String>
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
