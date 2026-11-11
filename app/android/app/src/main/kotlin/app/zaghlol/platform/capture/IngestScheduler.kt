package app.zaghlol.platform.capture

/**
 * Enqueues the expedited ingestion work (platform-channels.md section 2).
 * Injected so the host and the intake stay JVM-testable; the WorkManager
 * implementation is devSms-only until T-041.
 */
fun interface IngestScheduler {
    fun enqueue()
}
