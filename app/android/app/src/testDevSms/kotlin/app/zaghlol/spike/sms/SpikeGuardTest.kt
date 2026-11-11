package app.zaghlol.spike.sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SpikeGuardTest {
    private val guard = SpikeGuard(listOf("+20 100-000-0000"))

    private fun drop(d: SpikeGuard.Decision) = (d as SpikeGuard.Decision.Drop).reason

    @Test
    fun keepsOnlyAllowlistedSyntheticSenders() {
        val k = guard.decide("sms", "5550100", "spike: you paid EGP 1.00 card **4321") as SpikeGuard.Decision.Keep
        assertEquals("spike", k.inst)
        assertEquals("4321", k.last4)
        assertTrue(guard.decide("sms", "+201000000000", "x") is SpikeGuard.Decision.Keep)
        assertEquals(SpikeGuard.DropReason.NOT_ALLOWLISTED, drop(guard.decide("sms", "CIB", "debited EGP 5")))
        assertEquals(SpikeGuard.DropReason.NOT_ALLOWLISTED, drop(guard.decide("sms", "Mom", "hi")))
        assertEquals(SpikeGuard.DropReason.NOT_ALLOWLISTED, drop(guard.decide("notification", "5550100", "x")))
    }

    @Test
    fun dropsOtpBeforeWriting() {
        assertEquals(SpikeGuard.DropReason.OTP_OR_PROMO, drop(guard.decide("sms", "5550100", "Your OTP is 123456")))
        assertEquals(SpikeGuard.DropReason.OTP_OR_PROMO, drop(guard.decide("sms", "5550100", "رمز التحقق 1234")))
        assertEquals(SpikeGuard.DropReason.OTP_OR_PROMO, drop(guard.decide("sms", "5550100", "one-time password")))
    }

    @Test
    fun tooLongIsDroppedBeforeAnyRegex() {
        val body = "OTP " + "a".repeat(SpoolRecordCodec.MAX_BODY_CHARS)
        assertEquals(SpikeGuard.DropReason.TOO_LONG, drop(guard.decide("sms", "5550100", body)))
        val atLimit = "a".repeat(SpoolRecordCodec.MAX_BODY_CHARS)
        assertTrue(guard.decide("sms", "5550100", atLimit) is SpikeGuard.Decision.Keep)
    }

    @Test
    fun emptyInputsDrop() {
        assertEquals(SpikeGuard.DropReason.EMPTY, drop(guard.decide("sms", null, "x")))
        assertEquals(SpikeGuard.DropReason.EMPTY, drop(guard.decide("sms", "5550100", "")))
    }

    @Test
    fun emptyTesterResourceAddsNothing() {
        val g = SpikeGuard(listOf(""))
        assertEquals(SpikeGuard.DropReason.NOT_ALLOWLISTED, drop(g.decide("sms", "0", "x")))
    }
}
