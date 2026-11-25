package app.zaghlol.platform.share

import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * One share being ingested (F3). The outcome is set once, by the worker or by
 * the timeout, whichever comes first; the later one is ignored. It is handed
 * to the attached listener exactly once. A recreated [ShareActivity]
 * re-attaches by [id] instead of ingesting the same share again.
 *
 * [attach], [detach] and delivery all run on the thread behind [post] (the
 * main thread in production), so the listener that receives the outcome is
 * always the live activity. Pure Kotlin, so the rules are JVM-tested.
 */
class ShareJob(val id: String, private val post: (Runnable) -> Unit) {
    private var outcome: ShareOutcome? = null
    private var listener: ((ShareOutcome) -> Unit)? = null
    private var delivered = false
    private var committing = false
    private var abandoned = false

    /** Sets the outcome from any thread; false when one was already set. */
    fun complete(result: ShareOutcome): Boolean {
        synchronized(this) {
            if (outcome != null) return false
            outcome = result
        }
        post(Runnable { deliverIfReady() })
        return true
    }

    /**
     * FU-070 C3: the worker asks this right before it commits the encrypted
     * file. False when an outcome is already set (the give-up timer refused
     * the share): the worker must not commit. True marks the job as
     * committing, after which [giveUp] no longer sets an outcome; the
     * worker's own outcome follows the commit.
     */
    fun beginCommit(): Boolean = synchronized(this) {
        if (outcome != null) {
            false
        } else {
            committing = true
            true
        }
    }

    /** The give-up timer: sets [result] unless an outcome is set or a commit is in progress. */
    fun giveUp(result: ShareOutcome): Boolean {
        synchronized(this) {
            if (committing || outcome != null) return false
            outcome = result
        }
        post(Runnable { deliverIfReady() })
        return true
    }

    /**
     * FU-332: the commit watchdog. Unlike [giveUp] it applies while a commit is
     * in progress (a stalled Keystore call), and only then. Sets [result] and
     * marks the commit abandoned: if the worker's commit lands later, its
     * outcome is ignored by [complete] and the stored share is discarded by
     * [ShareJobs.finish], so the user sees exactly one outcome.
     */
    fun abandonCommit(result: ShareOutcome): Boolean {
        synchronized(this) {
            if (!committing || outcome != null) return false
            outcome = result
            abandoned = true
        }
        post(Runnable { deliverIfReady() })
        return true
    }

    /** True once [abandonCommit] set the outcome. */
    val commitAbandoned: Boolean
        get() = synchronized(this) { abandoned }

    /** Attaches the only listener (on the [post] thread); called at once when the outcome is already known. */
    fun attach(l: (ShareOutcome) -> Unit) {
        synchronized(this) { listener = l }
        deliverIfReady()
    }

    /** On the [post] thread, when the activity is destroyed. */
    fun detach() {
        synchronized(this) { listener = null }
    }

    val isDelivered: Boolean
        get() = synchronized(this) { delivered }

    private fun deliverIfReady() {
        val l: (ShareOutcome) -> Unit
        val o: ShareOutcome
        synchronized(this) {
            if (delivered) return
            l = listener ?: return
            o = outcome ?: return
            delivered = true
        }
        l(o)
    }
}

/** Live jobs in this process, by id. Ids carry a per-process random prefix, so a restored id never matches a new job. */
object ShareJobs {
    private val prefix: String = ByteArray(6).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
    private val next = AtomicLong(1)
    private val jobs = ConcurrentHashMap<String, ShareJob>()

    fun create(post: (Runnable) -> Unit): ShareJob =
        ShareJob("$prefix-${next.getAndIncrement()}", post).also { jobs[it.id] = it }

    fun get(id: String): ShareJob? = jobs[id]

    fun remove(id: String) {
        jobs.remove(id)
    }

    /**
     * Records the first outcome for [job]. A refusal also goes to
     * [ShareIntakeState], so Dart learns it even when no activity is left to
     * hand it over. Returns false when the job already had an outcome.
     */
    fun finish(job: ShareJob, outcome: ShareOutcome, discardLate: (String) -> Unit = {}): Boolean {
        val first = job.complete(outcome)
        if (first && outcome is ShareOutcome.Rejected) ShareIntakeState.setRejected(outcome.reason)
        // FU-332: a commit that landed after the watchdog gave up is not shown; its stored share is removed.
        if (!first && outcome is ShareOutcome.Accepted && job.commitAbandoned) {
            try {
                discardLate(outcome.descriptor.id)
            } catch (_: Exception) {
                // Best effort: the stale sweep removes it after STALE_AFTER_MS.
            }
        }
        return first
    }

    /** The commit watchdog's [finish] (FU-332): ends a commit that has stalled. */
    fun abandonCommit(job: ShareJob, outcome: ShareOutcome.Rejected): Boolean {
        val first = job.abandonCommit(outcome)
        if (first) ShareIntakeState.setRejected(outcome.reason)
        return first
    }

    /** The give-up timer's [finish] (FU-070 C3): yields to a commit in progress. */
    fun giveUp(job: ShareJob, outcome: ShareOutcome.Rejected): Boolean {
        val first = job.giveUp(outcome)
        if (first) ShareIntakeState.setRejected(outcome.reason)
        return first
    }
}
