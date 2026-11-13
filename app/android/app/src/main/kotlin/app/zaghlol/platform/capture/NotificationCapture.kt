package app.zaghlol.platform.capture

import android.content.Context
import androidx.annotation.VisibleForTesting
import app.zaghlol.platform.guard.AndroidGuardChannel

/** Process-wide entry for the listener (T-043); mirrors [SmsCapture]. */
object NotificationCapture {
    @Volatile
    private var dispatcher: NotificationDispatcher<NotificationItem>? = null

    @Volatile
    private var testIntake: NotificationIntake? = null

    /** The intake the listener uses now: the runtime's, or the one an instrumented test installed. */
    private fun intake(context: Context): NotificationIntake = testIntake ?: CaptureRuntime.get(context).notifications

    /** The dispatcher; its thread is started by the first submit. */
    fun dispatcher(context: Context): NotificationDispatcher<NotificationItem> {
        dispatcher?.let { return it }
        synchronized(this) {
            dispatcher?.let { return it }
            val app = context.applicationContext
            return NotificationDispatcher<NotificationItem>(
                onMissed = { n ->
                    CaptureRuntime.get(app).status.recordMissed(AndroidGuardChannel.NOTIFICATION.wire, System.currentTimeMillis(), n)
                },
                handler = { item -> intake(app).process(item.posted, item.wallMs, item.elapsedNs) },
            ).also { dispatcher = it }
        }
    }

    /** Instrumented tests only: routes the real listener to [intake] until the handle is closed. */
    @VisibleForTesting
    fun installForTest(intake: NotificationIntake): AutoCloseable {
        testIntake = intake
        return AutoCloseable { testIntake = null }
    }
}
