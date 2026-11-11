package app.zaghlol.spike.sms

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import app.zaghlol.platform.capture.AndroidCaptureHostApi
import app.zaghlol.platform.keys.SecretStoreRegistration
import com.github.dart_lang.jni.JniPlugin
import com.github.dart_lang.jni_flutter.JniFlutterPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The headless FlutterEngine of the spike (design note section 6). Main
 * thread only. One engine at a time per process; created from a process-wide
 * [FlutterEngineGroup] with entrypoint `ingestionMain`,
 * `automaticallyRegisterPlugins = false` and an explicit plugin allowlist:
 * - `JniPlugin` + `JniFlutterPlugin`: path_provider_android 2.3 is JNI-based
 *   (no PathProviderPlugin class exists); they give it the app context, so
 *   both engines resolve the same database directory (FU-065 S-7);
 * - `SecretStoreRegistration` (FU-065): the database key;
 * - the spool host (drain/ack; other capture methods NOT_AVAILABLE);
 * - the spike-only `zaghlol/spike_metrics` channel (not a contract).
 * Never started while the UI engine is attached.
 */
class HeadlessEngine(private val rt: SpikeRuntime) {
    private var group: FlutterEngineGroup? = null
    private var engine: FlutterEngine? = null
    private var host: SpoolHost? = null
    private var channel: BasicMessageChannel<Any>? = null
    private var ready: CompletableDeferred<Boolean>? = null
    private var current: SpikeMetrics.Cycle? = null
    private var pendingReply: CompletableDeferred<Any?>? = null
    private val destroyTask = Runnable { destroy() }
    private var trimRegistered = false

    @Volatile private var alive = false

    /** True when no headless engine exists (any thread). */
    fun isIdle(): Boolean = !alive

    /** Runs one drain cycle, starting the engine if needed. Never throws. */
    suspend fun runCycle(timeoutMs: Long, cycle: SpikeMetrics.Cycle): CycleOutcome {
        val reply = CompletableDeferred<Any?>()
        val outcome = withTimeoutOrNull(timeoutMs) {
            val readyNow = withContext(Dispatchers.Main) {
                rt.main.removeCallbacks(destroyTask)
                current = cycle
                ensureEngine()
            } ?: return@withTimeoutOrNull CycleOutcome.TIMEOUT
            if (!readyNow.await()) return@withTimeoutOrNull CycleOutcome.TIMEOUT
            withContext(Dispatchers.Main) {
                val ch = channel
                if (ch == null) {
                    reply.complete(null)
                } else {
                    pendingReply = reply
                    ch.send(mapOf("cmd" to "drain")) { reply.complete(it) }
                }
            }
            val r = reply.await() as? Map<*, *>
            CycleOutcome.parse(r?.get("result"))
        }
        SpikeLog.e(if (outcome == null) SpikeLog.Code.CYCLE_TIMEOUT else SpikeLog.Code.CYCLE_DONE)
        return outcome ?: CycleOutcome.TIMEOUT
    }

    /** Main thread. Destroys the engine after [lingerMs] (0 = now). */
    fun scheduleDestroy(lingerMs: Long) {
        rt.main.removeCallbacks(destroyTask)
        if (engine == null) return
        if (lingerMs <= 0) destroy() else rt.main.postDelayed(destroyTask, lingerMs)
    }

    /** Main thread. Also called when the UI engine attaches (never two writers). */
    fun destroy() {
        rt.main.removeCallbacks(destroyTask)
        val e = engine ?: return
        host?.detach()
        engine = null
        host = null
        channel = null
        ready?.complete(false)
        ready = null
        pendingReply?.complete(null) // the cycle is abandoned: RETRY, nothing acked
        pendingReply = null
        alive = false
        try {
            e.destroy()
        } catch (_: Exception) {
            // Engine teardown failure: nothing to keep.
        }
        SpikeLog.e(SpikeLog.Code.ENGINE_DESTROYED)
    }

    /** Main thread. Returns the readiness of the (new or existing) engine. */
    private fun ensureEngine(): CompletableDeferred<Boolean>? {
        ready?.let { return it }
        val signal = CompletableDeferred<Boolean>()
        ready = signal
        alive = true
        registerTrim()
        SpikeLog.e(SpikeLog.Code.ENGINE_START)
        val startNs = rt.clockNs()
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) loader.startInitialization(rt.app)
            loader.ensureInitializationCompleteAsync(rt.app, null, rt.main) {
                try {
                    if (ready !== signal) return@ensureInitializationCompleteAsync
                    start(loader.findAppBundlePath(), signal, startNs)
                } catch (_: Exception) {
                    SpikeLog.e(SpikeLog.Code.ENGINE_FAILED)
                    destroy()
                    signal.complete(false)
                }
            }
        } catch (_: Exception) {
            SpikeLog.e(SpikeLog.Code.ENGINE_FAILED)
            ready = null
            alive = false
            signal.complete(false)
        }
        return signal
    }

    private fun start(bundlePath: String, signal: CompletableDeferred<Boolean>, startNs: Long) {
        val g = group ?: FlutterEngineGroup(rt.app).also { group = it }
        val e = g.createAndRunEngine(
            FlutterEngineGroup.Options(rt.app)
                .setDartEntrypoint(DartExecutor.DartEntrypoint(bundlePath, ENTRYPOINT))
                .setAutomaticallyRegisterPlugins(false),
        )
        engine = e
        val messenger = e.dartExecutor.binaryMessenger
        e.plugins.add(JniPlugin())
        e.plugins.add(JniFlutterPlugin())
        SecretStoreRegistration.register(messenger, rt.app)
        val engineId = rt.engineIds.getAndIncrement()
        val h = SpoolHost(engineId, rt.store, rt.claim, rt.scheduler, rt.device, rt.metrics) { current }
        host = h
        AndroidCaptureHostApi.setUp(messenger, h)
        channel = metricsChannel(messenger, rt.metrics, { current }) {
            current?.dartReadyNs = rt.clockNs()
            SpikeLog.e(SpikeLog.Code.ENGINE_READY, (rt.clockNs() - startNs) / 1_000_000)
            signal.complete(true)
        }
    }

    private fun registerTrim() {
        if (trimRegistered) return
        trimRegistered = true
        rt.app.registerComponentCallbacks(object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                rt.main.post { if (engine != null && rt.claim.ownerOrNull() == null) destroy() }
            }

            override fun onConfigurationChanged(newConfig: Configuration) = Unit

            @Deprecated("Deprecated in Java")
            override fun onLowMemory() {
                rt.main.post { if (engine != null && rt.claim.ownerOrNull() == null) destroy() }
            }
        })
    }

    companion object {
        const val ENTRYPOINT = "ingestionMain"
        const val METRICS_CHANNEL = "zaghlol/spike_metrics"

        /**
         * Dart → native messages: `{ev: ready}`, `{ev: mark, stage, ids}`.
         * Only codes, stage names and ULIDs; anything else is ignored.
         */
        fun metricsChannel(
            messenger: BinaryMessenger,
            metrics: SpikeMetrics,
            cycle: () -> SpikeMetrics.Cycle?,
            onReady: () -> Unit,
        ): BasicMessageChannel<Any> {
            val ch = BasicMessageChannel<Any>(messenger, METRICS_CHANNEL, StandardMessageCodec.INSTANCE)
            ch.setMessageHandler { message, reply ->
                try {
                    val m = message as? Map<*, *>
                    when (m?.get("ev")) {
                        "ready" -> onReady()
                        "db_open" -> cycle()?.dbOpenNs = SpikeRuntime.peek()?.clockNs?.invoke() ?: -1
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
            return ch
        }
    }
}
