package com.strive.mobile.data

/**
 * Maps Garmin's exercise names onto library lifts, and invents sensible library
 * entries for the ones that do not exist yet.
 *
 * Garmin's names are long and equipment-prefixed ("Barbell Back Squat",
 * "Standing Ez Bar Biceps Curl"), while a library tends to use short names
 * ("Squats", "Curls"). Exact matching misses almost everything, which silently
 * orphans imported sets - and orphaned sets contribute nothing to volume,
 * progression or the daily suggestion.
 */
object ExerciseMatcher {

    private val noise = setOf(
        "barbell", "dumbbell", "dumbbells", "cable", "machine", "ez", "bar", "ezbar",
        "standing", "seated", "weighted", "assisted", "smith", "back", "flat", "trap"
        // Deliberately NOT stripped: incline, decline, close, wide, reverse.
        // They name a different lift ("incline bench press" is not "bench press").
    )

    /** Lowercase, drop equipment and position words, then de-pluralise. */
    fun normalize(raw: String): String {
        val cleaned = raw.lowercase().replace("-", " ").replace("_", " ")
        val tokens = cleaned.split(" ")
            .map { it.trim() }
            .filter { it.isNotEmpty() && it !in noise }

        return tokens.joinToString(" ") { token ->
            // "squats" -> "squat", but "press" must stay "press", not "pres".
            if (token.length > 3 && token.endsWith("s") && !token.endsWith("ss")) {
                token.dropLast(1)
            } else {
                token
            }
        }
    }

    /** Names that mean the same lift under a different label. */
    private val synonyms = mapOf(
        "military press" to "overhead_press",
        "shoulder press" to "overhead_press",
        "ohp" to "overhead_press",
        "overhead press" to "overhead_press",
        "bench press" to "bench_press",
        "chest press" to "bench_press",
        "squat" to "squats",
        "pull up" to "pull_ups",
        "pullup" to "pull_ups",
        "chin up" to "pull_ups",
        "deadlift" to "deadlift",
        "curl" to "bicep_curls",
        "bicep curl" to "bicep_curls",
        "biceps curl" to "bicep_curls"
    )

    fun match(rawName: String, library: List<Exercise>): Exercise? {
        if (rawName.isBlank()) return null
        val key = normalize(rawName)

        synonyms[key]?.let { id ->
            library.firstOrNull { it.id == id }?.let { return it }
        }

        library.firstOrNull { normalize(it.name) == key }?.let { return it }

        // "incline dumbbell bench press" -> "bench press" once noise is stripped,
        // but be conservative: only accept a full-token containment.
        return library.firstOrNull { exercise ->
            val name = normalize(exercise.name)
            name.isNotEmpty() && (key.endsWith(name) || key.startsWith("$name ") || name.startsWith("$key "))
        }
    }

