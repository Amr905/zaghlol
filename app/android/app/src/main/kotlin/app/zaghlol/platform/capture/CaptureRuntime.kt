package app.zaghlol.platform.capture

import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import app.zaghlol.platform.capture.inbox.InboxReader
import app.zaghlol.platform.capture.inbox.InboxReaders
import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.ingest.DrainEnvironment
import app.zaghlol.platform.ingest.DrainHold
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
import app.zaghlol.platform.wipe.LocalDataWiper
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
    /** T-042: the UI engine's inbox reader (`InboxReaders.forUiEngine`); never given to the headless host (FU-088). */
    val uiInbox: () -> InboxReader? = { null },
    /** T-040: `Settings.Global.BOOT_COUNT` for the receive stamp (-1 unknown). */
    val bootCount: () -> Int = { -1 },
    /** T-166: the native part of "Delete everything" (`LocalDataWiper.production`); UI host only. */
    val wipe: (() -> Unit)? = null,
    /** FU-194: wall clock for the drain hold's expiry. */
    val wallClockMs: () -> Long = System::currentTimeMillis,
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
 * engine. The Guard is [guard]. T-040: the SMS receiver's intake is [sms];
 * the UI host gets the Guard writer/state adapters ([GuardAdapters]).
 *
 * "UI attached" means MainActivity's engine exists (visible or not). While
 * it is attached the worker never starts a headless engine: it notifies it
 * ([notifyUiIfAttached]) and polls until the spool is empty.
 */
class CaptureRuntime internal constructor(seams: CaptureSeams) {
    val status = CaptureStatusStore(File(seams.noBackupDir, "capture/status.bin"), seams.cipher, monoClockMs = seams.monoClockMs)
    val store = SpoolStore(
        dir = File(seams.noBackupDir, "spool"),
        cipher = seams.cipher,
        status = status,
        keyCreatedAtMs = seams.keyCreatedAtMs,
        monoClockMs = seams.monoClockMs,
    )
    val claim = SpoolClaim(clock = seams.monoClockMs)

    /** FU-194: the restore's drain hold (persisted; no content). */
    val drainHold = DrainHold(File(seams.noBackupDir, "capture/" + DrainHold.FILE_NAME), seams.wallClockMs)
    val scheduler: IngestWorkQueue = seams.queue
    val device: CaptureDevice? = seams.device
    val main: MainThread = seams.main
    private val monoClockMs = seams.monoClockMs
    private val guardFactory = seams.guard
    private val uiInbox = seams.uiInbox
    private val wipe = seams.wipe

    /** The Capture Guard (T-038), loaded on first use. */
    val guard: GuardRuntime by lazy { guardFactory() }

    /**
     * T-040: the SMS receiver's intake. Guard (typed `sms` channel, the one
     * per-process rate limiter) → spool → [afterSpoolWrite] once per
     * broadcast. Built on first use, on the SMS intake thread.
     */
    val sms: SmsIntake by lazy {
        SmsIntake(
            intake = CaptureIntake(
                channel = AndroidGuardChannel.SMS,
                decide = { channel, source, body -> guard.decide(channel, source, body) },
                store = store,
                status = status,
                afterWrite = ::afterSpoolWrite,
                trace = { trace },
            ),
            bootCount = seams.bootCount,
            trace = { trace },
        )
    }

    /**
     * T-043: the notification listener's intake. Package admission → extract →
     * repeat filter → Guard (typed `notification` channel, the same
     * per-process rate limiter) → spool → [afterSpoolWrite]. Built on first
     * use, on the listener's intake thread.
     */
    val notifications: NotificationIntake by lazy {
        NotificationIntake(
            admits = { pkg -> guard.admitsNotificationPackage(pkg) },
            intake = CaptureIntake(
                channel = AndroidGuardChannel.NOTIFICATION,
                decide = { channel, source, body -> guard.decide(channel, source, body) },
                store = store,
                status = status,
                afterWrite = ::afterSpoolWrite,
                trace = { trace },
            ),
            recent = RecentNotifications(monoClockMs),
            bootCount = seams.bootCount,
        )
    }

    /** devSms: the spike's latency recorder (`SpikeInitializer`); [IngestTrace.NONE] otherwise. */
    @Volatile var trace: IngestTrace = IngestTrace.NONE

    private val engineIds = AtomicLong(1)
    private val notifyPosted = AtomicBoolean(false)

    /** The UI engine's event API while MainActivity's engine is attached. */
    @Volatile private var uiEvents: CaptureEventsApi? = null

