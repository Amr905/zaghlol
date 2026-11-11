package app.zaghlol.spike.sms

import app.zaghlol.platform.capture.AndroidCaptureHost
import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.capture.CaptureIntake
import app.zaghlol.platform.capture.FakeDevice
import app.zaghlol.platform.capture.FakeScheduler
import app.zaghlol.platform.capture.SmsIntake
import app.zaghlol.platform.capture.SmsPart
import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.SoftwareGuardUserCipher
import app.zaghlol.platform.spool.AdmissionClass
import app.zaghlol.platform.spool.FlakySpoolCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.record
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream

/**
 * Design note section 9 canary (T-008, T-040): a synthetic body travels the
 * **production** SMS intake (devSms spike Guard base) → spool → production
 * host drain/ack/hold, with the spike latency recorder and its log enabled;
 * neither the log sink, stdout, stderr, thrown errors, the metrics CSV nor
 * the spool bytes ever contain it or the sender.
 */
class CanaryTest {
    private val canary = "ZG_CANARY_7731"
    private val logged = ArrayList<String>()
    private val out = ByteArrayOutputStream()
    private val err = ByteArrayOutputStream()
    private lateinit var oldOut: PrintStream
    private lateinit var oldErr: PrintStream

    @Before
    fun capture() {
        SpikeLog.enabled = true
        SpikeLog.sink = { code, ms -> logged += "code=${code.name} ms=$ms" }
        oldOut = System.out
        oldErr = System.err
        System.setOut(PrintStream(out, true))
        System.setErr(PrintStream(err, true))
    }

    @After
    fun restore() {
        System.setOut(oldOut)
        System.setErr(oldErr)
        SpikeLog.enabled = false
    }

    @Test
    fun canaryNeverLeaks() {
        val dir = tempDir()
        val metricsFile = File(tempDir(), "metrics.csv")
        val metrics = SpikeMetrics(metricsFile, { 7 }, { SpikeMetrics.Conditions(34, false, false, 10, 0) })
        val trace = SpikeTrace(metrics, System::nanoTime, uiAttached = { false }, headlessIdle = { true })
        val store = storeIn(dir)
        val status = statusIn(tempDir())
        val sched = FakeScheduler()
        val guard = GuardRuntime(
            { File("src/devSms/assets/guard/spike_guard_base.json").readBytes() },
            GuardUserConfigStore(tempDir(), SoftwareGuardUserCipher()),
            { 0L },
        )
        val intake = SmsIntake(
            CaptureIntake(AndroidGuardChannel.SMS, guard::decide, store, status, { sched.enqueue() }, { trace }),
            bootCount = { 7 },
            trace = { trace },
        )
        val rx = System.nanoTime()
        val parts = listOf(SmsPart("5550100", "spike: you paid EGP 1.00 at $canary ", 1), SmsPart("5550100", "card *9999", 1))
        val kept = intake.process(parts, 1L, rx, null)
        // OTP and non-allowlisted canaries are dropped without a trace too.
        intake.process(listOf(SmsPart("5550100", "$canary your OTP is 123456", 1)), 1L, rx, null)
        intake.process(listOf(SmsPart("5550199", "$canary hello", 1)), 1L, rx, null)
        val ids = kept.written
        assertEquals(1, ids.size)
        assertEquals(1, sched.enqueued)

        val raw = String(File(dir, "${ids[0]}.bin").readBytes(), Charsets.ISO_8859_1)
        assertFalse(raw.contains(canary))

        trace.runStarted(foreground = false, warmEngine = false)
        val host = AndroidCaptureHost(1, store, SpoolClaim(), status, sched, null, null, FakeDevice(), { trace })
        val entries = host.drainSpool(10)
        assertTrue(entries[0].body.contains(canary))
        metrics.mark("parsed", ids)
        metrics.mark("commit", ids)
        host.ackSpool(ids)

        // T-041 hold path: a drained canary entry is held, never printed.
        store.write(record(body = "$canary held"), AdmissionClass.PRIORITY)
        val heldId = store.pendingIds().single()
        host.drainSpool(10)
        host.holdSpool(listOf(heldId))
        assertEquals(1, store.heldCount())

        // Error paths: a failing cipher and scheduler whose messages carry the canary.
        val hostile = AndroidCaptureHost(
            2,
            storeIn(dir, FlakySpoolCipher(100, canary)),
            SpoolClaim(),
            statusIn(tempDir()),
            { throw IllegalStateException(canary) },
            null,
            null,
            FakeDevice(),
            { trace },
        )
        storeIn(dir).write(record(body = canary), AdmissionClass.PRIORITY)
        val thrown = ArrayList<Throwable>()
        try {
            hostile.scheduleIngestionNow()
        } catch (e: CaptureApiError) {
            thrown += e
        }
        hostile.drainSpool(10) // transient: kept, nothing thrown
        assertEquals(1, thrown.size)
        for (t in thrown) {
            assertFalse(t.toString().contains(canary))
            assertFalse((t.message ?: "").contains(canary))
        }

        assertTrue(logged.any { it.startsWith("code=RX_RECEIVED") })
        assertTrue(logged.none { it.contains(canary) || it.contains("5550100") })
        assertFalse(out.toString().contains(canary))
        assertFalse(err.toString().contains(canary))
        val csv = metricsFile.readText()
        assertFalse(csv.contains(canary))
        assertFalse(csv.contains("5550100"))
        assertTrue(csv.startsWith(SpikeMetrics.HEADER))
        assertTrue(csv.contains(ids[0]))
        assertFalse(intake.toString().contains(canary))
        assertFalse(kept.toString().contains(canary))
    }
}
