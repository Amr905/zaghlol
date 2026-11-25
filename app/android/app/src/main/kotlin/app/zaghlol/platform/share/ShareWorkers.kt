package app.zaghlol.platform.share

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * The share intake's worker threads (FU-070 S1). A provider whose `getType`
 * or `openFile` never returns can hold a worker for good (the read is
 * cancelled at the deadline, but a provider may ignore the cancellation), so
 * there are [threads] workers, not one: one stuck provider does not block
 * the next share. At most [queue] shares wait; beyond that a share is refused
 * at once through [submit]'s `onRejected` (the caller maps it to
 * `unreadable`). A queued share past its deadline is refused by
 * [ShareIntake.accept]'s first deadline check, so waiting never extends it.
 * Pure Kotlin, so the rules are JVM-tested. Never logs.
 */
class ShareWorkers(
    threads: Int = THREADS,
    queue: Int = QUEUE,
    name: String = "zaghlol-share",
) {
    private val pool = ThreadPoolExecutor(
        threads,
        threads,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(queue),
        { r -> Thread(r, name).apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )

    /** Runs [task] on a worker, or calls [onRejected] on the caller's thread when no worker or queue slot is free. */
    fun submit(task: () -> Unit, onRejected: () -> Unit) {
        try {
            pool.execute(task)
        } catch (_: RejectedExecutionException) {
            onRejected()
        }
    }

    /** Tests only. */
    internal fun shutdownNow() {
        pool.shutdownNow()
    }

    companion object {
        const val THREADS = 2
        const val QUEUE = 8
    }
}
