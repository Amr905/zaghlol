package app.zaghlol.spike.sms

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.zaghlol.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * Expedited unique work `zaghlol.ingest` (design note section 5): no
 * constraints, `APPEND_OR_REPLACE`, exponential back-off from 10 s. On Android
 * 12+ it runs as an expedited job under App Standby quotas, or as regular
 * work when the quota is used up. It never calls `setForeground`.
 */
class WorkManagerScheduler(private val context: Context) : IngestScheduler {
    override fun enqueue() {
        WorkManager.getInstance(context)
            .enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, buildRequest())
    }

    companion object {
        const val UNIQUE_NAME = "zaghlol.ingest"
        const val BACKOFF_SECONDS = 10L

        fun buildRequest(): OneTimeWorkRequest =
            OneTimeWorkRequest.Builder(IngestionWorker::class.java)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
                .build()
    }
}

class IngestionWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val rt = SpikeRuntime.get(applicationContext)
        val startNs = rt.clockNs()
        SpikeLog.e(SpikeLog.Code.WORKER_START)
        val path = when {
            rt.uiEvents != null -> SpikeMetrics.Path.FOREGROUND
            !rt.headless.isIdle() -> SpikeMetrics.Path.WARM_ENGINE
            rt.processWokenBySms -> SpikeMetrics.Path.COLD_PROCESS
            else -> SpikeMetrics.Path.WARM_PROCESS
        }
        rt.processWokenBySms = false
        val cycle = SpikeMetrics.Cycle(path).also { it.workerNs = startNs }
        val env = object : DrainEnvironment {
            override fun pendingCount(): Int = try {
                rt.store.pendingCount()
            } catch (_: Exception) {
                0
            }

            override fun uiAttached(): Boolean = rt.uiEvents != null

            override fun notifyUi(pending: Int) {
                rt.uiCycle = cycle
                rt.notifyUiIfAttached()
            }

            override suspend fun runHeadlessCycle(timeoutMs: Long): CycleOutcome = rt.headless.runCycle(timeoutMs, cycle)

            override suspend fun pause(ms: Long) = delay(ms)

            override fun nowMs(): Long = rt.clockNs() / 1_000_000
        }
        val ok = try {
            DrainLoop(env).run()
        } catch (_: Exception) {
            false
        }
        withContext(Dispatchers.Main) { rt.headless.scheduleDestroy(rt.lingerMs()) }
        SpikeLog.e(if (ok) SpikeLog.Code.WORKER_SUCCESS else SpikeLog.Code.WORKER_RETRY, (rt.clockNs() - startNs) / 1_000_000)
        return if (ok) Result.success() else Result.retry()
    }

    /**
     * Android 8-11 only: expedited work falls back to a foreground service and
     * needs this notification. Low importance, no amounts or senders; text
     * from strings.xml (en/ar; PO approved the notification, Q4; copy in
     * copy-deck.md section 1.23).
     */
    override suspend fun getForegroundInfo(): ForegroundInfo =
        ForegroundInfo(NOTIFICATION_ID, captureNotification(applicationContext))

    companion object {
        const val NOTIFICATION_ID = 0x5A47
        const val CHANNEL_ID = "zaghlol_capture"

        /**
         * Security review L-1: hidden on the lock screen, so nobody near a
         * locked phone learns that (and when) a money movement arrived.
         */
        const val NOTIFICATION_VISIBILITY = Notification.VISIBILITY_SECRET

        fun captureNotification(context: Context): Notification {
            val nm = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm != null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        context.getString(R.string.native_android_captureChannelName),
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
            }
            return Notification.Builder(context, CHANNEL_ID)
                .setContentTitle(context.getString(R.string.native_android_captureNotifTitle))
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .setVisibility(NOTIFICATION_VISIBILITY)
                .build()
        }
    }
}
