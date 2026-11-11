package app.zaghlol.platform.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** EC-11 SIM slot from the `SMS_RECEIVED` extras (T-040; FU-109 m-3 shared with the inbox reader). */
class SimSlotTest {
    private fun slot(extras: Map<String, Int>, subToSlot: (Int) -> Long? = { null }) =
        SimSlot.fromExtras({ extras[it] }, subToSlot)

    @Test
    fun theSlotIndexExtraWins() {
        assertEquals(1, slot(mapOf(SimSlot.EXTRA_SLOT_INDEX to 1, SimSlot.EXTRA_LEGACY_SLOT to 0)))
        assertEquals(0, slot(mapOf(SimSlot.EXTRA_SLOT_INDEX to 0)))
    }

    @Test
    fun theLegacySlotExtraIsTheFallback() {
        assertEquals(1, slot(mapOf(SimSlot.EXTRA_SLOT_INDEX to -1, SimSlot.EXTRA_LEGACY_SLOT to 1)))
        assertEquals(1, slot(mapOf(SimSlot.EXTRA_LEGACY_SLOT to 1)))
    }

    @Test
    fun aSubscriptionIdIsMappedWhenNoSlotIsGiven() {
        assertEquals(1, slot(mapOf(SimSlot.EXTRA_SUBSCRIPTION_INDEX to 7)) { if (it == 7) 1L else null })
        assertEquals(0, slot(mapOf(SimSlot.EXTRA_LEGACY_SUBSCRIPTION to 3)) { 0L })
        assertNull(slot(mapOf(SimSlot.EXTRA_SUBSCRIPTION_INDEX to 7)) { null })
        assertNull(slot(mapOf(SimSlot.EXTRA_SUBSCRIPTION_INDEX to -1)) { 0L })
    }

    @Test
    fun absentNegativeOrThrowingIsUnknown() {
        assertNull(slot(emptyMap()))
        assertNull(slot(mapOf(SimSlot.EXTRA_SLOT_INDEX to -1, SimSlot.EXTRA_LEGACY_SLOT to -1)))
        assertNull(SimSlot.fromExtras({ throw IllegalStateException("bad bundle") }))
        assertNull(slot(mapOf(SimSlot.EXTRA_SUBSCRIPTION_INDEX to 1)) { throw SecurityException("no permission") })
    }

    @Test
    fun theSubscriptionLookupNeedsNoPermissionAndIsNullOffDevice() {
        // android.jar on the JVM: Build.VERSION.SDK_INT is 0 → below 29 → null, never a permission request.
        assertNull(SimSlot.of(-1))
    }
}
