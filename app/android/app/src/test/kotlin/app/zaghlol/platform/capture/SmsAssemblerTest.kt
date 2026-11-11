package app.zaghlol.platform.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Multipart assembly (EC-09, T-040 design note sections 3 and 11). */
class SmsAssemblerTest {
    private fun one(parts: List<SmsPart>): AssembledSms = SmsAssembler.assemble(parts).single()

    @Test
    fun onePart() {
        val m = one(listOf(SmsPart("CIB", "Purchase EGP 10.00", 5)))
        assertEquals("CIB", m.source)
        assertEquals("Purchase EGP 10.00", m.body)
    }

    @Test
    fun threePartsJoinInArrayOrderEvenWithDecreasingTimestamps() {
        val m = one(listOf(SmsPart("CIB", "a-", 30), SmsPart("CIB", "b-", 20), SmsPart("CIB", "c", 10)))
        assertEquals("a-b-c", m.body)
    }

    @Test
    fun twoAddressesGiveTwoMessagesInFirstSeenOrder() {
        val ms = SmsAssembler.assemble(
            listOf(SmsPart("NBE", "1", 1), SmsPart("CIB", "x", 1), SmsPart("NBE", "2", 1), SmsPart("CIB", "y", 1)),
        )
        assertEquals(listOf("NBE" to "12", "CIB" to "xy"), ms.map { it.source to it.body })
    }

    @Test
    fun aNullPartBodyContributesNothing() {
        assertEquals("ab", one(listOf(SmsPart("CIB", "a", 1), SmsPart("CIB", null, 1), SmsPart("CIB", "b", 1))).body)
    }

    @Test
    fun partsWithoutAnAddressAreDropped() {
        val ms = SmsAssembler.assemble(listOf(SmsPart(null, "lost", 1), SmsPart("", "lost too", 1), SmsPart("CIB", "kept", 1)))
        assertEquals(listOf("CIB" to "kept"), ms.map { it.source to it.body })
        assertEquals(0, SmsAssembler.assemble(listOf(SmsPart(null, "x", 1))).size)
        assertEquals(0, SmsAssembler.assemble(emptyList()).size)
    }

    @Test
    fun aSixPartArabicBodyEqualsTheSource() {
        val source = SmsCaptureScenario.LONG_BODY
        val parts = source.chunked(67).map { SmsPart(SmsCaptureScenario.USER_SENDER, it, 1_700_000_000_000L) }
        assertTrue(parts.size >= 6)
        val m = one(parts)
        assertEquals(source, m.body)
        assertEquals(SmsCaptureScenario.USER_SENDER, m.source)
    }

    @Test
    fun theSourceIsKeptRaw() {
        assertEquals("+20 100-123", one(listOf(SmsPart("+20 100-123", "x", 1))).source)
    }

    @Test
    fun partsAndMessagesNeverPrintContent() {
        val p = SmsPart("ZG_CANARY_SRC", "ZG_CANARY_7731", 1)
        val m = one(listOf(p))
        for (s in listOf(p.toString(), m.toString())) {
            assertFalse(s.contains("ZG_CANARY"))
        }
    }
}
