package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * AC1 on the JVM: every entry of the shared golden file, read in place, with
 * `count` asserted. The same runner runs on devices (ICU regex) in
 * `GuardGoldenInstrumentedTest`.
 */
class GuardGoldenJvmTest {
    private val runner = GuardFixtures.runner()

    @Test
    fun allGoldenEntriesPass() {
        val result = runner.runAll()
        assertTrue(result.toString(), result.failures.isEmpty())
        assertEquals(result.count, result.total)
        // Floor from the T-035 golden (207) plus the T-038 additions (30).
        assertTrue("golden shrank: ${result.total}", result.total >= 237)
        assertTrue(result.cases >= 60 && result.fold >= 15 && result.rate >= 3 && result.modes >= 4)
    }

    @Test
    fun runnerRejectsAnUnknownTopLevelKeyOrFormat() {
        val text = String(GuardFixtures.bytes("golden.json"), Charsets.UTF_8)
        val extra = GuardGoldenRunner { if (it == "golden.json") text.replaceFirst("{", "{\"cases2\": [],").toByteArray() else GuardFixtures.bytes(it) }
        assertTrue(extra.runAll().failures.any { it.startsWith("unknown top-level keys") })
        val format = GuardGoldenRunner { if (it == "golden.json") text.replaceFirst("\"format\": 1", "\"format\": 2").toByteArray() else GuardFixtures.bytes(it) }
        assertTrue(format.runAll().failures.any { it == "format is not 1" })
    }

    @Test
    fun runnerFailsWhenCountDoesNotMatch() {
        val text = String(GuardFixtures.bytes("golden.json"), Charsets.UTF_8)
        val count = (runner.golden["count"] as Long)
        val wrong = GuardGoldenRunner { if (it == "golden.json") text.replaceFirst("\"count\": $count", "\"count\": ${count + 1}").toByteArray() else GuardFixtures.bytes(it) }
        assertTrue(wrong.runAll().failures.any { it.startsWith("count:") })
    }

    /**
     * Java's `$` also matches before a final line terminator, Dart's does not:
     * the folded forms must never end in `\n` (or start with one).
     */
    @Test
    fun foldedGoldenTextNeverStartsOrEndsWithALineBreak() {
        val inputs = runner.foldEntries.map { it["in"] as String } + runner.caseEntries.map { it["body"] as String }
        for (s in inputs) {
            for (f in listOf(TextFold.foldKey(s), TextFold.foldKeyLines(s))) {
                assertFalse(f.endsWith("\n") || f.startsWith("\n") || f.endsWith(" ") || f.startsWith(" "))
            }
            assertEquals(TextFold.foldKey(s), TextFold.foldKeyLines(s).replace('\n', ' '))
        }
    }
}
