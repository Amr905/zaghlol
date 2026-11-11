package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardDecision
import app.zaghlol.platform.guard.GuardDropReason
import app.zaghlol.platform.guard.GuardKeepKind
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.ingest.safely
import app.zaghlol.platform.spool.AdmissionClass
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.SpoolRecord
import app.zaghlol.platform.spool.SpoolStore

/** One message handed to the intake (sender and body as received). Never printed. */
class CapturedMessage(val source: String, val body: String) {
    override fun toString(): String = "CapturedMessage(<redacted>)"
}

/** What the receiver stamped when the broadcast arrived. Numbers only. */
class ReceiveStamp(val wallMs: Long, val elapsedNs: Long, val bootCount: Int, val simSlot: Int?) {
    override fun toString(): String = "ReceiveStamp(<redacted>)"
}

/**
 * The outcome of one batch: entry ids written (ULIDs) and counts. No
 * content; [toString] prints the counts only.
 */
class IntakeResult(val written: List<String>, val refused: Int, val dropped: Int, val failed: Int, val enqueued: Boolean) {
    override fun toString(): String = "IntakeResult(written=${written.size}, refused=$refused, dropped=$dropped, failed=$failed, enqueued=$enqueued)"
}

/**
 * Guard → spool → status → enqueue/notify for one capture channel (T-040
 * design note section 4; channel-agnostic, T-043 reuses it for
 * notifications). Runs on the channel's intake thread, never on the main
 * thread.
 *
 * Per message, `decide(channel, source, body)` (the process-wide
 * `GuardRuntime` with its one rate limiter):
 * - `Drop(rate_limited)` → `status.recordRateLimited(channel, wallMs)` (an SMS
 *   sets `firstMissedSmsAtMs` for the inbox catch-up).
 * - any other `Drop` → **nothing**: no file, no directory, no status write,
 *   no enqueue (a personal SMS leaves no trace).
 * - `Keep(kind)` → one [SpoolRecord], admission class `registry`/`user` →
 *   [AdmissionClass.PRIORITY], `generic` → [AdmissionClass.GENERIC]. A
 *   refusal is recorded by the store; a write failure (I/O, Keystore) is
 *   swallowed (counted, code-free) and nothing is enqueued for it.
 * After the batch, if anything was written **or refused**, [afterWrite]
 * (`CaptureRuntime.afterSpoolWrite`: enqueue the live work, notify an
 * attached UI engine) runs **once**; a refusal still enqueues, so the drain
 * runs (FU-084b). An enqueue failure is swallowed: the entry stays and the
 * next enqueue or app start drains it.
 *
 * Never logs; never puts a message, sender or record into a string or an
 * exception (design note section 9).
 */
class CaptureIntake(
    private val channel: AndroidGuardChannel,
    private val decide: (AndroidGuardChannel, String, String) -> GuardDecision,
    private val store: SpoolStore,
    private val status: CaptureStatusStore,
    private val afterWrite: () -> Unit,
    private val trace: () -> IngestTrace = { IngestTrace.NONE },
) {
    fun process(messages: List<CapturedMessage>, stamp: ReceiveStamp): IntakeResult {
        val written = ArrayList<String>(messages.size)
        var refused = 0
        var dropped = 0
        var failed = 0
        for (m in messages) {
            when (val d = decideSafely(m)) {
                is GuardDecision.Drop -> {
                    dropped++
                    if (d.reason == GuardDropReason.RATE_LIMITED) status.recordRateLimited(channel.wire, stamp.wallMs)
                }
                is GuardDecision.Keep -> {
                    val record = SpoolRecord(
                        channel = channel.wire,
                        source = m.source,
                        body = m.body,
                        receivedAtMs = stamp.wallMs,
                        simSlot = stamp.simSlot,
                        guardInst = d.inst,
                        guardLast4 = d.last4,
                        rxElapsedNs = stamp.elapsedNs,
                        bootCount = stamp.bootCount,
                    )
                    val result = try {
                        store.write(record, admissionOf(d.kind)).also { store.write(record, admissionOf(d.kind)) }
                    } catch (_: Exception) {
                        // I/O or Keystore: nothing written, nothing to drain for it.
                        null
                    }
                    when (result) {
                        is SpoolStore.WriteResult.Written -> {
                            written += result.id
                            trace().safely { spooled(result.id, stamp.elapsedNs, stamp.wallMs) }
                        }
                        is SpoolStore.WriteResult.Refused -> refused++ // recorded in the status by the store
                        null -> failed++
                    }
                }
            }
        }
        var scheduled = false
        if (written.isNotEmpty() || refused > 0) {
            scheduled = try {
                afterWrite()
                true
            } catch (_: Exception) {
                // The entries stay; the next enqueue or app start drains them.
                false
            }
            if (scheduled && written.isNotEmpty()) trace().safely { enqueued(written.toList()) }
        }
        return IntakeResult(written, refused, dropped, failed, scheduled)
    }

    /** The Guard never throws by contract; a defect is treated as a drop (fail closed). */
    private fun decideSafely(m: CapturedMessage): GuardDecision = try {
        decide(channel, m.source, m.body)
    } catch (_: Exception) {
        GuardDecision.Drop(GuardDropReason.CONFIG_INVALID)
    }

    override fun toString(): String = "CaptureIntake(${channel.wire})"

    companion object {
        /** Guard keep kind → spool admission class (T-039 design note section 4). */
        fun admissionOf(kind: GuardKeepKind): AdmissionClass = when (kind) {
            GuardKeepKind.REGISTRY, GuardKeepKind.USER -> AdmissionClass.PRIORITY
            GuardKeepKind.GENERIC -> AdmissionClass.GENERIC
        }
    }
}
