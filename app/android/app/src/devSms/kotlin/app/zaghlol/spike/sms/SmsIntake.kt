package app.zaghlol.spike.sms

import java.util.concurrent.ExecutorService
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** One PDU as read from the intent. Never printed. */
class SmsPart(val address: String?, val body: String?, val timestampMs: Long) {
    override fun toString(): String = "SmsPart(<redacted>)"
}

/** A whole message after multipart assembly. Never printed. */
class AssembledSms(val source: String, val body: String, val sentAtMs: Long) {
    override fun toString(): String = "AssembledSms(<redacted>)"
}

/** What the receiver stamped when the broadcast arrived (t0). */
class ReceiveStamp(val wallMs: Long, val elapsedNs: Long, val bootCount: Int, val simSlot: Int?)

object SmsAssembler {
    /**
     * Groups the PDUs of one broadcast by originating address and joins their
     * bodies in PDU order (EC-09: a multipart SMS arrives as several PDUs of
     * one broadcast). Parts without an address are dropped.
     */
    fun assemble(parts: List<SmsPart>): List<AssembledSms> {
        val bySender = LinkedHashMap<String, Pair<StringBuilder, Long>>()
        for (p in parts) {
            val address = p.address?.takeIf { it.isNotEmpty() } ?: continue
            val slot = bySender.getOrPut(address) { StringBuilder() to p.timestampMs }
            slot.first.append(p.body.orEmpty())
        }
        return bySender.map { (address, v) -> AssembledSms(address, v.first.toString(), v.second) }
    }
}

/** Enqueues the expedited ingestion work. */
fun interface IngestScheduler {
    fun enqueue()
}

/**
 * The receiver's work after `goAsync()` (design note section 2): Guard, spool
 * write, enqueue. No engine, no parse, no DB.
 */
class SmsIntake(
    private val guard: SpikeGuard,
    private val store: SpoolStore,
    private val scheduler: IngestScheduler,
    private val metrics: SpikeMetrics?,
    private val nanoClock: () -> Long = System::nanoTime,
) {
    /** Returns the ids written. Throws only for unexpected errors (the caller still finishes). */
    fun process(messages: List<AssembledSms>, stamp: ReceiveStamp): List<String> {
        val written = ArrayList<String>()
        for (m in messages) {
            when (val d = guard.decide(SpikeGuard.CHANNEL_SMS, m.source, m.body)) {
                is SpikeGuard.Decision.Drop -> SpikeLog.e(SpikeLog.Code.RX_DROP)
                is SpikeGuard.Decision.Keep -> {
                    SpikeLog.e(SpikeLog.Code.RX_KEEP)
                    val record = SpoolRecord(
                        channel = SpikeGuard.CHANNEL_SMS,
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
                        store.write(record)
                    } catch (_: Exception) {
                        SpikeLog.e(SpikeLog.Code.SPOOL_WRITE_FAILED)
                        null
                    }
                    when (result) {
                        is SpoolStore.WriteResult.Written -> {
                            written += result.id
                            metrics?.spooled(result.id, stamp.elapsedNs, nanoClock())
                            SpikeLog.e(SpikeLog.Code.SPOOL_WRITTEN, (nanoClock() - stamp.elapsedNs) / 1_000_000)
                        }
                        SpoolStore.WriteResult.Full -> SpikeLog.e(SpikeLog.Code.SPOOL_FULL)
                        null -> Unit
                    }
                }
            }
        }
        if (written.isNotEmpty()) {
            try {
                scheduler.enqueue()
                val now = nanoClock()
                written.forEach { metrics?.enqueued(it, now) }
                SpikeLog.e(SpikeLog.Code.ENQUEUED, (now - stamp.elapsedNs) / 1_000_000)
            } catch (_: Exception) {
                // The entry stays spooled; the next enqueue or the UI engine drains it.
                SpikeLog.e(SpikeLog.Code.ENQUEUE_FAILED)
            }
        }
        if (messages.isEmpty()) SpikeLog.e(SpikeLog.Code.RX_EMPTY)
        return written
    }
}

/**
 * Runs [work] on [executor] and calls [finish] exactly once: when the work
 * ends (normally or by throwing) or after [budgetMs], whichever is first
 * (design note section 2: hard 5 s budget, then abandon and finish).
 */
class BoundedDispatch(
    private val executor: ExecutorService,
    private val timer: ScheduledExecutorService,
    private val budgetMs: Long = BUDGET_MS,
) {
    fun run(work: () -> Unit, finish: () -> Unit) {
        val done = AtomicBoolean(false)
        val finishOnce = {
            if (done.compareAndSet(false, true)) {
                try {
                    finish()
                } catch (_: Throwable) {
                    // finish() of an already-finished PendingResult; nothing to do.
                }
            }
        }
        val timeout = try {
            timer.schedule({
                if (!done.get()) SpikeLog.e(SpikeLog.Code.SPOOL_TIMEOUT, budgetMs)
                finishOnce()
            }, budgetMs, TimeUnit.MILLISECONDS)
        } catch (_: Throwable) {
            null
        }
        try {
            executor.execute {
                try {
                    work()
                } catch (_: Throwable) {
                    SpikeLog.e(SpikeLog.Code.SPOOL_WRITE_FAILED)
                } finally {
                    timeout?.cancel(false)
                    finishOnce()
                }
            }
        } catch (_: Throwable) {
            timeout?.cancel(false)
            finishOnce()
        }
    }

    companion object {
        const val BUDGET_MS = 5_000L
    }
}
