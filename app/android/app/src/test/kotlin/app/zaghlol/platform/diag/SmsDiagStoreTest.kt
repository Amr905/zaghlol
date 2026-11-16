package app.zaghlol.platform.diag

import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** SMS-device: the debug counters keep counts and sender names, never a body. */
class SmsDiagStoreTest {
    private val file = File(tempDir(), "diag/sms_counts.tsv")

    @Test
    fun countsPerSenderAndStage() {
        val s = SmsDiagStore(file)
        s.record("HSBC", "received")
        s.record("HSBC", "received")
        s.record("HSBC", "kept:registry")
        s.record("CIB", "drop:no_digit")
        assertEquals(
            mapOf("CIB" to mapOf("drop:no_digit" to 1), "HSBC" to mapOf("kept:registry" to 1, "received" to 2)),
            s.snapshot(),
        )
    }

    @Test
    fun aPhoneNumberSenderIsNeverNamed() {
        assertEquals("(number)", SmsDiagStore.labelOf("+20 100 123 4567"))
        assertEquals("(number)", SmsDiagStore.labelOf("01001234567"))
        assertEquals("(none)", SmsDiagStore.labelOf("  "))
        assertEquals("HSBC EG", SmsDiagStore.labelOf("HSBC EG"))
        val s = SmsDiagStore(file)
        s.record("01001234567", "received")
        assertFalse(file.readText().contains("01001234567"))
    }

    @Test
    fun countsSurviveARestartAndReset() {
        SmsDiagStore(file).apply { record("NBE", "spooled") }
        val again = SmsDiagStore(file)
        again.record("NBE", "spooled")
        assertEquals(mapOf("NBE" to mapOf("spooled" to 2)), again.snapshot())
        again.reset()
        assertTrue(again.snapshot().isEmpty())
        assertFalse(file.exists())
    }

    @Test
    fun theFileHoldsOnlyNamesStagesAndCounts() {
        val s = SmsDiagStore(file)
        s.record("NBE", "kept:registry")
        for (line in file.readLines()) {
            val p = line.split('\t')
            assertEquals(3, p.size)
            assertTrue(p[2].toInt() > 0)
        }
    }
}
