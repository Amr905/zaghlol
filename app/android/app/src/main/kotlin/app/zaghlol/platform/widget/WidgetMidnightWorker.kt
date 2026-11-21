package app.zaghlol.platform.widget

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/**
 * FU-206b: redraws the widget just after the next local midnight so the
 * days-to-payday line rolls ([WidgetView.secondaryAt] picks the line at
 * render time). One unique, non-expedited work item that re-arms itself; it
 * reads nothing but the clock and carries no data.
 */
class WidgetMidnightWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        SafeToSpendWidgetReceiver.refreshAll(applicationContext) // also re-arms
        return Result.success()
    }

    companion object {
        const val UNIQUE_NAME = "zaghlol.widget.midnight"

        /** Milliseconds from [nowMs] to 1 minute past the next local midnight. */
        fun delayToNextMidnightMs(nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): Long {
            val now = Instant.ofEpochMilli(nowMs).atZone(zone)
            val next = now.toLocalDate().plusDays(1).atStartOfDay(zone).plusMinutes(1)
            return Duration.between(now, next).toMillis().coerceAtLeast(60_000L)
        }

        fun schedule(context: Context) {
            val request = OneTimeWorkRequestBuilder<WidgetMidnightWorker>()
                .setInitialDelay(delayToNextMidnightMs(System.currentTimeMillis()), TimeUnit.MILLISECONDS)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.REPLACE, request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context.applicationContext).cancelUniqueWork(UNIQUE_NAME)
        }
    }
}
