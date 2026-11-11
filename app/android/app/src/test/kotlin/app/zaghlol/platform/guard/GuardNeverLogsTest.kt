package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream

/**
 * AC5: no body, source, last-4 or config value in any output, exception or
 * `toString` (canary), and no logging call in `platform/guard/` (source scan,
 * until the app-ci grep covers the directory; T-039 owns that edit).
 */
class GuardNeverLogsTest {
    private val canaries = listOf("ZG_CANARY_7731", "7731", "ZG_CANARY_SRC", "zgcanaryinst")

    private fun assertClean(what: String, text: String?) {
        if (text == null) return
        for (c in canaries) assertFalse("$what leaks a canary", text.contains(c))
    }

    @Test
    fun canaryNeverReachesOutputExceptionsOrToString() {
        val out = ByteArrayOutputStream()
        val oldOut = System.out
        val oldErr = System.err
        val seen = ArrayList<String?>()
        System.setOut(PrintStream(out, true))
        System.setErr(PrintStream(out, true))
        try {
            val userJson = mapOf(
                "v" to 1, "baseRegistryVersion" to 3,
                "ignore" to listOf(mapOf("inst" to "nbe", "last4" to "7731", "ch" to "sms")),
                "userSenders" to listOf(mapOf("value" to "ZG_CANARY_SRC", "ch" to "sms")),
            ).bytes()
            val load = GuardConfig.parse(GuardFixtures.t1Base, userJson)
            seen += load.toString()
            seen += load.config.toString()
            val guard = CaptureGuard(load.config)
            seen += guard.toString()
            val bodies = listOf(
                "ZG_CANARY_7731 Purchase EGP 10.00 card **7731",
                "ZG_CANARY_7731 Purchase EGP 10.00 card **7732",
                "ZG_CANARY_7731 OTP is 773100",
                "ZG_CANARY_7731" + "x".repeat(4000),
            )
            for (b in bodies) {
                for (src in listOf("NBE", "ZG_CANARY_SRC", "ZG_CANARY_SRC" + "x".repeat(300))) {
                    for (ch in listOf("sms", "notification", "apple_pay", "ZG_CANARY_SRC")) {
                        val d = guard.decide(ch, src, b)
                        seen += d.toString()
                        if (d is GuardDecision.Keep) seen += GuardDecision.Keep(d.kind, d.inst, d.last4).toString()
                    }
                }
            }
            // Error paths: a canary in every kind of bad input.
            val badUsers = listOf(
                "{\"v\":1,\"ZG_CANARY_7731\":1}",
                "{\"v\":1,\"baseRegistryVersion\":3,\"ignore\":[{\"inst\":\"zgcanaryinst\",\"last4\":\"ZG_CANARY_7731\",\"ch\":\"sms\"}],\"userSenders\":[]}",
                "{\"v\":\"ZG_CANARY_7731\"}",
                "ZG_CANARY_7731",
                "{\"v\":1,\"baseRegistryVersion\":3,\"ignore\":[],\"userSenders\":[{\"value\":\"ZG_CANARY_SRC\",\"ch\":\"ZG_CANARY_SRC\"}]}",
            )
            val rt = GuardRuntime({ GuardFixtures.t1Base }, GuardUserConfigStore(File(tempDir(), "guard"), SoftwareGuardUserCipher()), { 0L })
            for (u in badUsers) {
                val l = GuardConfig.parse(GuardFixtures.t1Base, u.toByteArray())
                seen += l.toString()
                seen += l.userError.toString()
                seen += GuardConfig.validateUser(u.toByteArray()).toString()
                try {
                    rt.writeUser(u.toByteArray())
                } catch (e: GuardConfigWriteException) {
                    seen += e.message
                    seen += e.toString()
                    seen += e.stackTraceToString()
                }
            }
            seen += rt.current().toString()
            seen += GuardUserConfigStore(File(tempDir(), "g"), SoftwareGuardUserCipher()).read().toString()
            seen += GuardUserConfigStore.Read.Plain("ZG_CANARY_7731".toByteArray()).toString()
            seen += GuardIgnoreKey("zgcanaryinst", "7731", GuardIgnoreChannel.SMS).toString()
            seen += GuardUserSender("sms", "ZG_CANARY_SRC").toString()
            val limiter = SenderRateLimiter(1)
            limiter.apply(GuardDecision.Keep(GuardKeepKind.REGISTRY, "nbe", "7731"), "sms", "ZG_CANARY_SRC", 0)
            seen += limiter.toString()
            try {
                StrictJson.parse("{\"ZG_CANARY_7731\" 1}")
            } catch (e: StrictJsonException) {
                seen += e.message
            }
            try {
                throw GuardConfigException(GuardConfigErrorCode.badValue, "$.ignore[0].last4")
            } catch (e: GuardConfigException) {
                assertEquals("badValue at $.ignore[0].last4", e.message)
            }
        } finally {
            System.setOut(oldOut)
            System.setErr(oldErr)
        }
        assertEquals("", out.toString(Charsets.UTF_8.name()))
        seen.forEach { assertClean("toString/message", it) }
        assertTrue(seen.size > 60)
    }

    @Test
    fun baseReaderIsBounded() {
        val big = ByteArrayInputStream(ByteArray(1_000_000))
        assertEquals(GuardConfig.MAX_BASE_BYTES + 1, BaseConfigSource.readBounded(big, GuardConfig.MAX_BASE_BYTES).size)
        assertEquals(10, BaseConfigSource.readBounded(ByteArrayInputStream(ByteArray(10)), 100).size)
        assertEquals(100, BaseConfigSource.readBounded(ByteArrayInputStream(ByteArray(100)), 100).size)
        val tooBig = BaseConfigSource.readBounded(ByteArrayInputStream(ByteArray(GuardConfig.MAX_BASE_BYTES + 5)), GuardConfig.MAX_BASE_BYTES)
        assertEquals(GuardConfigErrorCode.tooLarge, GuardConfig.parse(tooBig, null).baseError!!.code)
    }

    /** No logging call in the Guard sources (same pattern as the app-ci grep). */
    @Test
    fun sourcesHaveNoLoggingCalls() {
        val dir = File(System.getProperty("zaghlol.guardSources") ?: error("zaghlol.guardSources is not set"))
        val files = dir.listFiles { f -> f.name.endsWith(".kt") }!!.toList()
        assertTrue(files.size >= 10)
        val forbidden = Regex("""\b(print|debugPrint|log|dump)\(|\b(stdout|stderr)\b|\bLog\.[a-z]+\(|println\(|Timber|System\.(out|err)|printStackTrace|Logger\(""")
        for (f in files) {
            f.readLines().forEachIndexed { i, line ->
                assertFalse("${f.name}:${i + 1} logs", forbidden.containsMatchIn(line))
            }
        }
    }
}
