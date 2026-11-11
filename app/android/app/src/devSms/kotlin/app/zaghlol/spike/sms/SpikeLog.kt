package app.zaghlol.spike.sms

import android.util.Log

/**
 * The only log output of the SMS spike (T-008 design note section 8). It
 * takes a code from a fixed set and a number: there is no parameter that
 * could carry a body, sender, last4, amount or exception message. Emits
 * `ZG-SPK code=<CODE> ms=<n>` only on debuggable builds (dev/profile); the
 * spike exists only in the devSms flavour anyway. CI greps the spike sources
 * for any other `Log.` call.
 */
object SpikeLog {
    enum class Code {
        RX_RECEIVED,
        SPOOL_WRITTEN,
        ENQUEUED,
        WORKER_START,
        ENGINE_READY,
        METRICS_FAILED,
    }

    /** Set once from `ApplicationInfo.FLAG_DEBUGGABLE`. */
    @Volatile
    var enabled: Boolean = false

    /** Test seam; production writes to logcat. */
    @Volatile
    var sink: (Code, Long) -> Unit = { code, ms -> Log.d(TAG, "code=${code.name} ms=$ms") }

    fun e(code: Code, ms: Long = -1) {
        if (!enabled) return
        try {
            sink(code, ms)
        } catch (_: Throwable) {
            // Logging must never break capture.
        }
    }

    private const val TAG = "ZG-SPK"
}
