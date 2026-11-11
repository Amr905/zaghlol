package app.zaghlol.platform.capture

/**
 * The T-040 emulator scenario (design note section 11, T-047 test plan 9),
 * shared by `SmsReceiverEmulatorTest` (device, real receiver, real
 * telephony) and `SmsCaptureScenarioTest` (JVM, the same Guard rules and
 * bodies), so the device run checks plumbing and the JVM run pins the
 * decisions. `.github/scripts/sms-spike-device.sh` sends exactly these
 * bodies with `adb emu sms send` (keep them in sync). Synthetic only.
 *
 * Senders are digits (the emulator console accepts phone numbers only):
 * - [PERSONAL] is in no rule: `not_financial`, nothing written (AC1);
 * - [USER_SENDER] is a user sender (`user` keep, priority class): its OTP is
 *   dropped, its long Arabic debit arrives as one message of 6+ UCS-2 parts
 *   (AC3) and its single-part debit is kept (AC2);
 * - [REGISTRY_SENDER] is added to the t1 base as a `cib` sender: the card
 *   ignored by the user part is dropped natively (`ignored_card`, T-047 plan
 *   9) and the same sender's other card is kept (`registry`).
 */
object SmsCaptureScenario {
    const val PERSONAL = "5550199"
    const val USER_SENDER = "5550123"
    const val REGISTRY_SENDER = "5550124"
    const val CANARY = "ZG_CANARY_7731"

    const val PERSONAL_BODY = "$CANARY hello from a friend"
    const val OTP_BODY = "$CANARY your OTP is 482913"
    const val LONG_START = "ZGT040LONGSTART"
    const val LONG_END = "ZGT040LONGEND"

    /** ~430 UTF-16 units with Arabic text: UCS-2, 67 per concatenated part → 7 parts. */
    const val LONG_BODY = LONG_START +
        " تجربة زغلول: اتخصم من حسابك EGP 150.00 بالبطاقة **4321 عند SYNTH SHOP. " +
        "الرسالة دي طويلة عشان تتقسم على كذا جزء وتتجمع تاني مرة واحدة بس. " +
        "تجربة زغلول: اتخصم من حسابك EGP 150.00 بالبطاقة **4321 عند SYNTH SHOP. " +
        "الرسالة دي طويلة عشان تتقسم على كذا جزء وتتجمع تاني مرة واحدة بس. " +
        "تجربة زغلول: اتخصم من حسابك EGP 150.00 بالبطاقة **4321 عند SYNTH SHOP. " +
        "الرسالة دي طويلة عشان تتقسم على كذا جزء وتتجمع تاني مرة واحدة بس. " +
        LONG_END
    const val SINGLE_BODY = "ZG T040 single: you paid EGP 25.00 at SYNTH CAFE card **4321"
    const val IGNORED_CARD_BODY = "Purchase EGP 10.00 card **9910 at SYNTH MART"
    const val OTHER_CARD_BODY = "Purchase EGP 11.00 card **4321 at SYNTH MART"

    /** The bodies the device test must find in the spool, in send order. */
    val KEPT = listOf(USER_SENDER to LONG_BODY, USER_SENDER to SINGLE_BODY, REGISTRY_SENDER to OTHER_CARD_BODY)

    /** One enqueue per kept broadcast (the multipart message is one broadcast). */
    const val KEPT_BROADCASTS = 3

    /** The user part, written through `AndroidCaptureHost.writeGuardConfig` (the adapter path). */
    const val USER_JSON = "{\"v\":1,\"baseRegistryVersion\":3," +
        "\"ignore\":[{\"inst\":\"cib\",\"last4\":\"9910\",\"ch\":\"sms\"}]," +
        "\"userSenders\":[{\"value\":\"$USER_SENDER\",\"ch\":\"sms\"}]}"

    /** The t1 golden base plus [REGISTRY_SENDER] as an exact `cib` sender. */
    fun base(t1Base: ByteArray): ByteArray {
        val text = String(t1Base, Charsets.UTF_8)
        val anchor = "\"senders\": ["
        val at = text.indexOf(anchor)
        check(at >= 0) { "t1 base layout changed" }
        val insert = "\n  {\"match\": \"exact\", \"value\": \"$REGISTRY_SENDER\", \"inst\": \"cib\"},"
        return (text.substring(0, at + anchor.length) + insert + text.substring(at + anchor.length)).toByteArray(Charsets.UTF_8)
    }
}
