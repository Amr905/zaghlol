package app.zaghlol.platform.ingest

import android.app.Notification
import androidx.work.NetworkType
import androidx.work.OutOfQuotaPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** T-041 design note section 3 (FU-081 F5): the shape of the live and retry work requests. */
class WorkRequestTest {
    private fun noConstraints(spec: androidx.work.impl.model.WorkSpec) {
        val c = spec.constraints
        assertFalse(c.requiresBatteryNotLow() || c.requiresCharging() || c.requiresStorageNotLow() || c.requiresDeviceIdle())
        assertEquals(NetworkType.NOT_REQUIRED, c.requiredNetworkType)
        assertEquals(IngestionWorker::class.java.name, spec.workerClassName)
    }

    @Test
    fun liveWorkIsExpeditedWithFallbackNoDelayNoConstraints() {
        val spec = IngestWork.liveRequest().workSpec
        assertTrue(spec.expedited)
        assertEquals(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST, spec.outOfQuotaPolicy)
        assertEquals(0L, spec.initialDelay)
        assertEquals("no attempt input: a live run", 0, spec.input.getInt(IngestWork.KEY_ATTEMPT, 0))
        noConstraints(spec)
        assertEquals("zaghlol.ingest", IngestWork.LIVE)
    }

    @Test
    fun retryWorkIsDelayedNotExpeditedAndCarriesOnlyTheAttemptNumber() {
        val spec = IngestWork.retryRequest(3).workSpec
        assertFalse(spec.expedited)
        assertEquals(40_000L, spec.initialDelay)
        assertEquals(3, spec.input.getInt(IngestWork.KEY_ATTEMPT, 0))
        assertEquals(setOf(IngestWork.KEY_ATTEMPT), spec.input.keyValueMap.keys)
        noConstraints(spec)
        assertEquals("zaghlol.ingest.retry", IngestWork.RETRY)
    }

    @Test
    fun backOffSeriesIsTenSecondsDoublingUpToFifteenMinutes() {
        val series = (1..IngestWork.MAX_ATTEMPTS).map { IngestWork.retryDelayMs(it) / 1_000 }
        assertEquals(listOf(10L, 20L, 40L, 80L, 160L, 320L, 640L, 900L), series)
        assertEquals(900_000L, IngestWork.retryDelayMs(40))
        assertEquals(8, IngestWork.MAX_ATTEMPTS)
    }

    /** The policies live in WorkManagerIngestScheduler (Android-only); checked at the source. */
    @Test
    fun uniqueWorkPolicies() {
        val src = File("src/main/kotlin/app/zaghlol/platform/ingest/IngestionWorker.kt").readText()
        assertTrue(src.contains("enqueueUniqueWork(IngestWork.LIVE, ExistingWorkPolicy.APPEND_OR_REPLACE, IngestWork.liveRequest())"))
        assertTrue(src.contains("if (fromRetryRun) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP"))
        assertTrue(src.contains("cancelUniqueWork(IngestWork.RETRY)"))
        assertFalse("REPLACE would cancel a running drain on every SMS", Regex("ExistingWorkPolicy\\.REPLACE\\b").containsMatchIn(src))
    }

    /** F5: the worker never returns Result.retry() and never calls setForeground. */
    @Test
    fun theWorkerNeverRetriesOrStartsAForegroundServiceItself() {
        val dir = File("src/main/kotlin/app/zaghlol/platform/ingest")
        for (f in dir.listFiles()!!.filter { it.extension == "kt" }) {
            val text = f.readText()
            assertFalse("${f.name}: Result.retry", text.contains("Result.retry("))
            assertFalse("${f.name}: setForeground", Regex("\\bsetForeground(Async)?\\(").containsMatchIn(text))
            assertFalse("${f.name}: Log", Regex("\\bLog\\.[a-z]+\\(|println\\(|printStackTrace|System\\.(out|err)").containsMatchIn(text))
            assertFalse("${f.name}: VISIBILITY_PUBLIC", text.contains("VISIBILITY_PUBLIC"))
        }
        val worker = File(dir, "IngestionWorker.kt").readText()
        assertTrue(worker.contains("return Result.success()"))
    }

    /** Security L-1, FU-093 N1: the API 26-30 capture notification is secret on the notification and its channel. */
    @Test
    fun captureNotificationAndChannelAreSecretOnTheLockScreen() {
        assertEquals(Notification.VISIBILITY_SECRET, IngestionWorker.NOTIFICATION_VISIBILITY)
        val worker = File("src/main/kotlin/app/zaghlol/platform/ingest/IngestionWorker.kt").readText()
        assertTrue(worker.contains(".setVisibility(NOTIFICATION_VISIBILITY)"))
        assertTrue(worker.contains("lockscreenVisibility = NOTIFICATION_VISIBILITY"))
        assertTrue(worker.contains("NotificationManager.IMPORTANCE_LOW"))
    }

    @Test
    fun notificationStringsExistInEnglishAndArabicInEveryFlavour() {
        for (dir in listOf("values", "values-ar")) {
            val text = File("src/main/res/$dir/capture_strings.xml").readText()
            assertTrue(dir, text.contains("name=\"native_android_captureChannelName\""))
            assertTrue(dir, text.contains("name=\"native_android_captureNotifTitle\""))
        }
    }
}
