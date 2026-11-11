package app.zaghlol.platform.ingest

import io.flutter.plugin.common.BinaryMessenger

/**
 * Timing seam of the ingestion path (T-041 design note section 1). Production
 * uses [NONE]; the devSms build registers the spike's latency recorder
 * (`SpikeMetrics`) so `sms-spike` keeps measuring the production worker.
 *
 * Never logged (section 10): every call carries ULIDs, stage names, flags or
 * numbers taken from the record's diagnostic timing fields, never a body,
 * sender, amount or anything derived from them. Implementations must not
 * throw; callers still guard every call.
 */
interface IngestTrace {
    /** T-040: a capture broadcast arrived (receive stamp on `elapsedRealtimeNanos`). */
    fun received(rxElapsedNs: Long) {}

    /** T-040: the intake wrote entry [id] (receive stamps of its record). */
    fun spooled(id: String, rxElapsedNs: Long, rxWallMs: Long) {}

    /** T-040: the live work was enqueued for [ids] (after their spool writes). */
    fun enqueued(ids: List<String>) {}

    /** A worker run starts. [foreground]: a UI engine is attached; [warmEngine]: a headless engine exists. */
    fun runStarted(foreground: Boolean, warmEngine: Boolean) {}

    /** The headless engine's Dart side is ready (`HeadlessIngestionHostApi.ready`). */
    fun engineReady() {}

    /** The host handed entry [id] to an engine (receive stamps from the record). */
    fun drained(id: String, rxElapsedNs: Long, bootCount: Int) {}

    /** The host deleted [ids] after Dart's ack. */
    fun acked(ids: List<String>) {}

    /** An engine (UI or headless) was set up; devSms registers its marks channel here. */
    fun engineAttached(messenger: BinaryMessenger) {}

    fun engineDetached(messenger: BinaryMessenger) {}

    companion object {
        val NONE: IngestTrace = object : IngestTrace {}
    }
}

/** Calls [block] on [trace], swallowing anything: timing must never break capture. */
internal inline fun IngestTrace.safely(block: IngestTrace.() -> Unit) {
    try {
        block()
    } catch (_: Throwable) {
        // Diagnostics only.
    }
}
