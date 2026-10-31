package com.strive.mobile.data

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Runs shared/engine-vectors.json against the Kotlin engine.
 *
 * The same file is generated into garmin/watch/test/Vectors.mc and run by
 * TestEngine.mc there, so this suite is half of the agreement check: if the two
 * implementations drift, one of the two goes red.
 *
 * Nothing here is hand-copied. The JSON is on the test classpath because
 * app/build.gradle adds ../../shared to the test resources.
 */
class EngineTest {

    private val vectors: JSONObject by lazy {
        val stream = javaClass.getResourceAsStream("/engine-vectors.json")
            ?: throw AssertionError(
                "engine-vectors.json is not on the test classpath: " +
                    "check the sourceSets test resources entry in app/build.gradle"
            )
        JSONObject(stream.bufferedReader().readText())
    }

    private val tolerance: Double get() = vectors.getDouble("tolerance")

    // ---- 1. strength -----------------------------------------------------

    @Test
    fun e1rmCases() = runCases("e1rm") { c ->
        val actual = if (c.has("bodyKg")) {
            Engine.e1rm(
                c.getDouble("weight"),
                c.getInt("reps"),
                c.getInt("rir"),
                c.getDouble("bodyKg"),
                c.getDouble("bodyweightFraction")
            )
        } else {
            Engine.e1rm(c.getDouble("weight"), c.getInt("reps"), c.getInt("rir"))
        }
        close(actual, c.getDouble("expect"), "e1rm")
    }

    // ---- 2. next load ----------------------------------------------------

    @Test
    fun nextLoadCases() = runCases("nextLoad") { c ->
        val advice = Engine.nextLoad(
            spec(c.getJSONObject("spec")),
            engineSets(c.getJSONArray("history")),
            c.getDouble("seedKg")
        )
        close(advice.weightKg, c.getDouble("expectWeight"), "weightKg")
            ?: if (advice.targetReps != c.getInt("expectReps")) {
                "targetReps ${advice.targetReps} != ${c.getInt("expectReps")}"
            } else null
    }

    // ---- 3. how many sets ------------------------------------------------

    @Test
    fun recommendedSetsCases() = runCases("recommendedSets") { c ->
        val sets = Engine.recommendedSets(
            spec(c.getJSONObject("spec")),
            c.getInt("weeklyMuscleSets"),
            c.getBoolean("everTrained")
        )
        if (sets != c.getInt("expect")) "sets $sets != ${c.getInt("expect")}" else null
    }

    // ---- 4. load and recovery --------------------------------------------

    @Test
    fun muscleLoadCases() = runCases("muscleLoad") { c ->
        val actual = Engine.muscleLoad(
            specs(c.getJSONArray("specs")),
            timedSets(c.getJSONArray("sets")),
            c.getLong("now")
        )
        compareMaps(actual, c.getJSONObject("expect"), "load")
    }

    @Test
    fun recoveryCases() = runCases("recovery") { c ->
        compareMaps(Engine.recovery(doubleMap(c.getJSONObject("load"))), c.getJSONObject("expect"), "recovery")
    }

    @Test
    fun rankCases() = runCases("rank") { c ->
        val ranked = Engine.rank(
            specList(c.getJSONArray("specs")),
            timedSets(c.getJSONArray("sets")),
            c.getLong("now")
        )

        val expectedOrder = c.getJSONArray("expectOrder")
            .let { array -> (0 until array.length()).map { array.getString(it) } }
        val actualOrder = ranked.map { it.exerciseId }
        if (actualOrder != expectedOrder) {
            return@runCases "order $actualOrder != $expectedOrder"
        }

        val expectedScores = c.getJSONObject("expectScores")
        for (entry in ranked) {
            close(entry.score, expectedScores.getDouble(entry.exerciseId), "score(${entry.exerciseId})")
                ?.let { return@runCases it }
        }
        null
    }

    // ---- 6. rest ---------------------------------------------------------

    @Test
    fun restCases() = runCases("rest") { c ->
        val advice = Engine.rest(
            baseSeconds = c.getInt("base"),
            peakHr = if (c.isNull("peakHr")) null else c.getInt("peakHr"),
            currentHr = if (c.isNull("currentHr")) null else c.getInt("currentHr"),
            restingHr = c.getInt("restingHr"),
            ceilingSeconds = if (c.isNull("ceiling")) null else c.getInt("ceiling")
        )
        when {
            advice.seconds != c.getInt("expectSeconds") ->
                "seconds ${advice.seconds} != ${c.getInt("expectSeconds")}"
            advice.ready != c.getBoolean("expectReady") ->
                "ready ${advice.ready} != ${c.getBoolean("expectReady")}"
            else -> null
        }
    }

