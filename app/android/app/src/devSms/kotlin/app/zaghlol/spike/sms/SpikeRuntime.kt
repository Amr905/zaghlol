package app.zaghlol.spike.sms

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import app.zaghlol.R
import app.zaghlol.platform.capture.CaptureEventsApi
import app.zaghlol.platform.capture.IngestScheduler
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.KeystoreSpoolCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.SpoolKey
import app.zaghlol.platform.spool.SpoolStore
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Process-wide wiring of the SMS spike (devSms only). Every component the
 * receiver, worker and engines share lives here once per process: the spool
 * store (one writer lock), the drain claim, the metrics and the engine state.
 */
class SpikeRuntime private constructor(context: Context) {
    val app: Context = context.applicationContext
    val clockNs: () -> Long = SystemClock::elapsedRealtimeNanos
    val status = CaptureStatusStore(File(app.noBackupFilesDir, "capture/status.bin"), KeystoreSpoolCipher())
    val store = SpoolStore(
        dir = File(app.noBackupFilesDir, "spool"),
        cipher = KeystoreSpoolCipher(),
        status = status,
        keyCreatedAtMs = SpoolKey::creationDateMs,
        monoClockMs = SystemClock::elapsedRealtime,
    )
    val claim = SpoolClaim(clock = SystemClock::elapsedRealtime)
    val guard = SpikeGuard(listOfNotNull(app.getString(R.string.spike_tester_sender).takeIf { it.isNotBlank() }))
    val scheduler: IngestScheduler = WorkManagerScheduler(app)
    val device = AndroidCaptureDevice(app)
    val metrics = SpikeMetrics(
        file = File(app.noBackupFilesDir, "spike/metrics.csv"),
        bootCount = ::bootCount,
        conditions = { device.conditions(lingerMs()) },
        nanoClock = clockNs,
        processStartNs = { android.os.Process.getStartElapsedRealtime() * 1_000_000 },
    )
    val intake = SmsIntake(guard, store, scheduler, metrics, clockNs)
    val dispatch = BoundedDispatch(
        executor = Executors.newSingleThreadExecutor { r -> Thread(r, "zaghlol-sms-intake").apply { isDaemon = true } },
        timer = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "zaghlol-sms-timer").apply { isDaemon = true } },
    )
    val engineIds = AtomicLong(1)
    val headless = HeadlessEngine(this)

    /** Set by the first receive of a process started for it: a cold-process run. */
    @Volatile var processWokenBySms = false

    private val firstReceive = java.util.concurrent.atomic.AtomicBoolean(true)

    /**
     * Called by the receiver: the run is "cold process" when this is the
     * process's first receive, it started less than [COLD_START_WINDOW_MS]
     * before it, and no engine exists.
     */
    fun noteReceive(rxElapsedMs: Long) {
        if (!firstReceive.compareAndSet(true, false)) return
        val age = rxElapsedMs - android.os.Process.getStartElapsedRealtime()
        if (age in 0 until COLD_START_WINDOW_MS && headless.isIdle() && uiEvents == null) processWokenBySms = true
    }

    /** The UI engine's event API while MainActivity's engine is attached (main thread only). */
    @Volatile var uiEvents: CaptureEventsApi? = null

    @Volatile var uiMessenger: BinaryMessenger? = null

    /** The worker cycle the UI engine is draining for (foreground metrics). */
    @Volatile var uiCycle: SpikeMetrics.Cycle? = null

    val main = Handler(Looper.getMainLooper())

    fun bootCount(): Int = try {
        Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT, -1)
    } catch (_: Exception) {
        -1
    }

    /** Spike setting: engine linger after a drain (0 or 20 000 ms), from `no_backup/spike/linger_ms`. */
    fun lingerMs(): Long = try {
        File(app.noBackupFilesDir, "spike/linger_ms").takeIf { it.isFile }?.readText()?.trim()?.toLong()
            ?.coerceIn(0, 60_000) ?: 0L
    } catch (_: Exception) {
        0L
    }

    /** Receiver step 5 (platform-channels.md section 2): tell an attached UI engine. */
    fun notifyUiIfAttached() {
        main.post {
            val events = uiEvents ?: return@post
            events.onSpoolChanged(store.pendingCount().toLong()) { }
            SpikeLog.e(SpikeLog.Code.UI_NOTIFIED)
        }
    }

    companion object {
        const val COLD_START_WINDOW_MS = 5_000L

        @Volatile private var instance: SpikeRuntime? = null

        fun get(context: Context): SpikeRuntime =
            instance ?: synchronized(this) {
                instance ?: SpikeRuntime(context).also {
                    SpikeLog.enabled = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                    instance = it
                }
            }

        fun peek(): SpikeRuntime? = instance
    }
}
