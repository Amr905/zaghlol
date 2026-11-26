package app.zaghlol.platform.haptics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HapticsRegistrationTest {
    @Test
    fun cancelCallsTheVibratorOnce() {
        var calls = 0
        assertTrue(HapticsRegistration.cancelWith { calls++ })
        assertEquals(1, calls)
    }

    @Test
    fun missingVibratorIsANoOp() {
        assertFalse(HapticsRegistration.cancelWith(null))
    }

    @Test
    fun cancelSwallowsRuntimeExceptions() {
        assertFalse(HapticsRegistration.cancelWith { throw IllegalStateException() })
    }
}
