package com.strive.mobile.data

/**
 * Seed library. Mirrors the six lifts the watch app ships with, so the phone and
 * the wrist agree on ids and rest durations.
 */
object Seed {
    val exercises: List<Exercise> = listOf(
        Exercise(
            id = "bench_press",
            name = "Bench Press",
            muscle = "Chest",
            targetReps = 8,
            restSeconds = 150,
            description = "Barbell bench press, flat bench. The main horizontal press: " +
                "chest, front delts and triceps. Keep the shoulder blades pulled back " +
                "and the bar touching the lower chest.",
            primary = mapOf(
                "pectoralis_major" to 1.0,
                "anterior_deltoid" to 0.55,
                "triceps_lateral" to 0.5
            ),
            secondary = mapOf(
                "pectoralis_minor" to 0.4,
                "serratus_anterior" to 0.3,
                "triceps_medial" to 0.3,
                "rotator_cuff" to 0.2
            ),
            variations = listOf(
                Variation("bench_incline", "Incline", "Upper chest emphasis; 30-45 degrees.", 8, 150),
                Variation("bench_dumbbell", "Dumbbells", "More range, harder to stabilise.", 10, 120),
                Variation("bench_close", "Close grip", "Shifts work to the triceps.", 8, 120)
            )
        ),
        Exercise(
            id = "squats",
            name = "Squats",
            muscle = "Legs",
            targetReps = 6,
            restSeconds = 180,
            description = "Back squat. The whole lower body under load, with the trunk " +
                "holding position. Depth to at least parallel keeps the quads and " +
                "glutes sharing the work.",
            primary = mapOf(
                "vastus_lateralis" to 0.9,
                "gluteus_maximus" to 0.9,
                "rectus_femoris" to 0.8,
                "vastus_medialis" to 0.8
            ),
            secondary = mapOf(
                "erector_spinae" to 0.5,
                "adductors" to 0.4,
                "biceps_femoris" to 0.4,
                "semitendinosus" to 0.3,
                "transverse_abdominis" to 0.3,
                "gluteus_medius" to 0.3
            ),
            variations = listOf(
                Variation("squat_front", "Front squat", "More quad and upper back, less load.", 6, 180),
                Variation("squat_highbar", "High bar", "More upright, quad-dominant.", 8, 180),
                Variation("squat_bulgarian", "Bulgarian split squat", "Single leg; brutal on glutes.", 10, 120)
            )
        ),
        Exercise(
            id = "deadlift",
            name = "Deadlift",
            muscle = "Back",
            targetReps = 5,
            restSeconds = 180,
            description = "Conventional deadlift from the floor. Hips and back doing the " +
                "bulk of it, grip doing more than people give it credit for. Bar close " +
                "to the shins, chest up, hips and shoulders rising together.",
            primary = mapOf(
                "gluteus_maximus" to 1.0,
                "erector_spinae" to 0.9,
                "biceps_femoris" to 0.8
            ),
            secondary = mapOf(
                "forearm_flexors" to 0.6,
                "latissimus_dorsi" to 0.5,
                "rectus_femoris" to 0.4,
                "trapezius_mid" to 0.4,
                "semimembranosus" to 0.4,
                "adductors" to 0.3
            ),
            variations = listOf(
                Variation("deadlift_sumo", "Sumo", "Wider stance, more hip and less back.", 5, 180),
                Variation("deadlift_rdl", "Romanian", "Hinge only; hamstrings and glutes.", 8, 150),
                Variation("deadlift_trap", "Trap bar", "Neutral grip, easier on the lower back.", 6, 180)
            )
        ),
        Exercise(
            id = "overhead_press",
            name = "Overhead Press",
            muscle = "Shoulders",
            targetReps = 8,
            restSeconds = 120,
            description = "Standing barbell press. Front and side delts with the triceps " +
                "locking out, and the trunk resisting the lean. Squeeze the glutes to " +
                "stop the lower back taking over.",
            primary = mapOf(
                "anterior_deltoid" to 1.0,
                "lateral_deltoid" to 0.6,
                "triceps_lateral" to 0.5
            ),
            secondary = mapOf(
                "trapezius_upper" to 0.4,
                "rotator_cuff" to 0.3,
                "serratus_anterior" to 0.3,
                "rectus_abdominis" to 0.2,
                "triceps_medial" to 0.2
            ),
            variations = listOf(
                Variation("ohp_seated", "Seated", "Removes leg drive; stricter.", 8, 120),
                Variation("ohp_dumbbell", "Dumbbells", "Independent arms, more range.", 10, 120),
                Variation("ohp_push", "Push press", "Leg drive, heavier loads.", 6, 150)
            )
        ),
        Exercise(
            id = "pull_ups",
            name = "Pull-ups",
            muscle = "Back",
            targetReps = 8,
            restSeconds = 120,
            description = "Overhand pull-ups from a dead hang. Lats and biceps, with the " +
                "mid-back pulling the shoulder blades down first. Chin over the bar, " +
                "no swinging.",
            primary = mapOf(
                "latissimus_dorsi" to 1.0,
                "biceps_brachii" to 0.6,
                "teres_major" to 0.6
            ),
            secondary = mapOf(
                "rhomboids" to 0.4,
                "trapezius_mid" to 0.4,
                "brachialis" to 0.4,
                "forearm_flexors" to 0.4,
                "rectus_abdominis" to 0.2
            ),
            variations = listOf(
                Variation("pullup_chin", "Chin-up", "Underhand; more biceps.", 8, 120),
                Variation("pullup_neutral", "Neutral grip", "Easiest on the elbows.", 8, 120),
                Variation("pullup_weighted", "Weighted", "Add load once 10 reps is easy.", 5, 180)
            )
        ),
        Exercise(
            id = "bicep_curls",
            name = "Curls",
            muscle = "Arms",
            targetReps = 10,
            restSeconds = 90,
            description = "Standing dumbbell curls. Biceps and brachialis, with the " +
                "forearm flexors holding the bar. Elbows pinned to the sides; the " +
                "shoulder should not be doing the lifting.",
            primary = mapOf(
                "biceps_brachii" to 1.0,
                "brachialis" to 0.6
            ),
            secondary = mapOf(
                "brachioradialis" to 0.5,
                "forearm_flexors" to 0.4,
                "anterior_deltoid" to 0.1
            ),
            variations = listOf(
                Variation("curl_hammer", "Hammer", "Neutral grip; brachialis and forearms.", 10, 90),
                Variation("curl_incline", "Incline bench", "Stretched position, harder.", 10, 90),
                Variation("curl_preacher", "Preacher", "Strict, no shoulder movement.", 10, 90)
            )
        )
    )
}
