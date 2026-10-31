package com.strive.mobile.ui

/**
 * The rest countdown, as a function of the clock rather than a counter.
 *
 * A counter decremented by a coroutine loses its place on recomposition and
 * stops while the app is backgrounded, so the screen stores the wall-clock
 * instant rest ends and asks this for the remainder on every tick. Nothing is
 * accumulated here, which is what makes a clock jump harmless: the answer is
 * always derived, never carried.
 */
object RestClock {

    /**
     * Seconds left until [endsAt], rounded up so a running rest never displays
     * 0:00, and clamped at zero so a clock that jumped forward ends the rest
     * instead of showing a negative number.
     */
    fun remainingSeconds(endsAt: Long?, nowMillis: Long): Int {
        if (endsAt == null) return 0
        val remainingMillis = endsAt - nowMillis
        if (remainingMillis <= 0L) return 0
        val seconds = (remainingMillis + 999L) / 1000L
        // A clock that jumped backwards by decades would overflow Int; an
        // hour-long rest is already nonsense, so cap instead of wrapping.
        return seconds.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }
}
