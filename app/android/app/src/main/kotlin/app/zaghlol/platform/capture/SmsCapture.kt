package app.zaghlol.platform.capture

import android.content.Context
import androidx.annotation.VisibleForTesting
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.ingest.safely

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
