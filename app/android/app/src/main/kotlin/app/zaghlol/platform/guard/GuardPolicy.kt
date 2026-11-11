package app.zaghlol.platform.guard

/** What the Guard does when the user part can not be used (PO Q1). Mirrors Dart `GuardUserConfigFailure`. */
enum class GuardUserConfigFailure {
    /** Keep messages with the bundled base rules only (`baseOnly`). */
    KEEP_WITH_BASE,

    /** Drop everything until the app rewrites the config (`invalid`). */
    DROP_ALL,
}

/**
 * Capture Guard policy decisions, mirroring
 * `packages/zaghlol_parsing/lib/guard/guard_policy.dart`. Every value is a
 * **provisional default** awaiting PO confirmation (T-035 questions); changing
 * one means changing the Dart constant, this constant and the golden cases that
 * pin it, together.
 */
internal object GuardPolicy {
    /**
     * PO Q1 (provisional, T-035): an undecryptable, malformed or
     * unknown-version user part keeps bank messages with the bundled rules
     * (`baseOnly` + diag `CONFIG_INVALID`). Dart: `kGuardUserConfigFailure`.
     * Pinned by golden `modes` `user.*` and `GuardConfigReaderTest`.
     */
    val USER_CONFIG_FAILURE: GuardUserConfigFailure = GuardUserConfigFailure.KEEP_WITH_BASE

    /**
     * PO Q5 (provisional, T-035): the per-card "SMS" toggle also governs
     * `shortcut_message` (iOS SMS through the Shortcuts automation). Dart:
     * `kShortcutMessageUsesSmsToggle`. Pinned by golden
     * `inst.shortcut_hits_sms_rule` and `card.shortcut_hits_sms_rule`.
     */
    const val SHORTCUT_MESSAGE_USES_SMS_TOGGLE: Boolean = true
}
