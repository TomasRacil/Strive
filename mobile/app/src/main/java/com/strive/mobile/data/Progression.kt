package com.strive.mobile.data

/**
 * Double progression, the same rule the watch app uses: hold the load until the
 * target sets are completed, then add one step. Kept in one place so the phone
 * and the wrist cannot drift apart.
 */
object Progression {

    const val STEP_KG = 2.5
    const val TARGET_SETS = 3

    fun suggest(entry: ProgressionEntry?, fallbackKg: Double): Double {
        if (entry == null) return fallbackKg
        return if (entry.completed) entry.weightKg + STEP_KG else entry.weightKg
    }
}
