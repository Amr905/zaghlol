package app.zaghlol.platform.capture

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Runs a receiver's work off the main thread under `goAsync()` and calls
 * `finish` **exactly once** (T-040 design note section 3; ported from the
 * T-008 spike): when the work ends (normally or by throwing), when
 * [budgetMs] has passed, or at once when the executor rejects the work.
 * Past the budget the work is abandoned, not interrupted: the spool write is
 * atomic (a whole entry or none), and a message lost to a process kill after
 * `finish()` is recovered by the inbox catch-up (FU-088). Nothing is logged.
 *
 * FU-086 I-5: when the budget (or an executor rejection) finishes the
 * broadcast **before** the work did, [run]'s `onAbandoned` is called once,
 * after `finish`, so the caller can record the message as possibly missed.
 * It is not called when the work finished first. It runs on the timer thread
 * (or the caller's, on rejection): a caller whose callback can block must
 * hand it to its own thread, so later broadcasts' `finish` is never delayed.
 */
class BoundedDispatch(
    private val executor: ExecutorService,
    private val timer: ScheduledExecutorService,
    private val budgetMs: Long = BUDGET_MS,
) {
    fun run(work: () -> Unit, onAbandoned: (() -> Unit)? = null, finish: () -> Unit) {
        val done = AtomicBoolean(false)
        val finishOnce = {
            if (done.compareAndSet(false, true)) {
                try {
                    finish()
                } catch (_: Throwable) {
                    // finish() of an already-finished PendingResult; nothing to do.
                }
                true
            } else {
                false
            }
        }
        val abandon = {
            if (finishOnce() && onAbandoned != null) {
                try {
                    onAbandoned()
                } catch (_: Throwable) {
                    // A record of a miss must never break the receiver.
                }
            }
        }
        val timeout = try {
            timer.schedule({ abandon() }, budgetMs, TimeUnit.MILLISECONDS)
        } catch (_: Throwable) {
            null
        }
        try {
            executor.execute {
                try {
                    work()
                } catch (_: Throwable) {
                    // Code-free by design: the work swallows its own errors; this is the last net.
                } finally {
                    timeout?.cancel(false)
                    finishOnce()
                }
            }
        } catch (_: Throwable) {
            timeout?.cancel(false)
            abandon()
        }
    }

    override fun toString(): String = "BoundedDispatch"

    companion object {
        /** The receiver's budget (a broadcast receiver has ~10 s before ANR; half of it). */
        const val BUDGET_MS = 5_000L

        /** One daemon intake thread plus one daemon timer thread, named for [channel]. */
        fun daemon(channel: String): BoundedDispatch = BoundedDispatch(
            executor = Executors.newSingleThreadExecutor { r -> Thread(r, "zaghlol-$channel-intake").apply { isDaemon = true } },
            timer = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "zaghlol-$channel-timer").apply { isDaemon = true } },
        )
    }
}
