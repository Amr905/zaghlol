package app.zaghlol.platform.capture.inbox

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.capture.InboxQuery
import app.zaghlol.platform.capture.RawInboxMessage
import app.zaghlol.platform.capture.SimSlot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T-042 on a device (design note section 10), driven by
 * `.github/scripts/sms-spike-device.sh` on the devSms debug build:
 *
 * - `-e inboxPhase seeded -e inboxSince <ms> -e inboxMid <ms>`: the script
 *   granted `READ_SMS` and sent, with `adb emu sms send`, 30 messages from
 *   `5550100` (#10 a 3-part message, #20 an OTP, one carrying the canary)
 *   and 10 from `5550199`, with `inboxMid` taken between #15 and #16. Read
 *   through the **real** provider at page size 7: only `5550100`'s non-OTP
 *   rows, the long message once and whole, the `date` filter works.
 * - `-e inboxPhase denied`: after `pm revoke … READ_SMS`: `PERMISSION_DENIED`,
 *   also when the provider itself is asked (its `SecurityException`).
 * - Always: AC2, 10,000 rows × 4,000-char bodies through 20 calls of 500.
 *
 * Synthetic messages only. Nothing is logged.
 */
@RunWith(AndroidJUnit4::class)
class InboxReaderInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val phase: String? = args.getString("inboxPhase")

    private fun realReader(access: InboxAccess = ContextInboxAccess(context)) = InboxReader(
        ContentResolverInboxSource(context.contentResolver),
        access,
        { InboxTestConfig.guard() },
        SimSlot::of,
        System::currentTimeMillis,
    )

    private class Scan(val items: List<RawInboxMessage>, val pages: Int, val scanned: Long)

    private fun scan(reader: InboxReader, since: Long, pageSize: Long = 7): Scan {
        val items = ArrayList<RawInboxMessage>()
        var cursor: String? = null
        var pages = 0
        var scanned = 0L
        do {
            val p = reader.query(InboxQuery(since, SENDERS, cursor, pageSize))
            pages++
            scanned += p.scannedTotal
            items += p.items
            cursor = p.nextCursor
            check(pages < 1000)
        } while (cursor != null)
        return Scan(items, pages, scanned)
    }

    @Test
    fun seededInboxReturnsOnlyAllowlistedNonOtpRows() {
        assumeTrue(phase == "seeded")
        val since = checkNotNull(args.getString("inboxSince")).toLong()
        val mid = checkNotNull(args.getString("inboxMid")).toLong()
        assertTrue(ContextInboxAccess(context).declared())
        assertTrue(ContextInboxAccess(context).granted())
        val reader = realReader()
        // The default SMS app writes the rows asynchronously: wait up to 90 s for all 29.
        var all = scan(reader, since)
        val deadline = SystemClock.elapsedRealtime() + 90_000
        while (all.items.size < EXPECTED_KEPT && SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(2_000)
            all = scan(reader, since)
        }
        val bodies = all.items.map { it.body }
        assertEquals("kept rows (pages ${all.pages}, scanned ${all.scanned})", EXPECTED_KEPT, all.items.size)
        assertTrue(all.items.all { it.address == InboxTestConfig.EMU_SENDER })
        assertTrue(bodies.all { it.startsWith(MARK) })
        assertTrue(bodies.none { it.contains("friend") })
        assertTrue(bodies.none { it.contains("OTP") })
        // Paged at 7: several calls, each row once, ascending provider ids.
        assertTrue(all.pages >= 5)
        val ids = all.items.map { it.providerId.toLong() }
        assertEquals(ids.sorted(), ids)
        assertEquals(ids.size, ids.toSet().size)
        // The 3-part message: one row, whole.
        val long = all.items.filter { it.body.startsWith("$MARK 10 ") }
        assertEquals(1, long.size)
        assertTrue(long[0].body.endsWith("END-OF-LONG"))
        assertTrue(long[0].body.length > 306)
        assertTrue(all.items.all { it.dateMs > since })
        assertTrue(all.items.all { it.simSlot == null || it.simSlot!! >= 0 })
        // The date filter.
        val later = scan(reader, mid).items
        assertEquals(EXPECTED_KEPT_AFTER_MID, later.size)
        assertTrue(later.all { it.dateMs > mid })
        assertTrue(later.all { numberOf(it.body) > 15 })
    }

    @Test
    fun revokedPermissionIsPermissionDenied() {
        assumeTrue(phase == "denied")
        assertTrue(ContextInboxAccess(context).declared())
        assertEquals(false, ContextInboxAccess(context).granted())
        assertEquals("PERMISSION_DENIED", code { realReader().query(InboxQuery(0, SENDERS, null, 7)) })
        // Past our own check: the provider's SecurityException maps the same way.
        assertEquals("PERMISSION_DENIED", code { realReader(FakeInboxAccess()).query(InboxQuery(0, SENDERS, null, 7)) })
    }

    /** AC2: a lazy source of 10,000 rows × 4,000-char bodies; Java heap growth < 32 MB, no OOM. */
    @Test
    fun tenThousandLongMessagesPageInConstantMemory() {
        val now = System.currentTimeMillis()
        val src = FakeInboxSource(10_000) { i -> InboxRow10k.row(i, now - 86_400_000L) }
        val reader = InboxReader(src, FakeInboxAccess(), { InboxTestConfig.guard() }, { null }, { now })
        val rt = Runtime.getRuntime()
        fun used(): Long {
            repeat(3) {
                Runtime.getRuntime().gc()
                SystemClock.sleep(20)
            }
            return rt.totalMemory() - rt.freeMemory()
        }
        val base = used()
        var cursor: String? = null
        var calls = 0
        var items = 0
        var peak = 0L
        do {
            val p = reader.query(InboxQuery(0, listOf("NBE"), cursor, 500))
            calls++
            items += p.items.size
            cursor = p.nextCursor
            if (calls % 4 == 0) peak = maxOf(peak, used() - base)
        } while (cursor != null)
        assertEquals(10_000, items)
        assertTrue("calls=$calls", calls in 20..21)
        assertTrue("peak heap growth ${peak / 1_048_576} MB", peak < 32L * 1_048_576)
        assertTrue("retained ${(used() - base) / 1_048_576} MB", used() - base < 32L * 1_048_576)
        assertEquals(0, src.openCursors)
    }

    private fun code(block: () -> Unit): String {
        try {
            block()
        } catch (e: CaptureApiError) {
            assertNull(e.message)
            return e.code
        }
        fail("no error")
        throw AssertionError()
    }

    private fun numberOf(body: String): Int = body.removePrefix("$MARK ").substringBefore(' ').toInt()

    private companion object {
        const val MARK = "inbox-it"

        /** Dart may pass a non-allowlisted sender: the native Guard check drops it. */
        val SENDERS = listOf(InboxTestConfig.EMU_SENDER, "5550199")

        /** 30 from 5550100 minus the OTP (#20). */
        const val EXPECTED_KEPT = 29

        /** #16..#30 minus the OTP. */
        const val EXPECTED_KEPT_AFTER_MID = 14
    }
}
