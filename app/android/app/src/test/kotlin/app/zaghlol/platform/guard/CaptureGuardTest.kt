package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.random.Random

class CaptureGuardTest {
    private val t1 = CaptureGuard(GuardConfig.parse(GuardFixtures.t1Base, GuardFixtures.t1User).config)

    private fun guardWith(edit: MutableMap<String, Any?>.() -> Unit, user: ByteArray? = null): CaptureGuard {
        val load = GuardConfig.parse(jsonOf(GuardFixtures.t1Base).apply(edit).bytes(), user)
        return CaptureGuard(checkNotNull(load.config) { load.toString() })
    }

    /** Wire names equal Dart's `guard_types.dart` (read from the Dart source next to the fixtures). */
    @Test
    fun wireNamesMatchDart() {
        val dart = File(GuardFixtures.dir, "../../../lib/guard/guard_types.dart").readText()
        fun wires(enumName: String): List<String> {
            val body = dart.substringAfter("enum $enumName {").substringBefore(";\n")
            return Regex("""\w+\('([a-z_]+)'\)""").findAll(body).map { it.groupValues[1] }.toList()
        }
        assertEquals(wires("GuardChannel"), GuardChannel.entries.map { it.wire })
        assertEquals(wires("GuardIgnoreChannel"), GuardIgnoreChannel.entries.map { it.wire })
        assertEquals(wires("GuardDropReason"), GuardDropReason.entries.map { it.wire })
        assertEquals(wires("GuardKeepKind"), GuardKeepKind.entries.map { it.wire })
        assertEquals(10, GuardDropReason.entries.size)
    }

    @Test
    fun policyConstantsMatchDart() {
        val dart = File(GuardFixtures.dir, "../../../lib/guard/guard_policy.dart").readText()
        assertTrue(dart.contains("kGuardUserConfigFailure =\n    GuardUserConfigFailure.keepWithBase;"))
        assertEquals(GuardUserConfigFailure.KEEP_WITH_BASE, GuardPolicy.USER_CONFIG_FAILURE)
        assertTrue(dart.contains("const bool kShortcutMessageUsesSmsToggle = true;"))
        assertTrue(GuardPolicy.SHORTCUT_MESSAGE_USES_SMS_TOGGLE)
    }

    /**
     * Dart `guardLast4` looks only at each pattern's **first** match: when its
     * group 1 is not four ASCII digits, the next pattern is tried (not the
     * next match of the same pattern).
     */
    @Test
    fun last4UsesTheFirstMatchOfEachPatternOnly() {
        val guard = guardWith({ obj("last4")["nbe"] = listOf("card ([0-9]+)", "acct ([0-9]{4})") })
        val d = guard.decide("sms", "NBE", "Purchase card 12 then card 4567 acct 9999")
        assertEquals("9999", (d as GuardDecision.Keep).last4)
        val none = guardWith({ obj("last4")["nbe"] = listOf("card ([0-9]+)"); obj("last4")["*"] = listOf<String>() })
        assertEquals(null, (none.decide("sms", "NBE", "card 12 card 4567") as GuardDecision.Keep).last4)
    }

    /** EC-59 property: a random rule set never drops a message of another institution. */
    @Test
    fun aRuleNeverDropsAnotherInstitution() {
        val rnd = Random(59)
        val insts = listOf("nbe", "cib", "bm")
        val sources = mapOf("nbe" to "NBE", "cib" to "CIB", "bm" to "BanqueMisr")
        repeat(300) {
            val ruleInst = insts.random(rnd)
            val last4 = "%04d".format(rnd.nextInt(10000))
            val user = mapOf(
                "v" to 1, "baseRegistryVersion" to 3,
                "ignore" to listOf(mapOf("inst" to ruleInst, "last4" to last4, "ch" to "sms")),
                "userSenders" to emptyList<Any>(),
            ).bytes()
            val guard = CaptureGuard(GuardConfig.parse(GuardFixtures.t1Base, user).config)
            for (other in insts - ruleInst) {
                val d = guard.decide("sms", sources.getValue(other), "Purchase EGP 10.00 card **$last4")
                assertTrue(d !is GuardDecision.Drop || d.reason != GuardDropReason.IGNORED_CARD)
            }
        }
    }

