package app.zaghlol.spike.sms

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class SpoolRecordCodecTest {
    @Test
    fun roundTripKeepsEveryField() {
        val r = SpoolRecord("sms", "5550100", "خصم ٤٥٠ ج.م — card **1234 ✓", 123L, 0, "spike", "1234", 99L, 3)
        val d = SpoolRecordCodec.decode(SpoolRecordCodec.encode(r))
        assertEquals(r.channel, d.channel)
        assertEquals(r.source, d.source)
        assertEquals(r.body, d.body)
        assertEquals(r.receivedAtMs, d.receivedAtMs)
        assertEquals(0, d.simSlot)
        assertEquals("spike", d.guardInst)
        assertEquals("1234", d.guardLast4)
        assertEquals(99L, d.rxElapsedNs)
        assertEquals(3, d.bootCount)
    }

    @Test
    fun nullOptionalsRoundTrip() {
        val r = SpoolRecord("sms", "x", "b", 1, null, null, null, 0, -1)
        val d = SpoolRecordCodec.decode(SpoolRecordCodec.encode(r))
        assertNull(d.simSlot)
        assertNull(d.guardInst)
        assertNull(d.guardLast4)
    }

    @Test
    fun everyTruncationIsMalformed() {
        val bytes = SpoolRecordCodec.encode(record())
        for (n in 0 until bytes.size) {
            try {
                SpoolRecordCodec.decode(bytes.copyOf(n))
                fail("prefix $n decoded")
            } catch (_: SpoolFormatException) {
            }
        }
    }

    @Test
    fun trailingByteUnknownVersionAndBadUtf8AreMalformed() {
        val bytes = SpoolRecordCodec.encode(record())
        expectMalformed(bytes + byteArrayOf(0))
        expectMalformed(bytes.copyOf().also { it[0] = 2 })
        // channel "sms" starts at offset 2; 0xC3 0x28 is invalid UTF-8.
        expectMalformed(bytes.copyOf().also { it[2] = 0xC3.toByte(); it[3] = 0x28 })
        expectMalformed(ByteArray(SpoolRecordCodec.MAX_RECORD_BYTES + 1))
    }

    @Test
    fun overLongBodyIsRefusedOnEncode() {
        try {
            SpoolRecordCodec.encode(record(body = "a".repeat(SpoolRecordCodec.MAX_BODY_CHARS + 1)))
            fail("encoded")
        } catch (e: IllegalArgumentException) {
            assertEquals("BODY_TOO_LONG", e.message)
        }
    }

    @Test
    fun toStringIsRedacted() {
        val r = record(body = "ZG_CANARY_7731")
        assertFalse(r.toString().contains("ZG_CANARY"))
        assertArrayEquals(SpoolRecordCodec.encode(r), SpoolRecordCodec.encode(r))
    }

    private fun expectMalformed(b: ByteArray) {
        try {
            SpoolRecordCodec.decode(b)
            fail("decoded")
        } catch (_: SpoolFormatException) {
        }
    }
}
