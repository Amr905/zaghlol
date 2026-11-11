package app.zaghlol.spike.sms

import android.app.Notification
import androidx.work.BackoffPolicy
import androidx.work.OutOfQuotaPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class WorkRequestTest {
    @Test
    fun expeditedWithFallbackBackoffAndNoConstraints() {
        val spec = WorkManagerScheduler.buildRequest().workSpec
        assertTrue(spec.expedited)
        assertEquals(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST, spec.outOfQuotaPolicy)
        assertEquals(BackoffPolicy.EXPONENTIAL, spec.backoffPolicy)
        assertEquals(10_000L, spec.backoffDelayDuration)
        assertEquals(0L, spec.initialDelay)
        val c = spec.constraints
        assertFalse(c.requiresBatteryNotLow() || c.requiresCharging() || c.requiresStorageNotLow() || c.requiresDeviceIdle())
        assertEquals(androidx.work.NetworkType.NOT_REQUIRED, c.requiredNetworkType)
        assertEquals(IngestionWorker::class.java.name, spec.workerClassName)
        assertEquals("zaghlol.ingest", WorkManagerScheduler.UNIQUE_NAME)
    }

    /** Security L-1: the Android 8-11 capture notification is hidden on the lock screen. */
    @Test
    fun captureNotificationIsSecretOnTheLockScreen() {
        assertEquals(Notification.VISIBILITY_SECRET, IngestionWorker.NOTIFICATION_VISIBILITY)
        val dir = File("src/devSms/kotlin/app/zaghlol/spike")
        for (f in dir.walkTopDown().filter { it.isFile && it.extension == "kt" }) {
            assertFalse(f.name, f.readText().contains("VISIBILITY_PUBLIC"))
        }
        val worker = File(dir, "sms/IngestionWorker.kt").readText()
        assertTrue(worker.contains(".setVisibility(NOTIFICATION_VISIBILITY)"))
    }
}
