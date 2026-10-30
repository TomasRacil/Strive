package com.strive.mobile.data

/**
 * Muscle taxonomy.
 *
 * Deliberately fine-grained: the small muscles matter for judging whether a lift
 * actually trains what you think it does (the brachialis under a curl, the
 * rotator cuff under a press). Each muscle carries a `zone` which is the shape
 * the body map draws it in - several muscles can share a zone, and their load
 * shares are summed for display.
 */
data class Muscle(
    val id: String,
    val name: String,
    val group: String,
    val zone: String
)

object Muscles {

    val all: List<Muscle> = listOf(
        // Chest
        Muscle("pectoralis_major", "Pectoralis major", "Chest", "chest"),
        Muscle("pectoralis_minor", "Pectoralis minor", "Chest", "chest"),
        Muscle("serratus_anterior", "Serratus anterior", "Chest", "ribs"),

        // Back
        Muscle("latissimus_dorsi", "Latissimus dorsi", "Back", "lats"),
        Muscle("rhomboids", "Rhomboids", "Back", "upper_back"),
        Muscle("trapezius_upper", "Trapezius (upper)", "Back", "traps"),
        Muscle("trapezius_mid", "Trapezius (mid)", "Back", "upper_back"),
        Muscle("trapezius_lower", "Trapezius (lower)", "Back", "upper_back"),
        Muscle("erector_spinae", "Erector spinae", "Back", "lower_back"),
        Muscle("teres_major", "Teres major", "Back", "lats"),
        Muscle("infraspinatus", "Infraspinatus", "Back", "rear_shoulder"),

        // Shoulders
        Muscle("anterior_deltoid", "Anterior deltoid", "Shoulders", "front_shoulder"),
        Muscle("lateral_deltoid", "Lateral deltoid", "Shoulders", "side_shoulder"),
        Muscle("posterior_deltoid", "Posterior deltoid", "Shoulders", "rear_shoulder"),
        Muscle("rotator_cuff", "Rotator cuff", "Shoulders", "rear_shoulder"),

        // Arms
        Muscle("biceps_brachii", "Biceps brachii", "Arms", "biceps"),
        Muscle("brachialis", "Brachialis", "Arms", "biceps"),
        Muscle("brachioradialis", "Brachioradialis", "Arms", "forearm"),
        Muscle("triceps_long", "Triceps (long head)", "Arms", "triceps"),
        Muscle("triceps_lateral", "Triceps (lateral head)", "Arms", "triceps"),
        Muscle("triceps_medial", "Triceps (medial head)", "Arms", "triceps"),
        Muscle("forearm_flexors", "Forearm flexors", "Arms", "forearm"),
        Muscle("forearm_extensors", "Forearm extensors", "Arms", "forearm"),

        // Legs
        Muscle("rectus_femoris", "Rectus femoris", "Legs", "quads"),
        Muscle("vastus_lateralis", "Vastus lateralis", "Legs", "quads"),
        Muscle("vastus_medialis", "Vastus medialis", "Legs", "quads"),
        Muscle("vastus_intermedius", "Vastus intermedius", "Legs", "quads"),
        Muscle("biceps_femoris", "Biceps femoris", "Legs", "hamstrings"),
        Muscle("semitendinosus", "Semitendinosus", "Legs", "hamstrings"),
        Muscle("semimembranosus", "Semimembranosus", "Legs", "hamstrings"),
        Muscle("gluteus_maximus", "Gluteus maximus", "Legs", "glutes"),
        Muscle("gluteus_medius", "Gluteus medius", "Legs", "glutes"),
        Muscle("adductors", "Adductors", "Legs", "adductors"),
        Muscle("iliopsoas", "Iliopsoas", "Legs", "hip_flexor"),
        Muscle("gastrocnemius", "Gastrocnemius", "Legs", "calves"),
        Muscle("soleus", "Soleus", "Legs", "calves"),
        Muscle("tibialis_anterior", "Tibialis anterior", "Legs", "shin"),

        // Core
        Muscle("rectus_abdominis", "Rectus abdominis", "Core", "abs"),
        Muscle("obliques", "Obliques", "Core", "obliques"),
        Muscle("transverse_abdominis", "Transverse abdominis", "Core", "abs"),
        Muscle("spinal_erectors", "Spinal erectors", "Core", "lower_back")
    )

    private val byId = all.associateBy { it.id }

    fun name(id: String): String = byId[id]?.name ?: id

    fun zone(id: String): String = byId[id]?.zone ?: "other"

    fun group(id: String): String = byId[id]?.group ?: "Other"

    /** Human-readable group names for the summary rows. */
    fun groupsOf(weights: Map<String, Double>): List<Pair<String, Double>> =
        weights.entries
            .groupBy { group(it.key) }
            .map { (group, entries) -> group to entries.sumOf { it.value } }
            .sortedByDescending { it.second }
}
