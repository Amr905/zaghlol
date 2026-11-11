package app.zaghlol.platform.ingest

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** The main thread: timers, posts and a coroutine dispatcher ([android.os.Handler] in the app). */
interface MainThread : MainTimers {
    fun post(task: Runnable)

    val dispatcher: CoroutineDispatcher
}

/**
 * One started headless engine (production: [FlutterHeadlessStarter]). Main
 * thread only. Its replies arrive on the main thread.
 */
interface HeadlessHandle {
    /** Sends `drain`; [onReply] gets the report, or a `RETRY` report when the call failed. */
    fun drain(onReply: (CycleReport) -> Unit)

    /** Sends `close`; [onReply] runs on any answer (also an error, or at once when Dart never started). */
    fun close(onReply: () -> Unit)

    /** Releases the engine's drain claim, then `FlutterEngine.destroy()`. Called exactly once, by [HeadlessEngine]. */
    fun destroy()
}

fun interface HeadlessStarter {
    /**
     * Main thread. Starts an engine at `ingestionMain`; [onReady] is called
     * later on the main thread, once: true when Dart called `ready()`, false
     * when the engine could not start.
     */
    fun start(onReady: (Boolean) -> Unit): HeadlessHandle
}

/**
 * The process-wide headless engine (T-041 design note section 5): one engine
 * at a time, started from [starter] (a `FlutterEngineGroup` engine with an
 * explicit plugin allowlist). Main-thread state; [runCycle] may be called
 * from any coroutine.
 *
 * - **Reuse:** a cycle reuses a live engine. An engine that is shutting down
 *   is never reused: the cycle waits until it is gone, then starts a fresh one.
 * - **F3:** right before it would start an engine, on the main thread, a
 *   cycle checks [runCycle]'s `uiAttached` again; a UI engine attached since
 *   the drain loop's check makes it return [CycleOutcome.UI_TOOK_OVER].
 *   (A UI attach also shuts a live engine down, on the main thread, so
 *   attach and start never interleave.)
 * - **Shutdown** ([shutdown], [scheduleShutdown]) goes through
 *   [ShutdownSequence]: `close` at once, destroy after the close reply and
 *   any pending drain reply (bounded). [onGone] runs after the destroy.
 */
class HeadlessEngine(
    private val starter: HeadlessStarter,
    private val main: MainThread,
    private val trace: () -> IngestTrace = { IngestTrace.NONE },
    private val onGone: () -> Unit = {},
) {
    private var handle: HeadlessHandle? = null
    private var ready: CompletableDeferred<Boolean>? = null
    private var pendingReply: CompletableDeferred<CycleReport>? = null
    private var sequence: ShutdownSequence? = null

    /** Non-null from a shutdown request until the engine is destroyed. */
    private var gone: CompletableDeferred<Unit>? = null
    private val lingerTask = Runnable { shutdown() }

    @Volatile private var alive = false

    /** True when no headless engine exists (any thread). */
    fun isIdle(): Boolean = !alive

    /** Runs one drain cycle, starting the engine if needed. Never throws except on cancellation. */
    suspend fun runCycle(timeoutMs: Long, uiAttached: () -> Boolean): CycleReport {
        val reply = CompletableDeferred<CycleReport>()
        val outcome = withTimeoutOrNull(timeoutMs) {
            var readyNow: CompletableDeferred<Boolean>? = null
            while (readyNow == null) {
                val step: Any? = withContext(main.dispatcher) {
                    val waitFor = gone
                    when {
                        waitFor != null -> waitFor
                        uiAttached() -> TOOK_OVER // F3: never start an engine next to the UI one
                        else -> {
                            main.cancel(lingerTask)
                            readyNow = ensureEngine()
                            null
                        }
                    }
                }
                if (step === TOOK_OVER) return@withTimeoutOrNull CycleReport(CycleOutcome.UI_TOOK_OVER)
                (step as? CompletableDeferred<*>)?.await()
            }
            if (readyNow?.await() != true) return@withTimeoutOrNull CycleReport(CycleOutcome.TIMEOUT)
            withContext(main.dispatcher) {
                val h = handle
                val seq = sequence
                if (h == null || seq == null || !seq.acceptsDrain()) {
                    reply.complete(CycleReport(CycleOutcome.RETRY)) // shutting down: nothing acked
                } else {
                    pendingReply = reply
                    seq.drainSent()
                    try {
                        h.drain { report ->
                            if (pendingReply === reply) pendingReply = null
                            reply.complete(report)
                            seq.drainAnswered()
                        }
                    } catch (_: Exception) {
                        if (pendingReply === reply) pendingReply = null
                        reply.complete(CycleReport(CycleOutcome.RETRY))
                        seq.drainAnswered()
                    }
                }
            }
            reply.await()
        }
        return outcome ?: CycleReport(CycleOutcome.TIMEOUT)
    }

    /** Main thread. Shuts the engine down after [lingerMs] (0 = now). */
    fun scheduleShutdown(lingerMs: Long) {
        main.cancel(lingerTask)
        if (sequence == null) return
        if (lingerMs <= 0) shutdown() else main.postDelayed(lingerTask, lingerMs)
    }

    /**
     * Main thread. Starts the [ShutdownSequence] (idempotent): linger end,
     * memory trim, UI engine attach, a stopped worker. Never destroys
     * directly; returns at once.
     */
    fun shutdown() {
        main.cancel(lingerTask)
        val seq = sequence ?: return
        if (gone == null) gone = CompletableDeferred()
        seq.request()
    }

    /** Main thread. Sends `close`; [onReply] runs when Dart answered (any answer). */
    private fun sendClose(onReply: () -> Unit) {
        val h = handle
        if (h == null) onReply() else h.close(onReply)
    }

    /** Main thread. Only [ShutdownSequence] calls this. */
    private fun teardown() {
        main.cancel(lingerTask)
        sequence = null
        val h = handle
        handle = null
        ready?.complete(false)
        ready = null
        pendingReply?.complete(CycleReport(CycleOutcome.RETRY)) // abandoned: nothing acked
        pendingReply = null
        try {
            h?.destroy()
        } catch (_: Exception) {
            // Engine teardown failure: nothing to keep.
        }
        alive = false
        val g = gone
        gone = null
        g?.complete(Unit)
        try {
            onGone()
        } catch (_: Exception) {
            // Notification only.
        }
    }

    /** Main thread. Returns the readiness of the (new or existing) engine. */
    private fun ensureEngine(): CompletableDeferred<Boolean> {
        ready?.let { return it }
        val signal = CompletableDeferred<Boolean>()
        ready = signal
        val seq = ShutdownSequence(main, ::sendClose, ::teardown)
        sequence = seq
        alive = true
        val h = try {
            starter.start { ok ->
                if (ready !== signal) return@start
                if (ok) trace().safely { engineReady() }
                signal.complete(ok)
                if (!ok && sequence === seq) seq.abort()
            }
        } catch (_: Exception) {
            null
        }
        if (h == null) {
            seq.abort()
            signal.complete(false)
        } else {
            handle = h
        }
        return signal
    }

    companion object {
        const val ENTRYPOINT = "ingestionMain"

        /**
         * Provisional (T-041 L4): a headless engine stays alive this long
         * after a worker run, so a burst reuses it. Lead may tune it from
         * the device rows.
         */
        const val LINGER_MS = 10_000L

        private val TOOK_OVER = Any()
    }
}