    // Main thread only.
    private var uiKey: Any? = null
    private var uiHost: AndroidCaptureHost? = null
    private var uiPermissions: UiPermissions? = null
    private var lastCaps: CaptureCapabilities? = null

    val headless = HeadlessEngine(
        starter = seams.headlessStarter { newHost(headless = true) },
        main = main,
        trace = { trace },
        onGone = { if ((store.pendingCountOrNull() ?: 0) > 0) notifyUiIfAttached() },
        hold = drainHold,
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
     * FU-194 (UI host `holdDrain`, any thread): sets or renews the hold; a
     * headless engine still alive is asked to shut down (after its current
     * batch and the DB close). Returns whether one was active.
     */
    fun holdDrain(ttlMs: Long): Boolean {
        val active = drainHold.hold(ttlMs)
        if (active) main.post { headless.shutdown() }
        return active
    }

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
    fun attachUi(engine: FlutterEngine, permissions: UiPermissions? = null) =
        attachUi(engine, engine.dartExecutor.binaryMessenger, permissions)

    /** Main thread (`MainActivity.cleanUpFlutterEngine`); only the attached engine detaches. */
    fun detachUi(engine: FlutterEngine) = detachUi(engine, engine.dartExecutor.binaryMessenger)

    internal fun attachUi(key: Any, messenger: BinaryMessenger, permissions: UiPermissions? = null) {
        headless.shutdown()
        uiHost?.detach()
        uiPermissions?.detach()
        uiPermissions = permissions
        lastCaps = safeCapabilities()
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
        uiPermissions?.detach()
        uiPermissions = null
        lastCaps = null
        uiHost?.detach()
        uiHost = null
        AndroidCaptureHostApi.setUp(messenger, null)
        trace.safely { engineDetached(messenger) }
    }

    /**
     * A capture host for one engine. Headless: no inbox reader, no Guard
     * writer and no Guard state (FU-088; the headless engine never writes the
     * config or reads the status, T-047), so those answer `NOT_AVAILABLE` /
     * `unknown`. UI: T-042's reader and T-040's Guard adapters (the Guard is
     * touched only when Dart calls, on the Pigeon background queue).
     */
    internal fun newHost(headless: Boolean): AndroidCaptureHost = AndroidCaptureHost(
        engineId = engineIds.getAndIncrement(),
        store = store,
        claim = claim,
        status = status,
        scheduler = scheduler,
        guardWriter = if (headless) null else { json -> GuardAdapters.writerFor(guard)(json) },
        guardState = if (headless) null else { -> GuardAdapters.stateOf(guard.state()) },
        device = device,
        trace = { trace },
        monoClockMs = monoClockMs,
        inbox = if (headless) null else uiInbox(),
        ui = if (headless) null else uiPermissions,
        wiper = if (headless) null else wipe,
        drainHold = if (headless) null else drainHoldControl,
    )

    /** FU-194: the UI host's view of the hold (the headless host answers `NOT_AVAILABLE`). */
    private val drainHoldControl = object : DrainHoldControl {
        override fun hold(ttlMs: Long): Boolean = holdDrain(ttlMs)

        override fun headlessActive(): Boolean = drainHold.headlessActive()

        override fun release() = drainHold.release()
    }

    /**
     * T-044 (EC-13): main thread, on resume and after a permission prompt.
     * When the capabilities differ from the last ones seen, tells the UI
     * engine (`CaptureEventsApi.onPermissionChanged`). The first look after
     * attach only records the baseline; a revocation that killed the process
     * is seen by Dart's own `getCapabilities` at start.
     */
    fun checkPermissions() {
        val events = uiEvents ?: return
        val now = safeCapabilities() ?: return
        val before = lastCaps
        lastCaps = now
        if (before == null || before == now) return
        try {
            events.onPermissionChanged(now) { }
        } catch (_: Exception) {
            // A notification only: Dart reads the capabilities again when it needs them.
        }
    }

    private fun safeCapabilities(): CaptureCapabilities? = try {
        device?.capabilities()
    } catch (_: Exception) {
        null
    }

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
                uiInbox = { InboxReaders.forUiEngine(app) },
                bootCount = { bootCount(app) },
                wipe = { LocalDataWiper.production(app) { GuardRuntime.get(app).forgetUser() }.wipe() },
                headlessStarter = { newHost ->
                    FlutterHeadlessStarter(app, handler, newHost) { ref.get()?.trace ?: IngestTrace.NONE }
                },
            )
        }

        private fun bootCount(app: Context): Int = try {
            Settings.Global.getInt(app.contentResolver, Settings.Global.BOOT_COUNT, -1)
        } catch (_: Exception) {
            -1
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
