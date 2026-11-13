package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardDecision
import app.zaghlol.platform.guard.GuardFixtures
import app.zaghlol.platform.guard.GuardKeepKind
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.SoftwareGuardUserCipher
import app.zaghlol.platform.spool.SpoolStore
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The emulator scenario (T-040 design note section 11, T-047 test plan 9)
 * decided on the JVM with the same rules and bodies, so a device failure is
 * plumbing, never a rule question. Also: the devSms spike base parses
 * natively and keeps only the spike sender.
 */
class SmsCaptureScenarioTest {
    private val guard = GuardRuntime(
        { SmsCaptureScenario.base(GuardFixtures.t1Base) },
        GuardUserConfigStore(tempDir(), SoftwareGuardUserCipher()),
        { 0L },
    )

    private fun decide(source: String, body: String) = guard.decide(AndroidGuardChannel.SMS, source, body).toString() to
        guard.decide(AndroidGuardChannel.SMS, source, body)

    @Test
    fun everyScenarioMessageGetsTheExpectedDecision() {
        // Written through the host adapter, as on the device.
        val host = AndroidCaptureHost(1, storeIn(tempDir()), app.zaghlol.platform.spool.SpoolClaim(), statusIn(tempDir()), null, GuardAdapters.writerFor(guard), GuardAdapters.stateFor(guard), null)
        host.writeGuardConfig(SmsCaptureScenario.USER_JSON.toByteArray())
        assertEquals(GuardConfigState.FULL, host.getSpoolStatus().guardState)
        val s = SmsCaptureScenario
        assertEquals("GuardDrop(not_financial)", decide(s.PERSONAL, s.PERSONAL_BODY).first)
        // FU-121: a phone-number user sender must look financial first; the OTP has no amount.
        assertEquals("GuardDrop(not_financial)", decide(s.USER_SENDER, s.OTP_BODY).first)
        assertEquals("GuardKeep(user)", decide(s.USER_SENDER, s.LONG_BODY).first)
        assertEquals("GuardKeep(user)", decide(s.USER_SENDER, s.SINGLE_BODY).first)
        assertEquals("GuardDrop(ignored_card)", decide(s.REGISTRY_SENDER, s.IGNORED_CARD_BODY).first)
        val other = decide(s.REGISTRY_SENDER, s.OTHER_CARD_BODY).second as GuardDecision.Keep
        assertEquals(GuardKeepKind.REGISTRY, other.kind)
        assertEquals("cib", other.inst)
        assertEquals("4321", other.last4)
    }

    @Test
    fun theLongBodyNeedsAtLeastSixUcs2Parts() {
        val body = SmsCaptureScenario.LONG_BODY
        assertTrue(body.any { it.code in 0x0600..0x06FF }) // Arabic: UCS-2 encoding
        assertTrue("${body.length} chars", (body.length + 66) / 67 >= 6)
        assertTrue(body.length <= 4_000)
        assertEquals(1, Regex(SmsCaptureScenario.LONG_START).findAll(body).count())
        assertEquals(3, SmsCaptureScenario.KEPT.size)
    }

    @Test
    fun theScenarioEndToEndOnTheJvmWritesExactlyTheKeptMessages() {
        val root = tempDir()
        host().writeGuardConfig(SmsCaptureScenario.USER_JSON.toByteArray())
        val store = storeIn(File(root, "spool"))
        var enqueues = 0
        val intake = SmsIntake(
            CaptureIntake(AndroidGuardChannel.SMS, guard::decide, store, statusIn(File(root, "status")), { enqueues++ }),
            bootCount = { 1 },
        )
        val s = SmsCaptureScenario
        val broadcasts = listOf(
            listOf(SmsPart(s.PERSONAL, s.PERSONAL_BODY, 1)),
            listOf(SmsPart(s.USER_SENDER, s.OTP_BODY, 1)),
            s.LONG_BODY.chunked(67).map { SmsPart(s.USER_SENDER, it, 1) },
            listOf(SmsPart(s.USER_SENDER, s.SINGLE_BODY, 1)),
            listOf(SmsPart(s.REGISTRY_SENDER, s.IGNORED_CARD_BODY, 1)),
            listOf(SmsPart(s.REGISTRY_SENDER, s.OTHER_CARD_BODY, 1)),
        )
        for (b in broadcasts) intake.process(b, 1L, 2L, null)
        val kept = store.pendingIds().map { (store.read(it) as SpoolStore.ReadResult.Ok).record }.map { it.source to it.body }
        assertEquals(s.KEPT, kept)
        assertEquals(s.KEPT_BROADCASTS, enqueues)
        assertTrue("no status: no alert", !File(root, "status").exists())
    }

    private fun host() = AndroidCaptureHost(1, storeIn(tempDir()), app.zaghlol.platform.spool.SpoolClaim(), statusIn(tempDir()), null, GuardAdapters.writerFor(guard), GuardAdapters.stateFor(guard), null)

    /** devSms: the spike base (an Android asset of src/devSms) parses natively and keeps only 5550100. */
    @Test
    fun theDevSmsSpikeBaseKeepsTheSpikeSenderOnly() {
        val bytes = File("src/devSms/assets/guard/spike_guard_base.json").readBytes()
        val spike = GuardRuntime({ bytes }, GuardUserConfigStore(tempDir(), SoftwareGuardUserCipher()), { 0L })
        assertEquals(app.zaghlol.platform.guard.GuardConfigMode.BASE_ONLY, spike.current().mode)
        val keep = spike.decide(AndroidGuardChannel.SMS, "5550100", "spike: you paid EGP 1.00 at SYNTH SHOP 1 card *4321") as GuardDecision.Keep
        assertEquals("spike", keep.inst)
        assertEquals("4321", keep.last4)
        assertEquals("GuardDrop(otp_or_promo_global)", spike.decide(AndroidGuardChannel.SMS, "5550100", "ZG_CANARY_7731 your OTP is 123456").toString())
        assertEquals("GuardDrop(not_financial)", spike.decide(AndroidGuardChannel.SMS, "5550199", "ZG_CANARY_7731 hello from a friend").toString())
        assertEquals("GuardDrop(not_financial)", spike.decide(AndroidGuardChannel.NOTIFICATION, "5550100", "spike: you paid EGP 1.00").toString())
        // The burst of the latency run (40 within seconds) is not rate-limited.
        repeat(40) { assertTrue(spike.decide(AndroidGuardChannel.SMS, "5550100", "spike: you paid EGP $it.00 at SYNTH SHOP card *4321") is GuardDecision.Keep) }
    }

    /** The device script sends exactly the scenario bodies (single-quoted, verbatim). */
    @Test
    fun theDeviceScriptCarriesTheScenarioBodiesVerbatim() {
        val script = File("../../../.github/scripts/sms-spike-device.sh").readText()
        val s = SmsCaptureScenario
        for (body in listOf(s.PERSONAL_BODY, s.OTP_BODY, s.LONG_BODY, s.SINGLE_BODY, s.IGNORED_CARD_BODY, s.OTHER_CARD_BODY)) {
            assertTrue(body.take(30), script.contains("'$body'"))
        }
        for (sender in listOf(s.PERSONAL, s.USER_SENDER, s.REGISTRY_SENDER)) assertTrue(sender, script.contains("\"$sender|"))
        assertTrue(script.contains("SmsReceiverEmulatorTest"))
    }
}
