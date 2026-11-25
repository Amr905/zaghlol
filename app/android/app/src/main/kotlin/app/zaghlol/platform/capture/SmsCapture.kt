package app.zaghlol.platform.capture

import android.content.Context
import androidx.annotation.VisibleForTesting
import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.ingest.safely
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * The SMS side of capture after `goAsync()` (T-040 design note sections 3
 * and 4): multipart assembly, the receive stamp, then [CaptureIntake] on the
 * `sms` channel. Runs on the SMS intake thread ([SmsCapture.dispatch]).
 */
class SmsIntake(
    private val intake: CaptureIntake,
    /** `Settings.Global.BOOT_COUNT`, -1 unknown (read here, off the main thread). */
    private val bootCount: () -> Int,
    private val trace: () -> IngestTrace = { IngestTrace.NONE },
) {
    fun process(parts: List<SmsPart>, wallMs: Long, rxElapsedNs: Long, simSlot: Int?): IntakeResult {
        trace().safely { received(rxElapsedNs) }
        val messages = SmsAssembler.assemble(parts).map { CapturedMessage(it.source, it.body) }
        if (messages.isEmpty()) return IntakeResult(emptyList(), refused = 0, dropped = 0, failed = 0, enqueued = false)
        val boot = try {
            bootCount()
        } catch (_: Exception) {
            -1
        }
        return intake.process(messages, ReceiveStamp(wallMs, rxElapsedNs, boot, simSlot))
    }

    override fun toString(): String = "SmsIntake"
}

/**
 * Process-wide entry for the SMS receiver (`src/sms`, T-040). The dispatcher
 * has **its own** daemon thread (`zaghlol-sms-intake`), SMS only, so a
 * notification burst (T-043, own thread) can't eat the SMS budget. The
 * intake is the [CaptureRuntime]'s, obtained on that thread (the runtime's
 * creation does file I/O, never on the receiver's main thread).
 */
object SmsCapture {
    val dispatch: BoundedDispatch by lazy { BoundedDispatch.daemon("sms") }

    /** FU-086 I-5: its own thread, so a stalled status write never delays the timer's `finish()`. */
    private val missedThread: Executor by lazy {
        Executors.newSingleThreadExecutor { r -> Thread(r, "zaghlol-sms-missed").apply { isDaemon = true } }
    }

    /**
     * FU-086 I-5: the `onAbandoned` of an SMS broadcast. The 5 s budget ended
     * the broadcast before the intake did, so the process may be killed with
     * the message unstored: record it as missed at its receive time
     * (`firstMissedSmsAtMs`), so the next catch-up starts at or before it even
     * after later SMS moved the watermark. A time only, never the sender or
     * the body. If the intake did finish after all, the catch-up just
     * re-reads a stored message and dedupes it.
     */
    fun missedRecorder(context: Context, wallMs: Long): () -> Unit = missedRecorder(missedThread, wallMs) { at ->
        CaptureRuntime.get(context).status.recordMissed(AndroidGuardChannel.SMS.wire, at)
    }

    internal fun missedRecorder(thread: Executor, wallMs: Long, record: (Long) -> Unit): () -> Unit = {
        try {
            thread.execute {
                try {
                    record(wallMs)
                } catch (_: Throwable) {
                    // Best effort: the catch-up still runs from the watermark on the next app open.
                }
            }
        } catch (_: Throwable) {
            // Executor gone: nothing to record with.
        }
    }

    @Volatile
    private var testIntake: SmsIntake? = null

    /** The intake the receiver uses now: the runtime's, or the one an instrumented test installed. */
    fun intake(context: Context): SmsIntake = testIntake ?: CaptureRuntime.get(context).sms

    /**
     * Instrumented tests only (`SmsReceiverEmulatorTest`): routes the real
     * receiver to [intake] (a test spool, Guard and scheduler) until the
     * returned handle is closed.
     */
    @VisibleForTesting
    fun installForTest(intake: SmsIntake): AutoCloseable {
        testIntake = intake
        return AutoCloseable { testIntake = null }
    }
}
