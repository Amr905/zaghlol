package app.zaghlol.platform.guard

/**
 * The Capture Guard (platform-channels section 1.2): decides whether a
 * message may be written anywhere. Kotlin port of
 * `packages/zaghlol_parsing/lib/guard/capture_guard.dart`; parity is proven
 * by the shared golden file (JVM regex in unit tests, device ICU regex in the
 * instrumented suite).
 *
 * Pure: no I/O, no logging, no mutable state; safe from any thread. A null
 * [config] (mode `invalid`) drops everything as `config_invalid`.
 */
class CaptureGuard(val config: GuardConfig?) {
    /**
     * Decides one message. Total: any exception, including a
     * [StackOverflowError] from `java.util.regex` recursion on a pathological
     * input, is `config_invalid` (Dart parity). Other VM errors (OOM) are
     * rethrown. Nothing from the input is kept or reported.
     */
    fun decide(channel: String, source: String, body: String): GuardDecision = try {
        decideUnsafe(channel, source, body)
    } catch (t: Throwable) {
        rethrowIfFatal(t)
        CONFIG_INVALID
    }

    /**
     * Step 1 of [decide] without a body (T-042 inbox allowlist): how the
     * Guard would recognise [source] on [channel], or null when it would not.
     * Registry (exact or regex sender, package, wallet card), user sender, or
     * `alwaysCapture` / a sender-less channel (`generic`). Sender **hints**
     * are not an allowlist (they need the body) and never count. Total:
     * any error, an invalid config, an empty or over-long source → null.
     */
    fun senderKind(channel: String, source: String): GuardKeepKind? = try {
        senderKindUnsafe(channel, source)
    } catch (t: Throwable) {
        rethrowIfFatal(t)
        null
    }

    private fun senderKindUnsafe(channelWire: String, source: String): GuardKeepKind? {
        val cfg = config ?: return null
        val channel = GuardChannel.fromWire(channelWire) ?: return null
        if (source.length > MAX_SOURCE_LENGTH) return null
        val sourceKey = GuardConfig.sourceKey(channel, source)
        return when {
            resolve(cfg, channel, sourceKey) != null -> GuardKeepKind.REGISTRY
            sourceKey.isNotEmpty() && GuardUserSender(channel.wire, sourceKey) in cfg.userSenders -> GuardKeepKind.USER
            (sourceKey.isNotEmpty() && channel != GuardChannel.NOTIFICATION && sourceKey in cfg.alwaysCapture) ||
                channel == GuardChannel.APPLE_PAY ||
                channel == GuardChannel.SHORTCUT_MESSAGE ||
                channel == GuardChannel.SHARE -> GuardKeepKind.GENERIC
            else -> null
        }
    }

