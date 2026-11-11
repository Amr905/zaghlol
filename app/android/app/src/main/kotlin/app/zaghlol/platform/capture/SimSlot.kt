package app.zaghlol.platform.capture

import android.os.Build
import android.telephony.SubscriptionManager

/**
 * The SIM slot of a message (EC-11), one mapping for live capture (T-040)
 * and the inbox reader (T-042; moved here by FU-109 m-3). Never asks for
 * `READ_PHONE_STATE`: where the slot can't be learned without it, it is null.
 */
object SimSlot {
    /** `SubscriptionManager.EXTRA_SLOT_INDEX` (API 30+). */
    const val EXTRA_SLOT_INDEX = "android.telephony.extra.SLOT_INDEX"

    /** The slot extra older telephony stacks put on `SMS_RECEIVED`. */
    const val EXTRA_LEGACY_SLOT = "slot"

    /** `SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX` (API 30+). */
    const val EXTRA_SUBSCRIPTION_INDEX = "android.telephony.extra.SUBSCRIPTION_INDEX"

    /** The subscription extra older telephony stacks put on `SMS_RECEIVED`. */
    const val EXTRA_LEGACY_SUBSCRIPTION = "subscription"

    /**
     * `sub_id` to the SIM slot index: `SubscriptionManager.getSlotIndex` on
     * API 29+ (no permission needed); below it null (the older lookups need
     * `READ_PHONE_STATE`, which the app does not request).
     */
    fun of(subId: Int): Long? {
        if (subId < 0 || Build.VERSION.SDK_INT < 29) return null
        val slot = SubscriptionManager.getSlotIndex(subId)
        return if (slot >= 0) slot.toLong() else null
    }

    /**
     * The slot of an `SMS_RECEIVED` broadcast from its int extras: the slot
     * index (new, then legacy name), else the subscription id mapped by
     * [subToSlot]. A negative or absent value is "unknown" (null). [intExtra]
     * returns null for an absent extra; it may throw (a malformed bundle),
     * which also gives null. Pure, so it is JVM-tested.
     */
    fun fromExtras(intExtra: (String) -> Int?, subToSlot: (Int) -> Long? = ::of): Int? = try {
        val slot = listOf(EXTRA_SLOT_INDEX, EXTRA_LEGACY_SLOT).firstNotNullOfOrNull { name -> intExtra(name)?.takeIf { it >= 0 } }
        slot ?: listOf(EXTRA_SUBSCRIPTION_INDEX, EXTRA_LEGACY_SUBSCRIPTION)
            .firstNotNullOfOrNull { name -> intExtra(name)?.takeIf { it >= 0 } }
            ?.let { sub -> subToSlot(sub)?.takeIf { it in 0..Int.MAX_VALUE.toLong() }?.toInt() }
    } catch (_: Exception) {
        null
    }
}
