package app.zaghlol.platform.guard

/**
 * Value types of the Capture Guard, mirroring
 * `packages/zaghlol_parsing/lib/guard/guard_types.dart`. Wire names are shared
 * with Dart, Swift and the golden cases. No type here holds message text
 * except the institution code and, in [GuardDecision.Keep], the last-4 digits,
 * which `toString` never prints.
 */
enum class GuardChannel(val wire: String) {
    SMS("sms"),
    NOTIFICATION("notification"),
    SHORTCUT_MESSAGE("shortcut_message"),
    APPLE_PAY("apple_pay"),

    /** User-initiated share/paste; both platforms skip the Guard for it, the value exists so the Guard has an answer. */
    SHARE("share"),
    ;

    companion object {
        fun fromWire(text: String): GuardChannel? = entries.firstOrNull { it.wire == text }
    }
}

/** Channels an ignore rule can name (database `ignore_rules.channel`). */
enum class GuardIgnoreChannel(val wire: String) {
    SMS("sms"),
    NOTIFICATION("notification"),
    APPLE_PAY("apple_pay"),
    ;

    companion object {
        fun fromWire(text: String): GuardIgnoreChannel? = entries.firstOrNull { it.wire == text }
    }
}

/**
 * The ignore-rule channel a message on [channel] is checked against, or null
 * when ignore rules do not apply (`share`). `shortcut_message` maps to `sms`
 * per [GuardPolicy.SHORTCUT_MESSAGE_USES_SMS_TOGGLE] (PO Q5).
 */
internal fun guardIgnoreChannel(channel: GuardChannel): GuardIgnoreChannel? = when (channel) {
    GuardChannel.SMS -> GuardIgnoreChannel.SMS
    GuardChannel.SHORTCUT_MESSAGE -> if (GuardPolicy.SHORTCUT_MESSAGE_USES_SMS_TOGGLE) GuardIgnoreChannel.SMS else null
    GuardChannel.NOTIFICATION -> GuardIgnoreChannel.NOTIFICATION
    GuardChannel.APPLE_PAY -> GuardIgnoreChannel.APPLE_PAY
    GuardChannel.SHARE -> null
}

/** Why a message was not kept (Dart `GuardDropReason.wire`). */
enum class GuardDropReason(val wire: String) {
    UNKNOWN_CHANNEL("unknown_channel"),
    EMPTY_BODY("empty_body"),
    TOO_LONG("too_long"),
    NOT_FINANCIAL("not_financial"),
    OTP_OR_PROMO_INST("otp_or_promo_inst"),
    OTP_OR_PROMO_GLOBAL("otp_or_promo_global"),
    IGNORED_INSTITUTION("ignored_institution"),
    IGNORED_CARD("ignored_card"),
    CONFIG_INVALID("config_invalid"),
    RATE_LIMITED("rate_limited"),
}

/** How a kept message was recognised (Dart `GuardKeepKind.wire`). */
enum class GuardKeepKind(val wire: String) {
    /** Registry sender, package or wallet card name: `inst` is set. */
    REGISTRY("registry"),

    /** A sender the user chose to capture. */
    USER("user"),

    /** Always-capture list, a sender-less channel, or sender and body hints. */
    GENERIC("generic"),
}

/** The Guard's answer for one message. */
sealed class GuardDecision {
    /**
     * May be written. [inst] is set for [GuardKeepKind.REGISTRY]; [last4] is
     * financial data and never printed by [toString].
     */
    class Keep(val kind: GuardKeepKind, val inst: String? = null, val last4: String? = null) : GuardDecision() {
        override fun toString(): String = "GuardKeep(${kind.wire})"

        override fun equals(other: Any?): Boolean =
            other is Keep && other.kind == kind && other.inst == inst && other.last4 == last4

        override fun hashCode(): Int = (kind.hashCode() * 31 + (inst?.hashCode() ?: 0)) * 31 + (last4?.hashCode() ?: 0)
    }

    /** Must not be written anywhere. */
    class Drop(val reason: GuardDropReason) : GuardDecision() {
        override fun toString(): String = "GuardDrop(${reason.wire})"

        override fun equals(other: Any?): Boolean = other is Drop && other.reason == reason

        override fun hashCode(): Int = reason.hashCode()
    }
}