    // ---- 5. seeds --------------------------------------------------------

    @Test
    fun seedCases() = runCases("seed") { c ->
        val seeds = Engine.seedE1rm(
            c.getDouble("bodyKg"),
            c.getInt("pushUpReps"),
            c.getInt("squatReps")
        )
        compareMaps(seeds, c.getJSONObject("expectE1rm"), "seedE1rm")
            ?: close(
                Engine.seedWeight(spec(c.getJSONObject("spec")), seeds),
                c.getDouble("expectWeight"),
                "seedWeight"
            )
    }

    /** The file has to carry real cases in every section or the suites prove nothing. */
    @Test
    fun everySectionIsPopulated() {
        val sections = listOf("e1rm", "nextLoad", "recommendedSets", "muscleLoad", "recovery", "rank", "rest", "seed")
        var total = 0
        for (section in sections) {
            assertTrue("section $section is missing", vectors.has(section))
            val count = vectors.getJSONArray(section).length()
            assertTrue("section $section is empty", count > 0)
            total += count
        }
        assertTrue("only $total cases: the vector file is the agreement contract", total >= 30)
    }

    // ---- plumbing --------------------------------------------------------

    private fun runCases(section: String, check: (JSONObject) -> String?) {
        val cases = vectors.getJSONArray(section)
        val failures = mutableListOf<String>()
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            check(c)?.let { failures += "${c.optString("name", "case $i")}: $it" }
        }
        assertTrue(
            "$section: ${failures.size} of ${cases.length()} cases failed\n" + failures.joinToString("\n"),
            failures.isEmpty()
        )
    }

    private fun close(actual: Double, expected: Double, label: String): String? =
        if (kotlin.math.abs(actual - expected) > tolerance) "$label $actual != $expected" else null

    private fun compareMaps(actual: Map<String, Double>, expected: JSONObject, label: String): String? {
        val keys = expected.keys().asSequence().toSet()
        if (actual.keys != keys) return "$label keys ${actual.keys.sorted()} != ${keys.sorted()}"
        for (key in keys) {
            close(actual.getValue(key), expected.getDouble(key), "$label($key)")?.let { return it }
        }
        return null
    }

    private fun spec(o: JSONObject) = EngineSpec(
        id = o.getString("id"),
        lo = o.getInt("lo"),
        hi = o.getInt("hi"),
        incrementKg = o.getDouble("inc"),
        minWeightKg = o.getDouble("minW"),
        restSeconds = o.getInt("rest"),
        primary = doubleMap(o.optJSONObject("primary")),
        secondary = doubleMap(o.optJSONObject("secondary")),
        pattern = o.optString("pattern", ""),
        bodyweightFraction = o.optDouble("bw", 0.0)
    )

    private fun specList(array: JSONArray): List<EngineSpec> =
        (0 until array.length()).map { spec(array.getJSONObject(it)) }

    private fun specs(array: JSONArray): Map<String, EngineSpec> =
        specList(array).associateBy { it.id }

    private fun engineSets(array: JSONArray): List<EngineSet> = (0 until array.length()).map {
        val o = array.getJSONObject(it)
        EngineSet(
            weightKg = o.getDouble("weight"),
            reps = o.getInt("reps"),
            rir = if (o.isNull("rir")) null else o.getInt("rir")
        )
    }

    private fun timedSets(array: JSONArray): List<TimedSet> = (0 until array.length()).map {
        val o = array.getJSONObject(it)
        TimedSet(
            exerciseId = o.getString("id"),
            weightKg = o.getDouble("weight"),
            reps = o.getInt("reps"),
            rir = if (o.isNull("rir")) null else o.getInt("rir"),
            timestampEpochSeconds = o.getLong("ts")
        )
    }

    private fun doubleMap(o: JSONObject?): Map<String, Double> {
        if (o == null) return emptyMap()
        val out = mutableMapOf<String, Double>()
        for (key in o.keys()) out[key] = o.getDouble(key)
        return out
    }
}
