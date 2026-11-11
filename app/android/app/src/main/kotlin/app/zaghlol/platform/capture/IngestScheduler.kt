package app.zaghlol.platform.capture

/**
 * Enqueues the expedited live ingestion work (platform-channels.md section 2;
 * T-041 `WorkManagerIngestScheduler`, every flavour). Injected so the host and
 * the intake stay JVM-testable. Receivers and listeners call
 * [CaptureRuntime.afterSpoolWrite] instead, which also notifies the UI engine.
 */
fun interface IngestScheduler {
    fun enqueue()
}
