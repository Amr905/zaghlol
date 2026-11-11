package app.zaghlol.platform.ingest

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Looper
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.zaghlol.R
import app.zaghlol.platform.capture.CaptureRuntime
import java.util.concurrent.TimeUnit

/**
 * [IngestWorkQueue] over WorkManager (T-041 design note section 3). [enqueue]
 * waits (bounded) until WorkManager has persisted the request when it is
 * called off the main thread (a receiver's `goAsync()` window), so a process
 * killed right after still runs the work; on the main thread it never blocks.
 */
class WorkManagerIngestScheduler(private val context: Context) : IngestWorkQueue {
    override fun enqueue() {
        val op = WorkManager.getInstance(context)
            .enqueueUniqueWork(IngestWork.LIVE, ExistingWorkPolicy.APPEND_OR_REPLACE, IngestWork.liveRequest())
        if (Looper.myLooper() != Looper.getMainLooper()) op.result.get(PERSIST_WAIT_MS, TimeUnit.MILLISECONDS)
    }

    override fun enqueueRetry(attempt: Int, fromRetryRun: Boolean) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            IngestWork.RETRY,
            if (fromRetryRun) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP,
            IngestWork.retryRequest(attempt),
        )
    }

    override fun cancelRetry() {
        WorkManager.getInstance(context).cancelUniqueWork(IngestWork.RETRY)
    }

    private companion object {
        const val PERSIST_WAIT_MS = 2_000L
    }
}

/**
 * The ingestion worker (T-041), every flavour. Drains the spool through the
 * UI engine (when attached) or the headless engine, within 60 s; see
 * [IngestRun] and [DrainLoop]. Always returns `success` (FU-081 F5): the back-off
 * lives in the separate retry work. Never calls `setForeground`.
 *
 * API 31+: WorkManager runs the expedited live work as an expedited job
 * (standby-bucket quota; out of quota → a regular job) and never calls
 * [getForegroundInfo]. API 26-30: expedited work falls back to a foreground
 * service and needs [getForegroundInfo]; no foreground-service type is
 * declared (WorkManager's `SystemForegroundService` has none, and the app
 * never starts a foreground service from the background itself).
 */
class IngestionWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val attempt = inputData.getInt(IngestWork.KEY_ATTEMPT, 0).coerceIn(0, IngestWork.MAX_ATTEMPTS)
        CaptureRuntime.get(applicationContext).ingest.run(attempt)
        return Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo =
        ForegroundInfo(NOTIFICATION_ID, captureNotification(applicationContext))

    companion object {
        const val NOTIFICATION_ID = 0x5A47
        const val CHANNEL_ID = "zaghlol_capture"

        /**
         * Security review L-1, FU-093 N1: hidden on the lock screen, on the
         * notification and on its channel, so nobody near a locked phone
         * learns that (and when) a money movement arrived.
         */
        const val NOTIFICATION_VISIBILITY = Notification.VISIBILITY_SECRET

        /**
         * Low importance, no amounts or senders; text from
         * `capture_strings.xml` (en/ar; PO approved the notification, T-008
         * Q4; copy in copy-deck.md section 1.23).
         */
        fun captureNotification(context: Context): Notification {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(captureChannel(context.getString(R.string.native_android_captureChannelName)))
            return Notification.Builder(context, CHANNEL_ID)
                .setContentTitle(context.getString(R.string.native_android_captureNotifTitle))
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .setVisibility(NOTIFICATION_VISIBILITY)
                .build()
        }

        fun captureChannel(name: String): NotificationChannel =
            NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW).apply {
                lockscreenVisibility = NOTIFICATION_VISIBILITY
            }
    }
}