    private fun decideUnsafe(channelWire: String, source: String, body: String): GuardDecision {
        val cfg = config ?: return CONFIG_INVALID
        // Step 0: cheap checks before any fold or regex. Lengths are UTF-16 code units.
        val channel = GuardChannel.fromWire(channelWire) ?: return GuardDecision.Drop(GuardDropReason.UNKNOWN_CHANNEL)
        if (body.length > MAX_BODY_LENGTH || source.length > MAX_SOURCE_LENGTH) {
            return GuardDecision.Drop(GuardDropReason.TOO_LONG)
        }
        // One fold that keeps line breaks for the global drop patterns; every
        // other pattern runs on the same text with each `\n` as a space.
        val lines = TextFold.foldKeyLines(body)
        val folded = if (lines.indexOf('\n') >= 0) lines.replace('\n', ' ') else lines
        if (folded.isEmpty()) return GuardDecision.Drop(GuardDropReason.EMPTY_BODY)

        // Step 1: resolve the source.
        val sourceKey = GuardConfig.sourceKey(channel, source)
        val inst = resolve(cfg, channel, sourceKey)
        val kind: GuardKeepKind = when {
            inst != null -> GuardKeepKind.REGISTRY
            sourceKey.isNotEmpty() && GuardUserSender(channel.wire, sourceKey) in cfg.userSenders -> {
                // FU-109 / FU-121: a user-added SMS sender is captured only when the body
                // looks financial (the generic `bodyHints`); otherwise dropped here.
                if (channel == GuardChannel.SMS && cfg.bodyHints.none { it.containsMatchIn(folded) }) {
                    return GuardDecision.Drop(GuardDropReason.NOT_FINANCIAL)
                }
                GuardKeepKind.USER
            }
            (sourceKey.isNotEmpty() && channel != GuardChannel.NOTIFICATION && sourceKey in cfg.alwaysCapture) ||
                channel == GuardChannel.APPLE_PAY ||
                channel == GuardChannel.SHORTCUT_MESSAGE ||
                channel == GuardChannel.SHARE ||
                (
                    sourceKey.isNotEmpty() &&
                        cfg.senderHints.any { it.containsMatchIn(sourceKey) } &&
                        cfg.bodyHints.any { it.containsMatchIn(folded) }
                    ) -> GuardKeepKind.GENERIC
            else -> return GuardDecision.Drop(GuardDropReason.NOT_FINANCIAL)
        }

        // Step 2: OTP / promo. Institution patterns on `folded`, global ones on `lines`.
        if (inst != null && cfg.dropByInst[inst]?.any { it.containsMatchIn(folded) } == true) {
            return GuardDecision.Drop(GuardDropReason.OTP_OR_PROMO_INST)
        }
        if (cfg.globalDrop.any { it.containsMatchIn(lines) }) {
            return GuardDecision.Drop(GuardDropReason.OTP_OR_PROMO_GLOBAL)
        }
        if (inst == null) return GuardDecision.Keep(kind)

        // Step 3: institution-level ignore.
        val ignoreCh = guardIgnoreChannel(channel)
        if (ignoreCh != null && GuardIgnoreKey(inst, null, ignoreCh) in cfg.ignore) {
            return GuardDecision.Drop(GuardDropReason.IGNORED_INSTITUTION)
        }

        // Step 4: card-level ignore, always keyed by institution (EC-59).
        val last4 = guardLast4(cfg, inst, folded)
        if (ignoreCh != null && last4 != null && GuardIgnoreKey(inst, last4, ignoreCh) in cfg.ignore) {
            return GuardDecision.Drop(GuardDropReason.IGNORED_CARD)
        }

        // Step 5.
        return GuardDecision.Keep(kind, inst = inst, last4 = last4)
    }

    private fun resolve(cfg: GuardConfig, channel: GuardChannel, sourceKey: String): String? {
        if (sourceKey.isEmpty()) return null
        return when (channel) {
            GuardChannel.NOTIFICATION -> cfg.packages[sourceKey]
            GuardChannel.SMS, GuardChannel.SHORTCUT_MESSAGE ->
                cfg.exactSenders[sourceKey] ?: cfg.senderRegexes.firstOrNull { it.first.containsMatchIn(sourceKey) }?.second
            GuardChannel.APPLE_PAY -> {
                // Longest card name contained in the folded source; a tie
                // between two institutions resolves to none.
                var best: String? = null
                var bestLength = 0
                var tie = false
                for ((name, inst) in cfg.wallet) {
                    if (!sourceKey.contains(name)) continue
                    if (name.length > bestLength) {
                        best = inst
                        bestLength = name.length
                        tie = false
                    } else if (name.length == bestLength && inst != best) {
                        tie = true
                    }
                }
                if (tie) null else best
            }
            GuardChannel.SHARE -> null
        }
    }

    override fun toString(): String = "CaptureGuard(${if (config == null) "invalid" else "loaded"})"

    companion object {
        /** Longest raw body (UTF-16 code units) the Guard looks at (Dart `kGuardMaxBodyLength`). */
        const val MAX_BODY_LENGTH = 4000

        /** Longest raw source (Dart `kGuardMaxSourceLength`). */
        const val MAX_SOURCE_LENGTH = 256

        private val CONFIG_INVALID = GuardDecision.Drop(GuardDropReason.CONFIG_INVALID)
    }
}

/**
 * The last-4 the Guard reads for [inst] from a `foldKey` body (Dart
 * `guardLast4`): institution patterns, then the `*` patterns; for each
 * pattern only its **first** match is looked at, and its group 1 is taken
 * when it is exactly four ASCII digits, otherwise the next pattern is tried.
 */
internal fun guardLast4(cfg: GuardConfig, inst: String, folded: String): String? {
    fun scan(patterns: List<Regex>?): String? {
        if (patterns == null) return null
        for (p in patterns) {
            val m = p.find(folded) ?: continue
            if (m.groups.size < 2) continue
            val g = m.groups[1]?.value
            if (g != null && isFourAsciiDigits(g)) return g
        }
        return null
    }
    return scan(cfg.last4ByInst[inst]) ?: scan(cfg.last4Any)
}

private fun isFourAsciiDigits(s: String): Boolean = s.length == 4 && s.all { it in '0'..'9' }
