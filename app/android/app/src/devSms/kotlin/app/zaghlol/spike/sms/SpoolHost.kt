package app.zaghlol.spike.sms

import app.zaghlol.platform.capture.AndroidCaptureHostApi
import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.capture.CaptureCapabilities
import app.zaghlol.platform.capture.CaptureDevice
import app.zaghlol.platform.capture.InboxPage
import app.zaghlol.platform.capture.InboxQuery
import app.zaghlol.platform.capture.IngestScheduler
import app.zaghlol.platform.capture.SpoolEntry
import app.zaghlol.platform.capture.SpoolStatus
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.SpoolStore

/**
 * [AndroidCaptureHostApi] for one engine (UI or headless), devSms spike
 * (T-041 replaces it with app.zaghlol.platform.capture.AndroidCaptureHost).
 * Implements the spool methods, scheduling, battery status and capabilities;
 * everything else answers `NOT_AVAILABLE` (owner tasks in capture_api.dart).
 *
 * Errors: every method catches everything and throws
 * `CaptureApiError(code, null, null)`, so Pigeon never puts `toString()` or a
 * stack trace into the reply (FU-034). Codes: platform-channels.md section 6.
 */
class SpoolHost(
    private val engineId: Long,
    private val store: SpoolStore,
    private val claim: SpoolClaim,
    private val scheduler: IngestScheduler,
    private val device: CaptureDevice,
    private val metrics: SpikeMetrics?,
    private val cycle: () -> SpikeMetrics.Cycle?,
) : AndroidCaptureHostApi {

    override fun getCapabilities(): CaptureCapabilities = guarded { device.capabilities() }

    override fun requestSmsPermission(callback: (Result<Boolean>) -> Unit) {
        // T-040 owns the runtime request (with the Flutter rationale UI). For the
        // spike, grant with `adb shell pm grant <pkg> android.permission.RECEIVE_SMS`.
        callback(Result.failure(CaptureApiError(NOT_AVAILABLE, null, null)))
    }

    override fun openNotificationAccessSettings(): Unit = notAvailable()

    override fun isIgnoringBatteryOptimizations(): Boolean = guarded { device.isIgnoringBatteryOptimizations() }

    override fun requestIgnoreBatteryOptimizations(): Unit = guarded { device.openBatteryOptimizationSettings() }

    override fun writeGuardConfig(userConfigJson: ByteArray): Unit = notAvailable()

    override fun queryInbox(query: InboxQuery): InboxPage = notAvailable()

    /**
     * Oldest first, at most [max] (clamped to 1..[MAX_DRAIN]). Returns an empty
     * list while another engine holds the drain claim. Entries that can't be
     * read now are skipped and kept; entries proven not authentic are deleted
     * (counted, never returned).
     */
    override fun drainSpool(max: Long): List<SpoolEntry> = guarded {
        store.sweepTmp()
        if (!claim.acquire(engineId)) return@guarded emptyList()
        val limit = max.coerceIn(1, MAX_DRAIN.toLong()).toInt()
        val out = ArrayList<SpoolEntry>(limit)
        val currentCycle = cycle()
        for (id in store.pendingIds()) {
            if (out.size >= limit) break
            when (val r = store.read(id)) {
                is SpoolStore.ReadResult.Ok -> {
                    val rec = r.record
                    out += SpoolEntry(id, rec.channel, rec.source, rec.body, rec.receivedAtMs, rec.simSlot?.toLong())
                    metrics?.drained(id, rec.rxElapsedNs, rec.bootCount, currentCycle)
                }
                SpoolStore.ReadResult.Deleted -> SpikeLog.e(SpikeLog.Code.SPOOL_DECRYPT_FAILED)
                is SpoolStore.ReadResult.Unavailable -> SpikeLog.e(SpikeLog.Code.SPOOL_READ_DEFERRED)
                SpoolStore.ReadResult.Missing -> Unit
            }
        }
        claim.hold(engineId, out.map { it.id })
        out
    }

    /** Idempotent. Called by Dart only after the DB commit returned. */
    override fun ackSpool(ids: List<String>): Unit = guarded {
        if (ids.size > MAX_DRAIN) throw CaptureApiError(IO_ERROR, null, null)
        store.ack(ids)
        claim.acked(engineId, ids)
        metrics?.mark("acked", ids)
    }

    override fun scheduleIngestionNow(): Unit = guarded { scheduler.enqueue() }

    // The production AndroidCaptureHost (T-039) implements the status; T-041 replaces this spike host.
    override fun getSpoolStatus(): SpoolStatus = notAvailable()

    override fun clearSpoolAlerts(seq: Long): Unit = notAvailable()

    override fun holdSpool(ids: List<String>): Unit = notAvailable()

    /** The engine is going away: drop its claim. */
    fun detach() {
        claim.release(engineId)
    }

    private fun <T> notAvailable(): T = throw CaptureApiError(NOT_AVAILABLE, null, null)

    private inline fun <T> guarded(block: () -> T): T = try {
        block()
    } catch (e: CaptureApiError) {
        throw CaptureApiError(e.code, null, null)
    } catch (_: Throwable) {
        SpikeLog.e(SpikeLog.Code.HOST_ERROR)
        throw CaptureApiError(IO_ERROR, null, null)
    }

    companion object {
        const val MAX_DRAIN = 100
        const val NOT_AVAILABLE = "NOT_AVAILABLE"
        const val IO_ERROR = "IO_ERROR"
    }
}
