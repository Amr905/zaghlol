package app.zaghlol.platform.speech

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeechSupportTest {
    private val d = SpeechSupportRegistration::decide

    @Test fun below31IsUnsupported() = assertFalse(d(30, true, null, "ar-EG"))

    @Test fun recognizerMissingIsUnsupported() = assertFalse(d(34, false, listOf("ar-EG"), "ar-EG"))

    @Test fun api31And32TrustAvailability() = assertTrue(d(32, true, null, "ar-EG"))

    @Test fun api33NeedsTheLocaleInstalled() {
        assertTrue(d(34, true, listOf("en-US", "ar-EG"), "ar_EG"))
        assertFalse(d(34, true, listOf("en-US"), "ar-EG"))
        assertFalse(d(34, true, null, "ar-EG"))
    }
}
