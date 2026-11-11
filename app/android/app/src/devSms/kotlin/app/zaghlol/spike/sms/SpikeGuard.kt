package app.zaghlol.spike.sms

/**
 * Spike Capture Guard (platform-channels.md section 1.2, steps 1, 2 and 4;
 * T-008 design note section 3). Runs before anything is written.
 *
 * Spike scope (T-038 productionises it):
 * - The config file `files/guard/guard.cfg.enc` has no writer yet (T-038), so
 *   this guard always takes the "missing config" path of section 1.2: fail
 *   closed for unknown senders and keep only compiled-in senders. The
 *   compiled-in list is synthetic test senders only ([SYNTHETIC_SENDERS],
 *   plus the tester's second phone from a debug resource), so real bank SMS
 *   on tester phones are dropped and never measured.
 * - Drop patterns: the global OTP list of the registry's shared config.
 * - Bodies over [SpoolRecordCodec.MAX_BODY_CHARS] are dropped before any
 *   regex runs.
 * - No ignore rules (section 1.2 steps 3-4 need the config).
 */
class SpikeGuard(extraSenders: Collection<String> = emptyList()) {
    sealed class Decision {
        class Keep(val inst: String?, val last4: String?) : Decision() {
            override fun toString(): String = "Keep(<redacted>)"
        }

        data class Drop(val reason: DropReason) : Decision()
    }

    enum class DropReason { NOT_ALLOWLISTED, OTP_OR_PROMO, TOO_LONG, EMPTY }

    private val senders: Map<String, String> =
        SYNTHETIC_SENDERS + extraSenders.map { normalizeSender(it) }.filter { it.isNotEmpty() }.associateWith { SPIKE_INST }

    fun decide(channel: String, source: String?, body: String?): Decision {
        if (channel != CHANNEL_SMS) return Decision.Drop(DropReason.NOT_ALLOWLISTED)
        if (source.isNullOrEmpty() || body.isNullOrEmpty()) return Decision.Drop(DropReason.EMPTY)
        if (body.length > SpoolRecordCodec.MAX_BODY_CHARS) return Decision.Drop(DropReason.TOO_LONG)
        val inst = senders[normalizeSender(source)] ?: return Decision.Drop(DropReason.NOT_ALLOWLISTED)
        if (DROP_PATTERNS.any { it.containsMatchIn(body) }) return Decision.Drop(DropReason.OTP_OR_PROMO)
        val last4 = LAST4_PATTERNS.firstNotNullOfOrNull { it.find(body)?.groupValues?.getOrNull(1) }
        return Decision.Keep(inst, last4)
    }

    companion object {
        const val CHANNEL_SMS = "sms"
        const val SPIKE_INST = "spike"

        /** `adb emu sms send 5550100 "<synthetic>"` (emulator) and its +1 form. */
        val SYNTHETIC_SENDERS: Map<String, String> = mapOf("5550100" to SPIKE_INST, "+15550100" to SPIKE_INST)

        /** The registry's shared global drop list (packages/zaghlol_parsing shared.json). */
        val DROP_PATTERNS: List<Regex> = listOf(
            Regex("\\botp\\b", RegexOption.IGNORE_CASE),
            Regex("رمز التحقق"),
            Regex("كود التفعيل"),
            Regex("one[- ]time password", RegexOption.IGNORE_CASE),
        )

        val LAST4_PATTERNS: List<Regex> = listOf(Regex("(?:\\*{2,}|x{2,}|ending\\s+)(\\d{4})", RegexOption.IGNORE_CASE))

        /** Exact match after removing spaces and dashes; no other folding. */
        fun normalizeSender(s: String): String = s.filterNot { it == ' ' || it == '-' }
    }
}
