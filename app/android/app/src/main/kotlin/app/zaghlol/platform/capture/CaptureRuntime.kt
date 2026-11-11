package app.zaghlol.platform.capture

import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.ingest.DrainEnvironment
import app.zaghlol.platform.ingest.DrainLoop
import app.zaghlol.platform.ingest.FlutterHeadlessStarter
import app.zaghlol.platform.ingest.HeadlessEngine
import app.zaghlol.platform.ingest.HeadlessStarter
import app.zaghlol.platform.ingest.IngestRun
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.ingest.IngestWorkQueue
import app.zaghlol.platform.ingest.MainThread
import app.zaghlol.platform.ingest.WorkManagerIngestScheduler
import app.zaghlol.platform.ingest.safely
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.KeystoreSpoolCipher
import app.zaghlol.platform.spool.SpoolCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.SpoolKey
import app.zaghlol.platform.spool.SpoolStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * The production clock and key functions, held once so a JVM test can check
 * by identity that the production graph uses them (FU-104 I-1).
 */
object ProductionClocks {
    val keyCreatedAtMs: () -> Long? = SpoolKey::creationDateMs
    val monoClockMs: () -> Long = SystemClock::elapsedRealtime
}

/**
 * The OS seams [CaptureRuntime] is built from (FU-104 I-1). The defaults are
 * the production ones; [CaptureRuntime.get] fills the context-bound rest.
 */
class CaptureSeams(
    val noBackupDir: File,
    /** `PackageInfo.longVersionCode` (FU-105 held release). */
    val appVersion: () -> Long,
    val main: MainThread,
    val queue: IngestWorkQueue,
    val device: CaptureDevice?,
    val guard: () -> GuardRuntime,
    /** Builds the headless starter; gets the runtime's headless host factory. */
    val headlessStarter: (newHeadlessHost: () -> AndroidCaptureHost) -> HeadlessStarter,
    val cipher: SpoolCipher = KeystoreSpoolCipher(),
    val keyCreatedAtMs: () -> Long? = ProductionClocks.keyCreatedAtMs,
    val monoClockMs: () -> Long = ProductionClocks.monoClockMs,
    val pause: suspend (Long) -> Unit = { delay(it) },
)

/**
 * Process-wide capture wiring (T-041 design note sections 1 and 6; replaces
 * the T-008 `SpikeRuntime`). Every component the receivers, the listener,
 * the worker and the engines share lives here once per process: the spool
 * store (one writer lock), the capture status, the drain claim, the
 * WorkManager queue, the headless engine and the UI engine's event API.
 *
 * For T-040 / T-043: after a spool write (or a refused write) call
 * [afterSpoolWrite]; it enqueues the live work and notifies an attached UI
 * engine. The Guard is [guard].
 *
 * "UI attached" means MainActivity's engine exists (visible or not). While
 * it is attached the worker never starts a headless engine: it notifies it
 * ([notifyUiIfAttached]) and polls until the spool is empty.
 */
class CaptureRuntime internal constructor(seams: CaptureSeams) {
    val status = CaptureStatusStore(File(seams.noBackupDir, "capture/status.bin"), seams.cipher)
    val store = SpoolStore(
        dir = File(seams.noBackupDir, "spool"),
        cipher = seams.cipher,
        status = status,
        keyCreatedAtMs = seams.keyCreatedAtMs,
        monoClockMs = seams.monoClockMs,
    )
    val claim = SpoolClaim(clock = seams.monoClockMs)
    val scheduler: IngestWorkQueue = seams.queue
    val device: CaptureDevice? = seams.device
    val main: MainThread = seams.main
    private val monoClockMs = seams.monoClockMs
    private val guardFactory = seams.guard

    /** The Capture Guard (T-038), loaded on first use. */
    val guard: GuardRuntime by lazy { guardFactory() }

    /** devSms: the spike's latency recorder (`SpikeInitializer`); [IngestTrace.NONE] otherwise. */
    @Volatile var trace: IngestTrace = IngestTrace.NONE

    private val engineIds = AtomicLong(1)
    private val notifyPosted = AtomicBoolean(false)

    /** The UI engine's event API while MainActivity's engine is attached. */
    @Volatile private var uiEvents: CaptureEventsApi? = null

    // Main thread only.
    private var uiKey: Any? = null
    private var uiHost: AndroidCaptureHost? = null

    val headless = HeadlessEngine(
        starter = seams.headlessStarter { newHost(headless = true) },
        main = main,
        trace = { trace },
        onGone = { if ((store.pendingCountOrNull() ?: 0) > 0) notifyUiIfAttached() },
    )

    /** The worker's run (one at a time per process). */
    val ingest = IngestRun(
        mutex = Mutex(),
        queue = scheduler,
        loop = { DrainLoop(environment(seams.pause)) },
        afterRun = { stopped ->
            main.post { if (stopped) headless.shutdown() else headless.scheduleShutdown(HeadlessEngine.LINGER_MS) }
        },
    )

    init {
        // FU-105: an app update may fix what made an entry unstorable.
        try {
            store.releaseHeldIfVersionChanged(seams.appVersion())
        } catch (_: Exception) {
            // Kept held; the next start compares again.
        }
    }

    fun uiAttached(): Boolean = uiEvents != null

    /**
     * After a spool write or a refused write (T-040 receiver, T-043
     * listener): enqueues the live work, then notifies an attached UI
     * engine (also when the enqueue failed, which is rethrown).
     */
    fun afterSpoolWrite() {
        try {
            scheduler.enqueue()
        } finally {
            notifyUiIfAttached()
        }
    }

