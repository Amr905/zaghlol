package app.zaghlol.platform.capture.inbox

import app.zaghlol.platform.capture.AndroidCaptureHost
import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.capture.InboxQuery
import app.zaghlol.platform.capture.inbox.InboxTestConfig.CANARY
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

/** `AndroidCaptureHost.queryInbox` (T-042): delegation, the headless host, code-only errors. */
class InboxHostTest {
    private val now = 1_800_000_000_000L
    private val status = statusIn(tempDir())
    private val store = storeIn(tempDir(), status = status)

    private fun host(inbox: InboxReader?) =
        AndroidCaptureHost(1, store, SpoolClaim(clock = { 0 }), status, null, null, null, null, inbox = inbox)

    private fun reader(src: InboxSource, access: InboxAccess = FakeInboxAccess()) =
        InboxReader(src, access, { InboxTestConfig.guard() }, { null }, { now })

    private fun code(block: () -> Unit): String {
        try {
            block()
        } catch (e: CaptureApiError) {
            assertNull(e.message)
            assertNull(e.details)
            assertFalse(e.stackTraceToString().contains(CANARY))
            return e.code
        }
        fail("no error")
        throw AssertionError()
    }

    private val query = InboxQuery(now - 86_400_000L * 30, listOf("NBE"), null, 50)

    @Test
    fun theHeadlessHostHasNoReaderAndAnswersNotAvailable() {
        assertEquals("NOT_AVAILABLE", code { host(null).queryInbox(query) })
    }

    @Test
    fun theUiHostDelegatesToItsReader() {
        val rows = (1..3L).map { InboxRow(it, "NBE", now - 1000, "Purchase EGP $it.00 at SYNTH SHOP") }
        val page = host(reader(FakeInboxSource(rows))).queryInbox(query)
        assertEquals(listOf("1", "2", "3"), page.items.map { it.providerId })
        assertNull(page.nextCursor)
        assertEquals(3L, page.scannedTotal)
    }

    @Test
    fun readerErrorsReachDartAsCodesOnly() {
        assertEquals("NOT_AVAILABLE", code { host(reader(FakeInboxSource(emptyList()), FakeInboxAccess(declared = false))).queryInbox(query) })
        assertEquals("PERMISSION_DENIED", code { host(reader(FakeInboxSource(emptyList()), FakeInboxAccess(granted = false))).queryInbox(query) })
        val denied = FakeInboxSource(emptyList()).apply { failWith = SecurityException(CANARY) }
        assertEquals("PERMISSION_DENIED", code { host(reader(denied)).queryInbox(query) })
        assertEquals("INVALID_ARGUMENT", code { host(reader(FakeInboxSource(emptyList()))).queryInbox(query.copy(afterCursor = CANARY)) })
        val broken = FakeInboxSource(emptyList()).apply { failWith = IllegalStateException(CANARY) }
        assertEquals("IO_ERROR", code { host(reader(broken)).queryInbox(query) })
    }
}
