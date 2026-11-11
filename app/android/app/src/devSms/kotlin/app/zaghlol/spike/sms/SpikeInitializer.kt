package app.zaghlol.spike.sms

import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import androidx.startup.Initializer
import app.zaghlol.platform.capture.CaptureRuntime
import app.zaghlol.platform.ingest.HeadlessEngine
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.spool.UlidGenerator
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The devSms-only part of the T-008 spike that is left after T-040: the
 * latency recorder, measuring the **production** receiver (`src/sms`
 * `SmsReceiver`), Guard, spool, worker and engines through [IngestTrace].
 * T-040 replaced the spike receiver and `SpikeGuard`; in devSms the
 * production Guard decides with the base exported from the spike registry
 * (`src/devSms/assets/guard/spike_guard_base.json`, sender 5550100).
 */
class Spike private constructor(context: Context) {
    val app: Context = context.applicationContext
    val runtime: CaptureRuntime = CaptureRuntime.get(app)
    val clockNs: () -> Long = SystemClock::elapsedRealtimeNanos
    val metrics = SpikeMetrics(
        file = File(app.noBackupFilesDir, "spike/metrics.csv"),
        bootCount = ::bootCount,
        conditions = ::conditions,
        nanoClock = clockNs,
        processStartNs = { android.os.Process.getStartElapsedRealtime() * 1_000_000 },
    )
    val trace = SpikeTrace(
        metrics,
        clockNs,
        uiAttached = runtime::uiAttached,
        headlessIdle = runtime.headless::isIdle,
        processStartMs = { android.os.Process.getStartElapsedRealtime() },
    )

    fun bootCount(): Int = try {
        Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT, -1)
    } catch (_: Exception) {
        -1
    }

    /** Device conditions for a metrics row (no identifiers). */
    private fun conditions(): SpikeMetrics.Conditions {
        val pm = app.getSystemService(PowerManager::class.java)
        val bucket = if (Build.VERSION.SDK_INT >= 28) {
            try {
                app.getSystemService(UsageStatsManager::class.java)?.appStandbyBucket ?: -1
            } catch (_: Exception) {
                -1
            }
        } else {
            -1
        }
        return SpikeMetrics.Conditions(
            sdk = Build.VERSION.SDK_INT,
            batteryExempt = pm?.isIgnoringBatteryOptimizations(app.packageName) == true,
            deviceIdle = pm?.isDeviceIdleMode == true,
            standbyBucket = bucket,
            lingerMs = HeadlessEngine.LINGER_MS,
        )
    }

    companion object {
        @Volatile private var instance: Spike? = null

        fun get(context: Context): Spike =
            instance ?: synchronized(this) {
                instance ?: Spike(context).also {
                    SpikeLog.enabled = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                    it.runtime.trace = it.trace
                    instance = it
                }
            }
    }
}

/**
 * [IngestTrace] over [SpikeMetrics] (devSms). Path of a row: `foreground`
 * (drained by the UI engine), `warm_engine` (a headless engine was alive),
 * `cold_process` (the process was started for this SMS), else
 * `warm_process`. Receives ULIDs, flags and the record's timing numbers only.
 */
