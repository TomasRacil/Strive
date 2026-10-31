package com.strive.mobile.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The rest countdown is the one piece of the train screen that used to hold
 * state of its own and drift. These cases pin the two things that went wrong: it
 * must always be derived from the end time, and a clock that jumps in either
 * direction must not produce a negative number or a timer that never finishes.
 */
class RestClockTest {

    private val endsAt = 1_000_000L + 90_000L  // 90 s of rest, started at t=1_000_000

    @Test
    fun remainderIsDerivedFromTheEndTime() {
        assertEquals(90, RestClock.remainingSeconds(endsAt, 1_000_000L))
        assertEquals(45, RestClock.remainingSeconds(endsAt, 1_045_000L))
        assertEquals(1, RestClock.remainingSeconds(endsAt, endsAt - 400L))
    }

    @Test
    fun aClockJumpForwardEndsTheRestInsteadOfGoingNegative() {
        assertEquals(0, RestClock.remainingSeconds(endsAt, endsAt))
        assertEquals(0, RestClock.remainingSeconds(endsAt, endsAt + 5_000L))
    }

    @Test
    fun aClockJumpBackwardDoesNotFreezeTheTimer() {
        // The clock is set back an hour mid-rest: the remainder is larger, but it
        // is still computed from the end time, so it keeps counting down rather
        // than sitting on the value it held before the jump.
        val afterJump = RestClock.remainingSeconds(endsAt, 1_000_000L - 3_600_000L)
        val aSecondLater = RestClock.remainingSeconds(endsAt, 1_000_000L - 3_600_000L + 1_000L)

        assertTrue(afterJump > 0)
        assertTrue("the timer must keep moving after a backwards jump", aSecondLater < afterJump)
    }

    @Test
    fun noRestIsZero() {
        assertEquals(0, RestClock.remainingSeconds(null, 1_000_000L))
    }
}
