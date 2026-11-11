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
 *
 * Shutdown (review F1) goes through [ShutdownSequence]: a pending drain is
 * waited for, Dart closes the database (`close` command), then the engine is
 * destroyed. A cycle requested meanwhile waits until the old engine is gone.
 */
class HeadlessEngine(private val rt: SpikeRuntime) {
    private var group: FlutterEngineGroup? = null
    private var engine: FlutterEngine? = null
    private var host: SpoolHost? = null
    private var channel: BasicMessageChannel<Any>? = null
    private var ready: CompletableDeferred<Boolean>? = null
    private var current: SpikeMetrics.Cycle? = null
    private var pendingReply: CompletableDeferred<Any?>? = null
    private var sequence: ShutdownSequence? = null

    /** Non-null from a shutdown request until the engine is destroyed. */
    private var gone: CompletableDeferred<Unit>? = null
    private val lingerTask = Runnable { shutdown() }
    private val timers = object : MainTimers {
        override fun postDelayed(task: Runnable, delayMs: Long) {
            rt.main.postDelayed(task, delayMs)
        }

        override fun cancel(task: Runnable) = rt.main.removeCallbacks(task)
    }
    private var trimRegistered = false

    @Volatile private var alive = false

    /** True when no headless engine exists (any thread). */
    fun isIdle(): Boolean = !alive

    /** Runs one drain cycle, starting the engine if needed. Never throws. */
    suspend fun runCycle(timeoutMs: Long, cycle: SpikeMetrics.Cycle): CycleOutcome {
        val reply = CompletableDeferred<Any?>()
        val outcome = withTimeoutOrNull(timeoutMs) {
            var readyNow: CompletableDeferred<Boolean>? = null
            while (readyNow == null) {
                // An engine that is shutting down is never reused: wait until
                // it is destroyed, then start a fresh one.
                val waitFor = withContext(Dispatchers.Main) {
                    gone ?: run {
                        rt.main.removeCallbacks(lingerTask)
                        current = cycle
                        readyNow = ensureEngine()
                        null
                    }
                }
                waitFor?.await()
            }
            if (readyNow?.await() != true) return@withTimeoutOrNull CycleOutcome.TIMEOUT
            withContext(Dispatchers.Main) {
                val ch = channel
                val seq = sequence
                if (ch == null || seq == null || !seq.acceptsDrain()) {
                    reply.complete(null) // shutting down: RETRY, nothing acked
                } else {
                    pendingReply = reply
                    seq.drainSent()
                    ch.send(mapOf("cmd" to "drain")) {
                        if (pendingReply === reply) pendingReply = null
                        reply.complete(it)
                        seq.drainAnswered()
                    }
                }
            }
            val r = reply.await() as? Map<*, *>
            CycleOutcome.parse(r?.get("result"))
        }
        SpikeLog.e(if (outcome == null) SpikeLog.Code.CYCLE_TIMEOUT else SpikeLog.Code.CYCLE_DONE)
        return outcome ?: CycleOutcome.TIMEOUT
    }

    /** Main thread. Shuts the engine down after [lingerMs] (0 = now). */
    fun scheduleDestroy(lingerMs: Long) {
        rt.main.removeCallbacks(lingerTask)
        if (sequence == null) return
        if (lingerMs <= 0) shutdown() else rt.main.postDelayed(lingerTask, lingerMs)
    }

    /**
     * Main thread. Starts the [ShutdownSequence] (idempotent): also called
     * when the UI engine attaches. Returns at once; the engine is destroyed
     * after a pending drain was answered and Dart closed the database (or
     * the bounds passed).
     */
    fun shutdown() {
        rt.main.removeCallbacks(lingerTask)
        val seq = sequence ?: return
        if (gone == null) gone = CompletableDeferred()
        seq.request()
    }

    /** Main thread. Sends `close`; [onReply] runs when Dart answered (any answer). */
    private fun sendClose(onReply: () -> Unit) {
        val ch = channel
        if (ch == null) {
            onReply() // Dart never started: nothing is open
        } else {
            ch.send(mapOf("cmd" to "close")) { onReply() }
        }
    }

    /** Main thread. Only [ShutdownSequence] calls this. */
    private fun teardown() {
        rt.main.removeCallbacks(lingerTask)
        sequence = null
        val e = engine
        host?.detach()
        engine = null
        host = null
        channel = null
        ready?.complete(false)
        ready = null
        pendingReply?.complete(null) // the cycle is abandoned: RETRY, nothing acked
        pendingReply = null
        alive = false
        gone?.complete(Unit)
        gone = null
        if (e == null) return
        try {
            e.destroy()
        } catch (_: Exception) {
            // Engine teardown failure: nothing to keep.
        }
        SpikeLog.e(SpikeLog.Code.ENGINE_DESTROYED)
    }

    /** Main thread. Returns the readiness of the (new or existing) engine. */
    private fun ensureEngine(): CompletableDeferred<Boolean> {
        ready?.let { return it }
        val signal = CompletableDeferred<Boolean>()
        ready = signal
        val seq = ShutdownSequence(timers, ::sendClose, ::teardown)
        sequence = seq
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
                    seq.abort()
                    signal.complete(false)
                }
            }
        } catch (_: Exception) {
            SpikeLog.e(SpikeLog.Code.ENGINE_FAILED)
            seq.abort()
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
                rt.main.post { if (engine != null && rt.claim.ownerOrNull() == null) shutdown() }
            }

            override fun onConfigurationChanged(newConfig: Configuration) = Unit

            @Deprecated("Deprecated in Java")
            override fun onLowMemory() {
                rt.main.post { if (engine != null && rt.claim.ownerOrNull() == null) shutdown() }
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