class SpikeTrace(
    private val metrics: SpikeMetrics,
    private val clockNs: () -> Long,
    private val uiAttached: () -> Boolean,
    private val headlessIdle: () -> Boolean,
    /** `Process.getStartElapsedRealtime()` (ms, same clock as the receive stamp); -1 unknown. */
    private val processStartMs: () -> Long = { -1L },
) : IngestTrace {
    /** Set by the first receive of a process started for it: a cold-process run. */
    @Volatile var processWokenBySms = false
    private val firstReceive = AtomicBoolean(true)

    @Volatile private var cycle: SpikeMetrics.Cycle? = null

    /**
     * The run is "cold process" when this is the process's first receive, it
     * started less than [COLD_START_WINDOW_MS] before it, and no engine exists.
     */
    fun noteReceive(rxElapsedMs: Long, processStartMs: Long) {
        if (!firstReceive.compareAndSet(true, false)) return
        if (processStartMs < 0) return
        val age = rxElapsedMs - processStartMs
        if (age in 0 until COLD_START_WINDOW_MS && headlessIdle() && !uiAttached()) processWokenBySms = true
    }

    /** T-040: the production receiver's intake (ULIDs and stamps only). */
    override fun received(rxElapsedNs: Long) {
        noteReceive(rxElapsedNs / 1_000_000, processStartMs())
        SpikeLog.e(SpikeLog.Code.RX_RECEIVED)
    }

    override fun spooled(id: String, rxElapsedNs: Long, rxWallMs: Long) {
        val now = clockNs()
        metrics.spooled(id, rxElapsedNs, now, rxWallMs)
        SpikeLog.e(SpikeLog.Code.SPOOL_WRITTEN, (now - rxElapsedNs) / 1_000_000)
    }

    override fun enqueued(ids: List<String>) {
        val now = clockNs()
        ids.forEach { metrics.enqueued(it, now) }
        SpikeLog.e(SpikeLog.Code.ENQUEUED)
    }

    override fun runStarted(foreground: Boolean, warmEngine: Boolean) {
        val path = when {
            foreground -> SpikeMetrics.Path.FOREGROUND
            warmEngine -> SpikeMetrics.Path.WARM_ENGINE
            processWokenBySms -> SpikeMetrics.Path.COLD_PROCESS
            else -> SpikeMetrics.Path.WARM_PROCESS
        }
        processWokenBySms = false
        cycle = SpikeMetrics.Cycle(path).also { it.workerNs = clockNs() }
        SpikeLog.e(SpikeLog.Code.WORKER_START)
    }

    override fun engineReady() {
        cycle?.dartReadyNs = clockNs()
        SpikeLog.e(SpikeLog.Code.ENGINE_READY)
    }

    override fun drained(id: String, rxElapsedNs: Long, bootCount: Int) {
        metrics.drained(id, rxElapsedNs, bootCount, currentCycle())
    }

    override fun acked(ids: List<String>) = metrics.mark("acked", ids)

    override fun engineAttached(messenger: BinaryMessenger) {
        marksChannel(messenger).setMessageHandler { message, reply ->
            try {
                val m = message as? Map<*, *>
                when (m?.get("ev")) {
                    "db_open" -> currentCycle().dbOpenNs = clockNs()
                    "mark" -> {
                        val stage = m["stage"] as? String
                        val ids = (m["ids"] as? List<*>)?.filterIsInstance<String>()?.filter(UlidGenerator::isValid)
                        if (stage != null && ids != null) metrics.mark(stage, ids)
                    }
                }
            } catch (_: Exception) {
                SpikeLog.e(SpikeLog.Code.METRICS_FAILED)
            }
            reply.reply(null)
        }
    }

    override fun engineDetached(messenger: BinaryMessenger) = marksChannel(messenger).setMessageHandler(null)

    /** While a UI engine is attached, drains come from it (no headless engine is started next to it). */
    private fun currentCycle(): SpikeMetrics.Cycle {
        val c = cycle
        if (uiAttached() && c?.path != SpikeMetrics.Path.FOREGROUND) {
            return SpikeMetrics.Cycle(SpikeMetrics.Path.FOREGROUND).also { cycle = it }
        }
        return c ?: SpikeMetrics.Cycle(SpikeMetrics.Path.WARM_PROCESS).also { cycle = it }
    }

    private fun marksChannel(messenger: BinaryMessenger) =
        BasicMessageChannel<Any>(messenger, MARKS_CHANNEL, StandardMessageCodec.INSTANCE)

    companion object {
        const val COLD_START_WINDOW_MS = 5_000L

        /** Dart → native stage marks (`spike_channel.dart`, devSms only): `{ev: db_open}`, `{ev: mark, stage, ids}`. */
        const val MARKS_CHANNEL = "zaghlol/spike_metrics"
    }
}

/** androidx.startup entry (declared in src/devSms/AndroidManifest.xml only): installs the spike trace. */
class SpikeInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        Spike.get(context)
    }

    override fun dependencies(): List<Class<out Initializer<*>>> = emptyList()
}
