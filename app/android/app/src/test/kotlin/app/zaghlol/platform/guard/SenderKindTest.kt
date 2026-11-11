package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** T-042: [CaptureGuard.senderKind] is step 1 of [CaptureGuard.decide] without the body, minus sender hints. */
class SenderKindTest {
    private val t1 = CaptureGuard(GuardConfig.parse(GuardFixtures.t1Base, GuardFixtures.t1User).config)

    @Test
    fun agreesWithDecideOnANeutralFinancialBody() {
        val body = "Purchase EGP 10.00 at SYNTH SHOP"
        for (s in listOf("NBE", "nbe", " NBE ", "CIB", "cib-egy", "CIB-ALERT", "BanqueMisr", "alahly", "club-7", "MyCoop", "BDC-ALERT", "fawry pay")) {
            val d = t1.decide("sms", s, body)
            val kind = (d as? GuardDecision.Keep)?.kind
            // Ignored institutions are still allowlisted senders; the row is dropped later.
            val expected = kind ?: if ((d as GuardDecision.Drop).reason == GuardDropReason.IGNORED_INSTITUTION) GuardKeepKind.REGISTRY else null
            assertEquals(s, expected, t1.senderKind("sms", s))
        }
    }

    @Test
    fun senderHintsAreNotAnAllowlist() {
        // Kept by decide (hint "bank" + an amount in the body), but not a sender the inbox may read.
        assertEquals(GuardKeepKind.GENERIC, (t1.decide("sms", "MyBank", "Purchase EGP 10.00") as GuardDecision.Keep).kind)
        assertNull(t1.senderKind("sms", "MyBank"))
        assertNull(t1.senderKind("sms", "01001234567"))
    }

    @Test
    fun totalOnBadInput() {
        assertNull(CaptureGuard(null).senderKind("sms", "NBE"))
        assertNull(t1.senderKind("nope", "NBE"))
        assertNull(t1.senderKind("sms", ""))
        assertNull(t1.senderKind("sms", "   "))
        assertNull(t1.senderKind("sms", "N".repeat(CaptureGuard.MAX_SOURCE_LENGTH + 1)))
        // Notification channel: alwaysCapture does not apply (decide parity).
        assertNull(t1.senderKind("notification", "bdc-alert"))
        assertEquals(GuardKeepKind.REGISTRY, t1.senderKind("notification", "com.example.nbe"))
    }
}