    /**
     * Calls `CaptureEventsApi.onSpoolChanged(pending)` on the attached UI
     * engine, coalesced: at most one post is pending at a time, and the
     * count is read when it runs. Any thread.
     */
    fun notifyUiIfAttached() {
        if (uiEvents == null) return
        if (!notifyPosted.compareAndSet(false, true)) return
        main.post {
            notifyPosted.set(false)
            val events = uiEvents ?: return@post
            try {
                events.onSpoolChanged(store.pendingCount().toLong()) { }
            } catch (_: Exception) {
                // A notification only: the worker polls and drains anyway.
            }
        }
    }

    /**
     * Main thread (`MainActivity.configureFlutterEngine`). Shuts a headless
     * engine down (after its current batch and DB close), registers a UI
     * [AndroidCaptureHost] and the event API.
     */
    fun attachUi(engine: FlutterEngine) = attachUi(engine, engine.dartExecutor.binaryMessenger)

    /** Main thread (`MainActivity.cleanUpFlutterEngine`); only the attached engine detaches. */
    fun detachUi(engine: FlutterEngine) = detachUi(engine, engine.dartExecutor.binaryMessenger)

    internal fun attachUi(key: Any, messenger: BinaryMessenger) {
        headless.shutdown()
        uiHost?.detach()
        // T-042 wires its inbox reader and T-040 the Guard writer/state here.
        val host = newHost(headless = false)
        uiHost = host
        uiKey = key
        AndroidCaptureHostApi.setUp(messenger, host)
        uiEvents = CaptureEventsApi(messenger)
        trace.safely { engineAttached(messenger) }
    }

    internal fun detachUi(key: Any, messenger: BinaryMessenger) {
        if (uiKey !== key) return
        uiEvents = null
        uiKey = null
        uiHost?.detach()
        uiHost = null
        AndroidCaptureHostApi.setUp(messenger, null)
        trace.safely { engineDetached(messenger) }
    }

    /**
     * A capture host for one engine. Headless: no inbox reader and no Guard
     * writer (FU-088), so those answer `NOT_AVAILABLE`.
     */
    private fun newHost(headless: Boolean): AndroidCaptureHost = AndroidCaptureHost(
        engineId = engineIds.getAndIncrement(),
        store = store,
        claim = claim,
        status = status,
        scheduler = scheduler,
        guardWriter = null,
        guardState = null,
        device = device,
        trace = { trace },
        monoClockMs = monoClockMs,
    )

    private fun environment(pauseFn: suspend (Long) -> Unit) = object : DrainEnvironment {
        override fun pendingCount(): Int? = try {
            store.pendingCountOrNull()
        } catch (_: Exception) {
            null
        }

        override fun uiAttached(): Boolean = this@CaptureRuntime.uiAttached()

        override fun notifyUi() = notifyUiIfAttached()

        override suspend fun runHeadlessCycle(timeoutMs: Long) = headless.runCycle(timeoutMs, ::uiAttached)

        override suspend fun pause(ms: Long) = pauseFn(ms)

        override fun nowMs(): Long = monoClockMs()
    }.also { trace.safely { runStarted(foreground = uiAttached(), warmEngine = !headless.isIdle()) } }

    companion object {
        @Volatile private var instance: CaptureRuntime? = null

        fun get(context: Context): CaptureRuntime =
            instance ?: synchronized(this) {
                instance ?: run {
                    val app = context.applicationContext
                    val ref = AtomicReference<CaptureRuntime?>()
                    val rt = create(production(app, ref))
                    ref.set(rt)
                    app.registerComponentCallbacks(TrimCallbacks { ref.get() })
                    instance = rt
                    rt
                }
            }

        /** Builds a runtime from [seams] (tests build the production graph with fakes for the OS-bound parts). */
        internal fun create(seams: CaptureSeams): CaptureRuntime = CaptureRuntime(seams)

        private fun production(app: Context, ref: AtomicReference<CaptureRuntime?>): CaptureSeams {
            val handler = Handler(Looper.getMainLooper())
            return CaptureSeams(
                noBackupDir = app.noBackupFilesDir,
                appVersion = { appVersion(app) },
                main = HandlerMainThread(handler),
                queue = WorkManagerIngestScheduler(app),
                device = AndroidCaptureDevice(app),
                guard = { GuardRuntime.get(app) },
                headlessStarter = { newHost ->
                    FlutterHeadlessStarter(app, handler, newHost) { ref.get()?.trace ?: IngestTrace.NONE }
                },
            )
        }

        private fun appVersion(app: Context): Long {
            val info = app.packageManager.getPackageInfo(app.packageName, 0)
            return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
        }
    }

    /** onTrimMemory / onLowMemory: shut an idle headless engine down when no claim is held. */
    private class TrimCallbacks(private val rt: () -> CaptureRuntime?) : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) = trim()

        override fun onConfigurationChanged(newConfig: Configuration) = Unit

        @Deprecated("Deprecated in Java")
        override fun onLowMemory() = trim()

        private fun trim() {
            val r = rt() ?: return
            r.main.post { if (!r.headless.isIdle() && r.claim.ownerOrNull() == null) r.headless.shutdown() }
        }
    }
}

/** [MainThread] over the main [Handler]. */
class HandlerMainThread(private val handler: Handler) : MainThread {
    override fun post(task: Runnable) {
        handler.post(task)
    }

    override fun postDelayed(task: Runnable, delayMs: Long) {
        handler.postDelayed(task, delayMs)
    }

    override fun cancel(task: Runnable) = handler.removeCallbacks(task)

    override val dispatcher: CoroutineDispatcher get() = Dispatchers.Main
}
