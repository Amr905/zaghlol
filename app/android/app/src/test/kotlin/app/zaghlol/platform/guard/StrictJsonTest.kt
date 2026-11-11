package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** RFC 8259 conformance, with Dart `jsonDecode` parity where it is observable (probed with the Dart SDK). */
class StrictJsonTest {
    private fun rejects(text: String) {
        try {
            StrictJson.parse(text)
            fail("accepted: ${text.take(20)}")
        } catch (e: StrictJsonException) {
            assertEquals("invalid JSON", e.message)
        }
    }

    @Test
    fun rejectsWhatDartRejects() {
        listOf(
            "{\"a\":1,}", "[1,]", "{'a':1}", "{a:1}", "{\"a\":01}", "{\"a\":-}", "{\"a\":1.}", "{\"a\":.5}",
            "{\"a\":+1}", "\uFEFF{}", "\"\u0001\"", "{\"a\":1} x", "", "  ", "{\"a\" 1}", "[1 2]",
            "{\"a\":NaN}", "{\"a\":Infinity}", "\"\\x41\"", "\"\\u12\"", "\"\\u\u0661\u0662\u0663\u0664\"", "// c\n{}", "{\"a\":tru}",
            "\"abc", "{\"a\":1", "nul",
        ).forEach(::rejects)
    }

    @Test
    fun acceptsWhatDartAccepts() {
        assertEquals("\uD800", StrictJson.parse("\"\\ud800\""))
        assertEquals("/", StrictJson.parse("\"\\/\""))
        assertEquals(listOf(1L), StrictJson.parse("[1 ]"))
        assertEquals(emptyMap<String, Any?>(), StrictJson.parse(" \t\r\n{} "))
        assertEquals(0L, StrictJson.parse("-0"))
        assertEquals(true, StrictJson.parse("true"))
        assertEquals(null, StrictJson.parse("null"))
    }

    @Test
    fun duplicateKeyLastWinsAndKeepsFirstPosition() {
        val m = StrictJson.parse("{\"a\":1,\"b\":2,\"a\":3}") as Map<*, *>
        assertEquals(listOf("a", "b"), m.keys.toList())
        assertEquals(3L, m["a"])
    }

    @Test
    fun onlyPlainIntegersAreLongs() {
        assertTrue(StrictJson.parse("4") is Long)
        listOf("4.0", "1e2", "1E+2", "99999999999999999999").forEach { assertTrue(it, StrictJson.parse(it) is Double) }
    }

    @Test
    fun depthIsCappedAt16() {
        StrictJson.parse("[".repeat(16) + "]".repeat(16))
        rejects("[".repeat(17) + "]".repeat(17))
        rejects("{\"a\":".repeat(17) + "1" + "}".repeat(17))
        // Hostile depth fails fast instead of overflowing the stack.
        rejects("[".repeat(100_000))
    }
}
