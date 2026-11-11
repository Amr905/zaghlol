package app.zaghlol.spike.sms

import androidx.work.BackoffPolicy
import androidx.work.OutOfQuotaPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

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
}
