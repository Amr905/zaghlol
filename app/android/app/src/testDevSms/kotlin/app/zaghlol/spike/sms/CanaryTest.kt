package app.zaghlol.spike.sms

import app.zaghlol.platform.capture.CaptureApiError
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
 * Design note section 9 canary: a synthetic body travels receiver core →
 * spool → host drain/ack with logging enabled; neither the log sink, stdout,
 * stderr, thrown errors nor the spool bytes ever contain it.
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
        val store = storeIn(dir)
        val sched = FakeScheduler()
        val intake = SmsIntake(SpikeGuard(), store, sched, metrics)
        val stamp = ReceiveStamp(1L, System.nanoTime(), 7, null)
        val parts = listOf(SmsPart("5550100", "$canary paid EGP 1.00 ", 1), SmsPart("5550100", "card **9999", 1))
        val ids = intake.process(SmsAssembler.assemble(parts), stamp)
        // OTP and non-allowlisted canaries are dropped without a trace too.
        intake.process(listOf(AssembledSms("5550100", "$canary OTP 1", 1), AssembledSms("Friend", canary, 1)), stamp)
        assertEquals(1, ids.size)

        val raw = String(File(dir, "${ids[0]}.bin").readBytes(), Charsets.ISO_8859_1)
        assertFalse(raw.contains(canary))

        val host = SpoolHost(1, store, SpoolClaim(), sched, FakeDevice(), metrics) { SpikeMetrics.Cycle(SpikeMetrics.Path.COLD_PROCESS) }
        val entries = host.drainSpool(10)
        assertTrue(entries[0].body.startsWith(canary))
        metrics.mark("parsed", ids)
        metrics.mark("commit", ids)
        host.ackSpool(ids)

        // Error paths: a failing cipher and scheduler whose messages carry the canary.
        val hostile = SpoolHost(2, storeIn(dir, FlakySpoolCipher(100, canary)), SpoolClaim(), { throw IllegalStateException(canary) }, FakeDevice(), metrics) { null }
        storeIn(dir).write(record(body = canary))
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

        assertTrue(logged.isNotEmpty())
        assertTrue(logged.none { it.contains(canary) || it.contains("5550100") })
        assertFalse(out.toString().contains(canary))
        assertFalse(err.toString().contains(canary))
        val csv = metricsFile.readText()
        assertFalse(csv.contains(canary))
        assertFalse(csv.contains("5550100"))
        assertTrue(csv.startsWith(SpikeMetrics.HEADER))
        assertTrue(csv.contains(ids[0]))
    }
}
