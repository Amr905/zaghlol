package app.zaghlol.platform.guard

/**
 * Per-sender rate limit applied to [GuardDecision.Keep] only (T-035 section 4,
 * FU-084b): more than [perSenderPerMin] keeps from one `(channel, source key)`
 * within a sliding 60 s window become `rate_limited`. Line-for-line port of
 * `packages/zaghlol_parsing/lib/guard/sender_rate_limiter.dart` (same key,
 * same boundary comparisons, LRU of [maxKeys] keys).
 *
 * In memory only, reset with the process: persisting it would write sender
 * ids to disk. Best-effort per process; the spool cap is the hard bound.
 * Unlike Dart's single-owner limiter this one is `@Synchronized`: the SMS
 * receiver and the notification listener threads may share it.
 * [nowMonotonicMs] comes from a monotonic clock (`SystemClock.elapsedRealtime`
 * in production).
 */
class SenderRateLimiter(val perSenderPerMin: Int, val maxKeys: Int = MAX_KEYS) {
    init {
        require(perSenderPerMin > 0)
        require(maxKeys > 0)
    }

    // Insertion order = recency (a touched key is re-inserted).
    private val windows = LinkedHashMap<GuardUserSender, ArrayDeque<Long>>()

    /** Number of keys currently remembered (tests). */
    val trackedKeys: Int @Synchronized get() = windows.size

    /** Applies the limit to [decision] at monotonic time [nowMonotonicMs]. Drops are returned unchanged and not counted. */
    @Synchronized
    fun apply(decision: GuardDecision, channel: String, source: String, nowMonotonicMs: Long): GuardDecision {
        if (decision !is GuardDecision.Keep) return decision
        val ch = GuardChannel.fromWire(channel)
        val key = GuardUserSender(channel, if (ch == null) TextFold.dartTrim(source) else GuardConfig.sourceKey(ch, source))
        val window = windows.remove(key) ?: ArrayDeque()
        windows[key] = window
        if (windows.size > maxKeys) windows.remove(windows.keys.first())
        // A clock that went backwards (it should not: monotonic) restarts the
        // window rather than keeping stale counts forever.
        if (window.isNotEmpty() && window.last() > nowMonotonicMs) window.clear()
        while (window.isNotEmpty() && nowMonotonicMs - window.first() >= WINDOW_MS) window.removeFirst()
        if (window.size >= perSenderPerMin) return RATE_LIMITED
        window.addLast(nowMonotonicMs)
        return decision
    }

    override fun toString(): String = "SenderRateLimiter($perSenderPerMin/min)"

    companion object {
        /** Dart `kGuardRateLimiterMaxKeys`. */
        const val MAX_KEYS = 64

        /** Dart `kGuardRateWindowMs`. */
        const val WINDOW_MS = 60_000L

        private val RATE_LIMITED = GuardDecision.Drop(GuardDropReason.RATE_LIMITED)
    }
}