    /**
     * Builds a library entry for a lift we have never seen, with muscle mapping
     * inferred from its name. Returns null when the name gives nothing away -
     * better an unmapped entry than a confidently wrong one.
     */
    fun infer(rawName: String): Exercise? {
        val name = rawName.trim()
        if (name.isBlank() || name.equals("unknown", ignoreCase = true)) return null

        val n = name.lowercase()
        fun has(vararg keys: String) = keys.any { n.contains(it) }

        return when {
            has("incline") && has("press") ->
                new(name, "Chest",
                    primary = mapOf("pectoralis_major" to 1.0),
                    secondary = mapOf("anterior_deltoid" to 0.7, "triceps_lateral" to 0.5))

            has("decline") && has("press") ->
                new(name, "Chest",
                    primary = mapOf("pectoralis_major" to 1.0),
                    secondary = mapOf("triceps_lateral" to 0.6, "anterior_deltoid" to 0.3))

            has("close grip") && has("press") ->
                new(name, "Arms",
                    primary = mapOf("triceps_lateral" to 1.0, "triceps_long" to 0.8),
                    secondary = mapOf("pectoralis_major" to 0.5, "anterior_deltoid" to 0.4))

            has("reverse fly", "rear delt", "reverse pec") ->
                new(name, "Shoulders",
                    primary = mapOf("posterior_deltoid" to 1.0),
                    secondary = mapOf("rhomboids" to 0.7, "trapezius_mid" to 0.5))

            has("pressdown", "skull crusher", "triceps extension", "overhead extension") ->
                new(name, "Arms",
                    primary = mapOf("triceps_lateral" to 1.0, "triceps_long" to 0.8),
                    secondary = mapOf("triceps_medial" to 0.6))

            has("face pull") ->
                new(name, "Shoulders",
                    primary = mapOf("posterior_deltoid" to 1.0, "rhomboids" to 0.7),
                    secondary = mapOf("rotator_cuff" to 0.6, "trapezius_mid" to 0.5))

            has("lat pulldown", "pulldown") ->
                new(name, "Back",
                    primary = mapOf("latissimus_dorsi" to 1.0, "biceps_brachii" to 0.5),
                    secondary = mapOf("teres_major" to 0.5, "rhomboids" to 0.4))

            has("row") ->
                new(name, "Back",
                    primary = mapOf("latissimus_dorsi" to 0.9, "rhomboids" to 0.8, "trapezius_mid" to 0.7),
                    secondary = mapOf("biceps_brachii" to 0.5, "posterior_deltoid" to 0.4))

            has("calf") ->
                new(name, "Legs",
                    primary = mapOf("gastrocnemius" to 1.0, "soleus" to 0.8),
                    secondary = mapOf("tibialis_anterior" to 0.2))

            has("lunge", "split squat") ->
                new(name, "Legs",
                    primary = mapOf("gluteus_maximus" to 1.0, "rectus_femoris" to 0.8),
                    secondary = mapOf("gluteus_medius" to 0.5, "adductors" to 0.4))

            has("leg extension") ->
                new(name, "Legs",
                    primary = mapOf("rectus_femoris" to 1.0, "vastus_lateralis" to 0.9),
                    secondary = mapOf("vastus_medialis" to 0.8))

            has("leg curl", "hamstring curl") ->
                new(name, "Legs",
                    primary = mapOf("biceps_femoris" to 1.0, "semitendinosus" to 0.8),
                    secondary = mapOf("semimembranosus" to 0.7))

            has("upright row") ->
                new(name, "Shoulders",
                    primary = mapOf("lateral_deltoid" to 1.0, "trapezius_upper" to 0.8),
                    secondary = mapOf("anterior_deltoid" to 0.4))

            has("shrug") ->
                new(name, "Back",
                    primary = mapOf("trapezius_upper" to 1.0),
                    secondary = mapOf("rhomboids" to 0.4, "forearm_flexors" to 0.3))

            has("toes to bar", "leg raise", "crunch", "plank", "sit up", "hanging") ->
                new(name, "Core",
                    primary = mapOf("rectus_abdominis" to 1.0, "iliopsoas" to 0.7),
                    secondary = mapOf("obliques" to 0.5))

            has("chop", "rotation", "russian twist") ->
                new(name, "Core",
                    primary = mapOf("obliques" to 1.0, "transverse_abdominis" to 0.6),
                    secondary = mapOf("rectus_abdominis" to 0.4))

            has("curl") ->
                new(name, "Arms",
                    primary = mapOf("biceps_brachii" to 1.0, "brachialis" to 0.6),
                    secondary = mapOf("brachioradialis" to 0.5))

            has("press") ->
                new(name, "Shoulders",
                    primary = mapOf("anterior_deltoid" to 1.0, "triceps_lateral" to 0.6),
                    secondary = mapOf("lateral_deltoid" to 0.5, "trapezius_upper" to 0.3))

            has("fly", "pec deck", "chest") ->
                new(name, "Chest",
                    primary = mapOf("pectoralis_major" to 1.0),
                    secondary = mapOf("anterior_deltoid" to 0.4))

            has("hip thrust", "glute") ->
                new(name, "Legs",
                    primary = mapOf("gluteus_maximus" to 1.0),
                    secondary = mapOf("biceps_femoris" to 0.5))

            else -> null
        }
    }

    private fun new(
        name: String,
        group: String,
        primary: Map<String, Double>,
        secondary: Map<String, Double>
    ) = Exercise(
        id = "auto_" + name.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_'),
        name = name,
        muscle = group,
        targetReps = 8,
        restSeconds = 120,
        description = "Imported from Garmin. Muscle mapping inferred from the name.",
        primary = primary,
        secondary = secondary
    )
}
