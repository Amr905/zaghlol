package app.zaghlol.spike.sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SpoolClaimTest {
    @Test
    fun secondEngineIsRefusedWhileTheFirstHoldsEntries() {
        var now = 0L
        val claim = SpoolClaim(clock = { now })
        assertTrue(claim.acquire(1))
        claim.hold(1, listOf("A", "B"))
        assertFalse(claim.acquire(2))
        claim.acked(1, listOf("A"))
        assertFalse(claim.acquire(2))
        claim.acked(1, listOf("B"))
        assertTrue(claim.acquire(2))
        assertEquals(2L, claim.ownerOrNull())
    }

    @Test
    fun drainingNothingReleases() {
        val claim = SpoolClaim(clock = { 0 })
        assertTrue(claim.acquire(1))
        claim.hold(1, emptyList())
        assertTrue(claim.acquire(2))
    }

    @Test
    fun claimExpires() {
        var now = 0L
        val claim = SpoolClaim(clock = { now })
        claim.acquire(1)
        claim.hold(1, listOf("A"))
        now = SpoolClaim.TTL_MS - 1
        assertFalse(claim.acquire(2))
        now = SpoolClaim.TTL_MS
        assertTrue(claim.acquire(2))
    }

    @Test
    fun releaseAndAckOnlyActOnOwnClaim() {
        val claim = SpoolClaim(clock = { 0 })
        claim.acquire(1)
        claim.hold(1, listOf("A"))
        claim.release(2)
        claim.acked(2, listOf("A"))
        assertEquals(1L, claim.ownerOrNull())
        claim.release(1)
        assertNull(claim.ownerOrNull())
    }

    @Test
    fun ownerMayDrainAgain() {
        val claim = SpoolClaim(clock = { 0 })
        claim.acquire(1)
        claim.hold(1, listOf("A"))
        assertTrue(claim.acquire(1))
    }
}
