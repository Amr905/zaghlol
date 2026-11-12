package app.zaghlol.platform.capture

import android.app.Notification
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-043 design note section 5 (the body shape) and the main-thread filter (section 2). */
class NotificationExtractorTest {
    private fun body(f: FakeFields) = NotificationExtractor.extract(f)

    @Test
    fun titlePlusBigTextWinsOverText() {
        assertEquals("Bank\nbig body", body(FakeFields(title = "Bank", text = "short", bigText = "big body")))
    }

    @Test
    fun textWhenThereIsNoBigText() {
        assertEquals("Bank\nshort", body(FakeFields(title = "Bank", text = "short", bigText = "  ")))
    }

    @Test
    fun linesAreTheFallbackJoinedWithNewlines() {
        assertEquals("Bank\na\nb", body(FakeFields(title = "Bank", lines = arrayOf("a", "b"))))
    }

    @Test
    fun aBlankTitleLeavesTheContentAloneAndViceVersa() {
        assertEquals("only text", body(FakeFields(title = " ", text = "only text")))
        assertEquals("only title", body(FakeFields(title = "only title")))
    }

    @Test
    fun allBlankIsNothing() {
        assertNull(body(FakeFields(title = "", text = null, bigText = " ", lines = emptyArray())))
    }

    @Test
    fun overLongFieldsAreSkippedWithoutCopying() {
        val title = CountingChars("t".repeat(NotificationExtractor.MAX_TITLE + 1))
        assertNull(body(FakeFields(title = title, text = "x")))
        assertEquals(0, title.toStrings)
        val big = CountingChars("b".repeat(NotificationExtractor.MAX_CONTENT + 1))
        assertNull(body(FakeFields(title = "Bank", bigText = big)))
        assertEquals(0, big.toStrings)
        val atLimit = "c".repeat(NotificationExtractor.MAX_CONTENT)
        assertEquals("Bank\n$atLimit", body(FakeFields(title = "Bank", bigText = atLimit)))
        assertNull(body(FakeFields(title = "Bank", lines = arrayOf("a".repeat(NotificationExtractor.MAX_CONTENT), "b"))))
    }

    @Test
    fun throwingFieldsAreSkippedSilently() {
        assertNull(body(FakeFields(title = "Bank", text = "x", throwOnRead = true)))
    }

    @Test
    fun aNonStringCharSequenceBecomesAPlainString() {
        // android.text.Spanned values are CharSequences too; toString() is what drops the spans.
        val styled = CountingChars("plain text")
        val out: Any? = body(FakeFields(title = null, text = styled))
        assertEquals("plain text", out)
        assertTrue(out is String)
        assertEquals(1, styled.toStrings)
    }

    @Test
    fun filterSkipsOwnSummaryOngoingAndForegroundService() {
        val own = "app.zaghlol"
        fun accepts(pkg: String?, flags: Int) = NotificationFilter.accepts(FakePosted(pkg, flags = flags), own)
        assertTrue(accepts("com.example.nbe", 0))
        assertFalse(accepts(own, 0))
        assertFalse(accepts(null, 0))
        assertFalse(accepts("com.example.nbe", Notification.FLAG_GROUP_SUMMARY))
        assertFalse(accepts("com.example.nbe", Notification.FLAG_ONGOING_EVENT))
        assertFalse(accepts("com.example.nbe", Notification.FLAG_FOREGROUND_SERVICE))
        assertTrue(accepts("com.example.nbe", Notification.FLAG_AUTO_CANCEL))
    }

    @Test
    fun theFilterReadsNoExtras() {
        val p = FakePosted("com.example.nbe")
        NotificationFilter.accepts(p, "app.zaghlol")
        assertEquals(0, p.fields.reads)
    }
}
