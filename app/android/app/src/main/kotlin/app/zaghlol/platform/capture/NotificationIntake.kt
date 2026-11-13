package app.zaghlol.platform.capture

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * The notification side of capture after the main-thread filter (T-043 design
 * note sections 4, 5 and 7), on the listener's own intake thread: package
 * admission **before any extras read**, extraction, the in-memory repeat
 * filter, then [CaptureIntake] on the `notification` channel (Guard → spool →
 * enqueue). A refused write is counted as a missed notification by the store,
 * a rate-limited one by [CaptureIntake]; neither is recovered (section 8).
 * Never logs; nothing here is put into a string.
 */
class NotificationIntake(
    private val admits: (packageName: String) -> Boolean,
    private val intake: CaptureIntake,
    private val recent: RecentNotifications,
    /** `Settings.Global.BOOT_COUNT` (-1 unknown), read here off the main thread. */
    private val bootCount: () -> Int = { -1 },
) {
    /** Null when nothing reached the Guard (not admitted, unreadable, blank, repeat). */
    fun process(posted: PostedNotification, wallMs: Long, rxElapsedNs: Long): IntakeResult? {
        val pkg = posted.packageName ?: return null
        if (!admits(pkg)) return null // extras are never touched for a package we don't read
        val body = NotificationExtractor.extract(posted.fields()) ?: return null
        if (recent.isRepeat(pkg, body)) return null
        val boot = try {
            bootCount()
        } catch (_: Exception) {
            -1
        }
        val result = intake.process(listOf(CapturedMessage(pkg, body)), ReceiveStamp(wallMs, rxElapsedNs, boot, null))
        if (result.written.isNotEmpty()) recent.remember(pkg, body)
        return result
    }

    override fun toString(): String = "NotificationIntake"
}

/** One posted notification and when it arrived (wall and monotonic clocks). Never printed. */
class NotificationItem(val posted: PostedNotification, val wallMs: Long, val elapsedNs: Long) {
    override fun toString(): String = "NotificationItem"
}

/**
 * One daemon thread with a bounded queue (T-043 design note section 3): a
 * burst of notifications can't consume the SMS receiver's `goAsync` budget
 * (the two meet only at the spool lock). On overflow the new item is dropped
 * and counted on the calling (main) thread; the intake thread reports the
 * count through [onMissed] before its next item, because that call may touch
 * the Keystore and must not run on the main thread.
 */
class NotificationDispatcher<T : Any>(
    private val capacity: Int = QUEUE_CAPACITY,
    private val onMissed: (count: Int) -> Unit,
    private val handler: (T) -> Unit,
    threadName: String = "zaghlol-notif-intake",
) {
    private val queue = ArrayBlockingQueue<T>(capacity)
    private val overflow = AtomicInteger()
    private val started = AtomicBoolean(false)
    private val thread = Thread(::loop, threadName).apply { isDaemon = true }

    /** Any thread, never blocks, no I/O. */
    fun submit(item: T) {
        if (started.compareAndSet(false, true)) thread.start()
        if (!queue.offer(item)) overflow.incrementAndGet()
    }

    private fun loop() {
        while (true) {
            flushMissed()
            val item = try {
                queue.take()
            } catch (_: InterruptedException) {
                return
            }
            try {
                handler(item)
            } catch (_: Throwable) {
                // Code-free by design: the intake swallows its own errors; this is the last net.
            }
        }
    }

    private fun flushMissed() {
        val n = overflow.getAndSet(0)
        if (n <= 0) return
        try {
            onMissed(n)
        } catch (_: Throwable) {
            // Counting is best effort (Keystore or I/O unavailable).
        }
    }

    override fun toString(): String = "NotificationDispatcher"

    companion object {
        const val QUEUE_CAPACITY = 64
    }
}
