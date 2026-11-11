package app.zaghlol.platform.ingest

import androidx.work.Data
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import app.zaghlol.platform.capture.IngestScheduler
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit
import kotlin.coroutines.cancellation.CancellationException

/**
 * The two unique works of the ingestion worker (T-041 design note section 3,
 * FU-081 F5). Both run [IngestionWorker], with **no constraints**.
 * - **Live** [LIVE]: expedited (`RUN_AS_NON_EXPEDITED_WORK_REQUEST`),
 *   `APPEND_OR_REPLACE`; enqueued after every spool write (also a refused
 *   one) and by `scheduleIngestionNow`. It never returns a WorkManager retry,
 *   so its head is never parked in back-off and a new message never waits
 *   behind one.
 * - **Retry** [RETRY]: not expedited, initial delay [retryDelayMs], input
 *   [KEY_ATTEMPT] = n (a number, no content), at most [MAX_ATTEMPTS].
 */
object IngestWork {
    const val LIVE = "zaghlol.ingest"
    const val RETRY = "zaghlol.ingest.retry"
    const val KEY_ATTEMPT = "attempt"
    const val MAX_ATTEMPTS = 8
    const val FIRST_RETRY_DELAY_MS = 10_000L
    const val MAX_RETRY_DELAY_MS = 15 * 60_000L

    /** `min(10 s × 2^(n−1), 15 min)`: 10, 20, 40, 80, 160, 320, 640, 900 s. */
    fun retryDelayMs(attempt: Int): Long {
        var d = FIRST_RETRY_DELAY_MS
        repeat((attempt - 1).coerceIn(0, 30)) { d = minOf(d * 2, MAX_RETRY_DELAY_MS) }
        return minOf(d, MAX_RETRY_DELAY_MS)
    }

    fun liveRequest(): OneTimeWorkRequest =
        OneTimeWorkRequest.Builder(IngestionWorker::class.java)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()

    fun retryRequest(attempt: Int): OneTimeWorkRequest =
        OneTimeWorkRequest.Builder(IngestionWorker::class.java)
            .setInitialDelay(retryDelayMs(attempt), TimeUnit.MILLISECONDS)
            .setInputData(Data.Builder().putInt(KEY_ATTEMPT, attempt).build())
            .build()
}

/** Enqueues the live work ([IngestScheduler.enqueue]) and manages the retry work. */
interface IngestWorkQueue : IngestScheduler {
    /**
     * Enqueues retry [attempt]. From a live run ([fromRetryRun] false) with
     * `KEEP`: a retry already waiting keeps its back-off. From a retry run with
     * `APPEND_OR_REPLACE`: the running retry work counts as unfinished, so
     * `KEEP` would drop its successor; appended, the successor starts (with its
     * delay) when this run has succeeded.
     */
    fun enqueueRetry(attempt: Int, fromRetryRun: Boolean)

    fun cancelRetry()
}

/**
 * One worker run (T-041 design note section 3), JVM-testable. A process-wide
 * [mutex] lets one run at a time, so a live and a retry run never interleave
 * cycles. The run itself always ends as WorkManager `success`; only the
 * retry work carries a back-off:
 * - [RunResult.EMPTY] → a live run cancels the retry work (a retry run is
 *   that work, and has no successor);
 * - [RunResult.NO_RETRY] → nothing;
 * - [RunResult.RETRY] → retry `attempt + 1` (1 after a live run), stopping
 *   after [IngestWork.MAX_ATTEMPTS]; the next live enqueue or app open resumes.
 * [afterRun] always runs (also when the work is stopped and the coroutine
 * cancelled): it schedules the headless engine's shutdown, never a destroy.
 */
class IngestRun(
    private val mutex: Mutex,
    private val queue: IngestWorkQueue,
    private val loop: () -> DrainLoop,
    private val afterRun: (stopped: Boolean) -> Unit,
) {
    /** [attempt]: 0 for the live work, n for retry n. Throws only [CancellationException]. */
    suspend fun run(attempt: Int): RunResult = mutex.withLock {
        var stopped = false
        try {
            val result = try {
                loop().run()
            } catch (e: CancellationException) {
                stopped = true
                throw e
            } catch (_: Exception) {
                RunResult.RETRY
            }
            when (result) {
                RunResult.EMPTY -> if (attempt == 0) quietly { queue.cancelRetry() }
                RunResult.NO_RETRY -> Unit
                RunResult.RETRY -> {
                    val next = attempt + 1
                    if (next <= IngestWork.MAX_ATTEMPTS) quietly { queue.enqueueRetry(next, fromRetryRun = attempt > 0) }
                }
            }
            result
        } finally {
            withContext(NonCancellable) { quietly { afterRun(stopped) } }
        }
    }

    private inline fun quietly(block: () -> Unit) {
        try {
            block()
        } catch (_: Exception) {
            // WorkManager unavailable: the next enqueue or app open resumes.
        }
    }
}
