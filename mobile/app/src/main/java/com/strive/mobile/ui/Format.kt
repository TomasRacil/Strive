package com.strive.mobile.ui

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Display formatting. Weights live in kilograms everywhere; this is the only
 * place that knows about pounds, so a unit change never rewrites stored data.
 */
object Format {

    private const val LB_PER_KG = 2.2046226218

    fun toDisplay(kg: Double, unit: String): Double = if (unit == "lb") kg * LB_PER_KG else kg

    fun toKg(value: Double, unit: String): Double = if (unit == "lb") value / LB_PER_KG else value

    fun step(unit: String): Double = if (unit == "lb") 5.0 else 2.5

    fun weight(kg: Double, unit: String): String =
        String.format(Locale.US, "%.1f %s", toDisplay(kg, unit), unit)

    fun volume(kg: Double, unit: String): String {
        val v = toDisplay(kg, unit)
        return if (v >= 1000) String.format(Locale.US, "%.1f t", v / 1000)
        else String.format(Locale.US, "%,.0f %s", v, unit)
    }

    fun date(millis: Long, lang: String): String {
        val locale = if (lang == "cs") Locale.forLanguageTag("cs-CZ") else Locale.US
        // English puts the month first; Czech puts the day first.
        val pattern = if (lang == "cs") "d. MMM" else "MMM d"
        val fmt = DateTimeFormatter.ofPattern(pattern, locale)
        return Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).format(fmt)
    }

    fun duration(seconds: Long): String =
        if (seconds < 60) "${seconds}s" else "${seconds / 60} min"
}
