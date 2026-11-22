package app.zaghlol.platform.backupwork

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * FU-168e: the periodic backup wake-up. Native code only keeps time: the job
 * runs no Dart, reads no data and starts no service. When it fires it leaves
 * an empty "due" file; the app reads it (`takeDue`) and runs the Dart
 * BackupScheduleService, which checks the verified entitlement, the schedule
 * and the retry back-off. Battery rules: unmetered network, battery not low,
 * storage not low, a flex window so the system can batch it. Nothing logs.
 */
class BackupDueMark(private val file: File) {
    constructor(context: Context) : this(
        File(File(context.applicationContext.noBackupFilesDir, "backupwork"), "due"),
    )

    fun set() {
        file.parentFile?.mkdirs()
        file.createNewFile()
    }

    /** True once per [set]; the mark is cleared. */
    fun take(): Boolean = file.delete()

    fun clear() {
        file.delete()
    }
}

object BackupWorkPlan {
    const val UNIQUE_NAME = "zaghlol.backup.wake"
    val ALLOWED_DAYS = setOf(1, 7, 30)

    /** Flex window: a quarter of the period, at least the 15 minute WorkManager minimum. */
    fun flexMinutes(periodDays: Int): Long =
        maxOf(15L, TimeUnit.DAYS.toMinutes(periodDays.toLong()) / 4)
}

class BackupWorkHost(
    private val context: Context,
    private val mark: BackupDueMark = BackupDueMark(context),
) : BackupWorkHostApi {
    override fun schedule(periodDays: Long) {
        val days = periodDays.toInt()
        require(days in BackupWorkPlan.ALLOWED_DAYS) { "period" }
        val request = PeriodicWorkRequestBuilder<BackupWakeWorker>(
            days.toLong(), TimeUnit.DAYS,
            BackupWorkPlan.flexMinutes(days), TimeUnit.MINUTES,
        ).setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.UNMETERED)
                .setRequiresBatteryNotLow(true)
                .setRequiresStorageNotLow(true)
                .build(),
        ).build()
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniquePeriodicWork(BackupWorkPlan.UNIQUE_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    override fun cancel() {
        WorkManager.getInstance(context.applicationContext).cancelUniqueWork(BackupWorkPlan.UNIQUE_NAME)
        mark.clear()
    }

    override fun takeDue(): Boolean = mark.take()
}

class BackupWakeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        BackupDueMark(applicationContext).set()
        Result.success()
    } catch (_: java.io.IOException) {
        Result.retry()
    }
}