    /**
     * `decide` is total: a `java.util.regex` stack overflow (possible on the
     * JVM, not with ICU) becomes `config_invalid`, nothing escapes.
     */
    @Test
    fun stackOverflowInARegexIsConfigInvalid() {
        val guard = guardWith({ obj("drop").put("global", listOf("(?:a|b)*c")) })
        val body = "ab".repeat(1999)
        var result: GuardDecision? = null
        val t = Thread(null, { result = guard.decide("sms", "NBE", body) }, "small-stack", 32 * 1024)
        t.start()
        t.join()
        assertEquals(mapOf("decision" to "drop", "reason" to "config_invalid"), decision(result!!))
    }

    @Test
    fun outOfMemoryIsRethrown() {
        val oom = OutOfMemoryError()
        try {
            rethrowIfFatal(oom)
            throw AssertionError("not rethrown")
        } catch (e: OutOfMemoryError) {
            assertTrue(e === oom)
        }
        rethrowIfFatal(StackOverflowError())
        rethrowIfFatal(IllegalStateException())
    }

    @Test
    fun nullConfigDropsEverythingFirst() {
        val guard = CaptureGuard(null)
        // config_invalid is checked before channel and length (T-035 deviation 2).
        listOf("sms" to "Purchase", "mms" to "Purchase", "sms" to "x".repeat(5000)).forEach { (ch, body) ->
            assertEquals(mapOf("decision" to "drop", "reason" to "config_invalid"), decision(guard.decide(ch, "NBE", body)))
        }
    }

    @Test
    fun globalDropRunsOnLinesAndInstitutionDropOnTheSpacedFold() {
        // A pattern that needs the `\n` itself matches only the `foldKeyLines` form.
        val g = guardWith({ obj("drop").put("global", listOf("otp\\n[0-9]{4}")) })
        assertEquals("otp_or_promo_global", decision(g.decide("sms", "NBE", "OTP\n1234 x"))["reason"])
        assertEquals("keep", decision(g.decide("sms", "NBE", "OTP 1234 x"))["decision"])
        val i = guardWith({ obj("drop").obj("byInst").put("nbe", listOf("otp 1234")) })
        assertEquals("otp_or_promo_inst", decision(i.decide("sms", "NBE", "OTP\n1234"))["reason"])
    }

    @Test
    fun containsMatchNotFullMatch() {
        assertEquals("keep", decision(t1.decide("sms", "CIB-ALERT", "Purchase EGP 10.00"))["decision"])
        // Every golden sender regex is anchored, so search vs full match is pinned here.
        val g = guardWith({ arr("senders").add(mapOf("match" to "regex", "value" to "zgbank", "inst" to "cib")) })
        assertEquals("cib", decision(g.decide("sms", "AB-ZGBANK-1", "Purchase EGP 10.00"))["inst"])
        val hints = guardWith({ obj("generic").put("senderHints", listOf("ank")) })
        assertEquals("generic", decision(hints.decide("sms", "MyBank", "Paid EGP 5"))["kind"])
        val d = t1.decide("sms", "NBE", "Your OTP is 482913 thanks")
        assertEquals("otp_or_promo_global", decision(d)["reason"])
    }

    @Test
    fun toStringNeverShowsLast4OrInstitution() {
        val keep = GuardDecision.Keep(GuardKeepKind.REGISTRY, "nbe", "7731")
        assertEquals("GuardKeep(registry)", keep.toString())
        assertEquals("GuardDrop(ignored_card)", GuardDecision.Drop(GuardDropReason.IGNORED_CARD).toString())
    }
}
