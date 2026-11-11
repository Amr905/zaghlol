package app.zaghlol.platform.capture.inbox

import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.capture.InboxPage
import app.zaghlol.platform.capture.InboxQuery
import app.zaghlol.platform.capture.RawInboxMessage
import app.zaghlol.platform.capture.inbox.InboxTestConfig.CANARY
import app.zaghlol.platform.guard.CaptureGuard
import app.zaghlol.platform.guard.GuardKeepKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.PrintStream

/** T-042 design note section 10 (JVM part). All data is synthetic. */
class InboxReaderTest {
    private val now = 1_800_000_000_000L
    private val day = 86_400_000L
    private val since = now - 30 * day
    private val guard = InboxTestConfig.guard()

    private fun reader(
        source: InboxSource,
        access: InboxAccess = FakeInboxAccess(),
        guard: CaptureGuard = this.guard,
        simSlot: (Int) -> Long? = { it.toLong() + 100 },
    ) = InboxReader(source, access, { guard }, simSlot, { now })

    private fun q(senders: List<String>, cursor: String? = null, pageSize: Long = 500, since: Long = this.since) =
        InboxQuery(since, senders, cursor, pageSize)

    private fun paid(n: Int) = "Purchase EGP $n.00 at SYNTH SHOP card *4321"

    /** Reads every page; returns the pages. */
    private fun readAll(r: InboxReader, senders: List<String>, pageSize: Long = 500, since: Long = this.since): List<InboxPage> {
        val pages = ArrayList<InboxPage>()
        var cursor: String? = null
        do {
            val p = r.query(q(senders, cursor, pageSize, since))
            pages += p
            cursor = p.nextCursor
            check(pages.size < 10_000) { "no end" }
        } while (cursor != null)
        return pages
    }

    private fun code(block: () -> Unit): String {
        try {
            block()
        } catch (e: CaptureApiError) {
            assertNull(e.message)
            assertNull(e.details)
            return e.code
        }
        fail("expected CaptureApiError")
        throw AssertionError()
    }

    // ---- selection and arguments ---------------------------------------------------------

    @Test
    fun selectionIsTheConstantTemplateAndArgumentsAreVariantsSinceAndLastId() {
        val src = FakeInboxSource(listOf(InboxRow(1, "NBE", now - day, paid(1))))
        reader(src).query(q(listOf("NBE")))
        assertEquals(1, src.queries.size)
        val (sel, args) = src.queries[0]
        assertEquals("address IN (?,?) AND date > ? AND _id > ?", sel)
        assertEquals(listOf("NBE", "nbe", since.toString(), "0"), args)
        for (c in listOf("LIKE", "GLOB", "COLLATE", "LIMIT", "lower(", "NBE", "nbe")) assertFalse(c, sel.contains(c))
    }

    @Test
    fun aNonAllowlistedAddressIsNeverBound() {
        val src = FakeInboxSource(emptyList())
        // A personal number, a sender-hint-only sender ("MyBank": hints are not an allowlist), unknown.
        reader(src).query(q(listOf("01001234567", "MyBank", "Unknown", "NBE")))
        val bound = src.queries.flatMap { it.second.dropLast(2) }.toSet()
        assertEquals(setOf("NBE", "nbe"), bound)
    }

    @Test
    fun onlyNonAllowlistedAddressesMakeNoQueryAtAll() {
        val src = FakeInboxSource(emptyList())
        val p = reader(src).query(q(listOf("01001234567", "MyBank")))
        assertEquals(0, src.queries.size)
        assertEquals(emptyList<RawInboxMessage>(), p.items)
        assertNull(p.nextCursor)
        assertEquals(0L, p.scannedTotal)
        val empty = reader(src).query(q(emptyList()))
        assertNull(empty.nextCursor)
        assertEquals(0, src.queries.size)
    }

    /** FU-085: rows of other senders are filtered by the provider; the reader never makes it materialise them. */
    @Test
    fun nonAllowlistedRowsAreNeverMaterialised() {
        val rows = (1..300L).map { i ->
            val a = when (i % 3) {
                0L -> "NBE"
                1L -> "01001234567"
                else -> "Friend"
            }
            InboxRow(i, a, now - day, "$CANARY hello $i")
        }
        val src = FakeInboxSource(rows)
        readAll(reader(src), listOf("NBE", "01001234567", "Friend"))
        assertEquals(setOf<String?>("NBE"), src.materialisedByAddress.keys)
        assertEquals(100, src.materialisedByAddress["NBE"])
    }

    @Test
    fun aProviderIgnoringTheSelectionHasItsForeignRowsSkippedNotReturned() {
        val rows = listOf(
            InboxRow(1, "01001234567", now - day, paid(1)),
            InboxRow(2, "NBE", now - day, paid(2)),
            InboxRow(3, "Friend", now - day, "$CANARY egp 5"),
            InboxRow(4, "NBE", now - 400 * day * 3, paid(4)), // older than the 25-month floor
            InboxRow(5, "NBE", since - 1, paid(5)), // before since
            InboxRow(6, "CIB-EGY", now - day, paid(6)), // allowlisted but not requested
            InboxRow(7, "MyBank", now - day, paid(7)), // the Guard would keep it (sender + body hints)
        )
        val src = FakeInboxSource(rows).apply { ignoreSelection = true }
        val p = reader(src).query(q(listOf("NBE")))
        assertEquals(listOf("2"), p.items.map { it.providerId })
        assertEquals(7L, p.scannedTotal)
        assertNull(p.nextCursor)
    }

    @Test
    fun aProviderIgnoringTheIdFloorCannotMakeTheScanLoop() {
        val rows = (1..10L).map { InboxRow(it, "NBE", now - day, paid(it.toInt())) }
        val src = FakeInboxSource(rows).apply { ignoreSelection = true }
        val r = reader(src)
        val first = r.query(q(listOf("NBE"), pageSize = 5))
        assertEquals((1..5).map { "$it" }, first.items.map { it.providerId })
        // The provider returns ids 1..5 again: no progress → IO_ERROR, never an endless cursor.
        assertEquals(InboxReader.IO_ERROR, code { r.query(q(listOf("NBE"), first.nextCursor, 5)) })
    }

    // ---- Guard on every row -------------------------------------------------------------

    @Test
    fun guardDropsAreNotReturned() {
        val rows = listOf(
            InboxRow(1, "NBE", now - day, paid(1)),
            InboxRow(2, "NBE", now - day, "Your OTP is 123456"),
            InboxRow(3, "NBE", now - day, "Purchase EGP 9.00 card **4567"), // ignored card
            InboxRow(4, "NBE", now - day, "Special offer just for you EGP 5"), // nbe promo
            InboxRow(5, "NBE", now - day, "x".repeat(CaptureGuard.MAX_BODY_LENGTH + 1)), // too long
            InboxRow(6, "NBE", now - day, ""), // empty
            InboxRow(7, "NBE", now - day, null as String?), // null body
            InboxRow(8, null, now - day, paid(8)), // null address
            InboxRow(9, "NBE", null, paid(9)), // null date
            InboxRow(10, "NBE", now - day, "x".repeat(CaptureGuard.MAX_BODY_LENGTH - 20) + " EGP 1"),
        )
        val src = FakeInboxSource(rows).apply { ignoreSelection = true }
        val p = reader(src).query(q(listOf("NBE")))
        assertEquals(listOf("1", "10"), p.items.map { it.providerId })
        assertEquals(10L, p.scannedTotal)
    }

    @Test
    fun keptItemCarriesAddressBodyDateSimSlotAndProviderId() {
        val rows = listOf(
            InboxRow(41, "nbe", now - day, paid(1), subId = 2),
            InboxRow(42, "NBE", now - day, paid(2), subId = -1),
            InboxRow(43, "NBE", now - day, paid(3), subId = null),
        )
        val p = reader(FakeInboxSource(rows)).query(q(listOf("NBE")))
        assertEquals(RawInboxMessage("nbe", paid(1), now - day, 102, "41"), p.items[0])
        assertNull(p.items[1].simSlot)
        assertNull(p.items[2].simSlot)
    }

    @Test
    fun alwaysCaptureUserAndRegexSendersAreReadButHintsAreNot() {
        assertEquals(GuardKeepKind.GENERIC, guard.senderKind("sms", "BDC-ALERT"))
        assertEquals(GuardKeepKind.USER, guard.senderKind("sms", "MyCoop"))
        assertEquals(GuardKeepKind.REGISTRY, guard.senderKind("sms", "CIB-EGY"))
        assertNull(guard.senderKind("sms", "MyBank"))
        val rows = listOf(
            InboxRow(1, "BDC-ALERT", now - day, paid(1)),
            InboxRow(2, "MyCoop", now - day, "dividend paid"),
            InboxRow(3, "CIB-EGY", now - day, paid(3)),
            InboxRow(4, "MyBank", now - day, paid(4)),
        )
        val p = reader(FakeInboxSource(rows)).query(q(listOf("BDC-ALERT", "MyCoop", "CIB-EGY", "MyBank")))
        assertEquals(listOf("1", "2", "3"), p.items.map { it.providerId })
    }

    /** History is not a flood: the live per-sender rate limit (20/min) is not applied. */
    @Test
    fun twentyOneRowsFromOneSenderAreAllReturned() {
        val rows = (1..40L).map { InboxRow(it, "NBE", now - day + it, paid(it.toInt())) }
        val p = reader(FakeInboxSource(rows)).query(q(listOf("NBE")))
        assertEquals(40, p.items.size)
    }

    @Test
    fun mixedCaseVariantsFindRowsStoredInAnotherCase() {
        val rows = listOf(
            InboxRow(1, "nbe", now - day, paid(1)),
            InboxRow(2, "NBE", now - day, paid(2)),
            InboxRow(3, "Nbe", now - day, paid(3)), // documented residual: not a variant of "NBE"
        )
        val p = reader(FakeInboxSource(rows)).query(q(listOf("NBE")))
        assertEquals(listOf("1", "2"), p.items.map { it.providerId })
        assertEquals(listOf("Nbe", "nbe", "NBE"), InboxReader.variantsOf("Nbe"))
        // ASCII only: no locale case rules.
        assertEquals(listOf("İstanbul", "İstanbul".replace("stanbul", "STANBUL")), InboxReader.variantsOf("İstanbul"))
    }

    @Test
    fun anInvalidGuardConfigReadsNothing() {
        val src = FakeInboxSource(listOf(InboxRow(1, "NBE", now - day, paid(1))))
        val p = reader(src, guard = CaptureGuard(null)).query(q(listOf("NBE")))
        assertTrue(p.items.isEmpty())
        assertNull(p.nextCursor)
        assertEquals(0, src.queries.size)
    }

    // ---- paging, chunks, cursor ----------------------------------------------------------

    @Test
    fun rows1234AtPageSize500AreThreePagesEachRowOnceAscending() {
        val rows = (1..1234L).map { InboxRow(it * 3, if (it % 2 == 0L) "NBE" else "nbe", now - day, paid(it.toInt())) }
        val src = FakeInboxSource(rows)
        val pages = readAll(reader(src), listOf("NBE"))
        assertEquals(3, pages.size)
        assertEquals(listOf(500L, 500L, 234L), pages.map { it.scannedTotal })
        val ids = pages.flatMap { p -> p.items.map { it.providerId.toLong() } }
        assertEquals(rows.map { it.id }, ids)
        assertNull(pages.last().nextCursor)
        assertEquals(0, src.openCursors)
    }

    @Test
    fun aThousandAddressesAreChunkedWithAtMost900ArgumentsAndNoAddressSplit() {
        val addresses = (1..1000).map { "zb%04d".format(it) }
        val rows = addresses.mapIndexed { i, a -> InboxRow(i + 1L, if (i % 2 == 0) a else a.uppercase(), now - day, paid(i)) }
        val src = FakeInboxSource(rows)
        val pages = readAll(reader(src), addresses, pageSize = 300)
        val ids = pages.flatMap { p -> p.items.map { it.providerId.toLong() } }
        assertEquals(rows.map { it.id }.toSet(), ids.toSet())
        assertEquals(ids.size, ids.toSet().size)
        val chunks = src.queries.map { it.second.dropLast(2) }.distinct()
        assertEquals(3, chunks.size) // 2,000 variants / 898
        for ((_, args) in src.queries) assertTrue(args.size <= InboxReader.MAX_BOUND_ARGS)
        for (a in addresses) {
            val holding = chunks.filter { a in it || a.uppercase() in it }
            assertEquals(1, holding.size)
            assertTrue(a in holding[0] && a.uppercase() in holding[0])
        }
        assertEquals(1000, src.materialised.toInt())
    }

    @Test
    fun moreThanAThousandAddressesIsInvalidArgument() {
        val src = FakeInboxSource(emptyList())
        assertEquals(InboxReader.INVALID_ARGUMENT, code { reader(src).query(q((0..1000).map { "zb%04d".format(it) })) })
        assertEquals(0, src.queries.size)
    }

    @Test
    fun aTamperedOrForeignCursorIsInvalidArgument() {
        val rows = (1..20L).map { InboxRow(it, "NBE", now - day, paid(it.toInt())) }
        val r = reader(FakeInboxSource(rows))
        val c = checkNotNull(r.query(q(listOf("NBE"), pageSize = 5)).nextCursor)
        assertTrue(c.matches(Regex("""v1\.0\.5\.[0-9a-f]{8}""")))
        val crc = c.substringAfterLast('.')
        val flipped = crc.dropLast(1) + (if (crc.last() == '0') '1' else '0')
        val bad = listOf(
            "", "garbage", "v2.0.5.$crc", "v1.0.5.$flipped", "v1.1.5.$crc", "v1.0.-5.$crc", "v1.00.5.$crc",
            "v1.0.5.ABCDEF12", "v1.0.99999999999999999999.$crc", "v1.0.5.$crc ", "v1.0.5.$crc.x", "v1.0.5." + "0".repeat(64),
        )
        for (b in bad) assertEquals(b, InboxReader.INVALID_ARGUMENT, code { r.query(q(listOf("NBE"), b, 5)) })
        // The same cursor for another sender set, or another since.
        assertEquals(InboxReader.INVALID_ARGUMENT, code { r.query(q(listOf("NBE", "CIB-EGY"), c, 5)) })
        assertEquals(InboxReader.INVALID_ARGUMENT, code { r.query(q(listOf("NBE"), c, 5, since - 1)) })
        // Untouched: continues after id 5.
        assertEquals("6", r.query(q(listOf("NBE"), c, 5)).items.first().providerId)
        // Order and duplicates of the request don't change the query.
        assertEquals("6", r.query(q(listOf("nbe", "NBE", "Friend"), c, 5)).items.first().providerId)
    }

    @Test
    fun cursorCodecRoundTrips() {
        val chunks = listOf(listOf("a", "A"), listOf("b"))
        val crc = InboxCursor.crcOf(chunks, 7)
        val t = InboxCursor.encode(1, Long.MAX_VALUE, crc)
        val p = checkNotNull(InboxCursor.decode(t, crc, 2))
        assertEquals(1, p.chunk)
        assertEquals(Long.MAX_VALUE, p.lastId)
        assertNull(InboxCursor.decode(t, crc, 1))
        // Chunk boundaries are part of the checksum.
        assertTrue(crc != InboxCursor.crcOf(listOf(listOf("a", "A", "b")), 7))
    }

    // ---- time bounds and page size ------------------------------------------------------

    @Test
    fun sinceIsRaisedTo25MonthsAndAFutureSinceIsAnEmptyLastPage() {
        val floor = InboxReader.floorOf(now)
        assertTrue(now - floor in (25 * 28 * day)..(25 * 31 * day))
        val rows = listOf(
            InboxRow(1, "NBE", floor - 1, paid(1)),
            InboxRow(2, "NBE", floor, paid(2)),
            InboxRow(3, "NBE", floor + 1, paid(3)),
        )
        val src = FakeInboxSource(rows)
        val p = reader(src).query(q(listOf("NBE"), since = 0))
        assertEquals(listOf("3"), p.items.map { it.providerId })
        assertEquals(floor.toString(), src.queries[0].second[2])
        val future = reader(src).query(q(listOf("NBE"), since = now + 1))
        assertTrue(future.items.isEmpty())
        assertNull(future.nextCursor)
        assertEquals(1, src.queries.size)
        // A since after the floor is kept as given.
        reader(src).query(q(listOf("NBE"), since = now - day))
        assertEquals((now - day).toString(), src.queries[1].second[2])
    }

    @Test
    fun pageSizeIsClampedTo1Through500() {
        val rows = (1..1200L).map { InboxRow(it, "NBE", now - day, paid(it.toInt())) }
        val r = reader(FakeInboxSource(rows))
        assertEquals(1L, r.query(q(listOf("NBE"), pageSize = 0)).scannedTotal)
        assertEquals(1L, r.query(q(listOf("NBE"), pageSize = -7)).scannedTotal)
        assertEquals(500L, r.query(q(listOf("NBE"), pageSize = 10_000)).scannedTotal)
        assertEquals(500L, r.query(q(listOf("NBE"), pageSize = Long.MAX_VALUE)).scannedTotal)
    }

    // ---- availability and errors --------------------------------------------------------

    @Test
    fun noManifestPermissionIsNotAvailableWithoutTouchingTheProvider() {
        val src = FakeInboxSource(emptyList())
        val access = FakeInboxAccess(declared = false, granted = true)
        assertEquals(InboxReader.NOT_AVAILABLE, code { reader(src, access).query(q(listOf("NBE"))) })
        assertEquals(0, src.queries.size)
    }

    @Test
    fun notGrantedOrSecurityExceptionIsPermissionDenied() {
        val src = FakeInboxSource(emptyList())
        assertEquals(InboxReader.PERMISSION_DENIED, code { reader(src, FakeInboxAccess(granted = false)).query(q(listOf("NBE"))) })
        assertEquals(0, src.queries.size)
        src.failWith = SecurityException("Permission Denial: reading $CANARY")
        assertEquals(InboxReader.PERMISSION_DENIED, code { reader(src).query(q(listOf("NBE"))) })
    }

    @Test
    fun otherFailuresAreIoError() {
        val src = FakeInboxSource(emptyList()).apply { returnNull = true }
        assertEquals(InboxReader.IO_ERROR, code { reader(src).query(q(listOf("NBE"))) })
        src.returnNull = false
        src.failWith = IllegalArgumentException("no such column $CANARY")
        assertEquals(InboxReader.IO_ERROR, code { reader(src).query(q(listOf("NBE"))) })
        val throwingGuard = InboxReader(FakeInboxSource(emptyList()), FakeInboxAccess(), { error(CANARY) }, { null }, { now })
        assertEquals(InboxReader.IO_ERROR, code { throwingGuard.query(q(listOf("NBE"))) })
    }

    @Test
    fun cursorsAreClosedOnEveryPath() {
        val rows = (1..30L).map { InboxRow(it, "NBE", now - day, paid(it.toInt())) }
        val src = FakeInboxSource(rows)
        val r = reader(src, simSlot = { throw IllegalStateException(CANARY) })
        assertEquals(InboxReader.IO_ERROR, code { r.query(q(listOf("NBE"))) })
        assertEquals(0, src.openCursors)
        readAll(reader(src), listOf("NBE"), pageSize = 7)
        assertEquals(0, src.openCursors)
    }

    // ---- never logged -------------------------------------------------------------------

    @Test
    fun theCanaryNeverReachesErrorsCursorsOrStandardStreams() {
        val out = ByteArrayOutputStream()
        val err = ByteArrayOutputStream()
        val oldOut = System.out
        val oldErr = System.err
        val errors = ArrayList<Throwable>()
        val cursors = ArrayList<String>()
        System.setOut(PrintStream(out, true))
        System.setErr(PrintStream(err, true))
        try {
            val sender = "bdc-alert"
            val rows = (1..12L).map { InboxRow(it, sender, now - day, "$CANARY ${paid(it.toInt())}") } +
                InboxRow(13, "$CANARY-friend", now - day, "$CANARY hello")
            val r = reader(FakeInboxSource(rows))
            var c: String? = null
            do {
                val p = r.query(q(listOf(sender, "$CANARY-friend"), c, 5))
                c = p.nextCursor
                c?.let { cursors += it }
            } while (c != null)
            // A provider that ignores the selection hands over the foreign row too: skipped.
            val all = reader(FakeInboxSource(rows).apply { ignoreSelection = true }).query(q(listOf(sender)))
            assertEquals(12, all.items.size)
            for (failure in listOf<() -> Unit>(
                { r.query(q(listOf(sender), "v1.0.1.$CANARY", 5)) },
                { reader(FakeInboxSource(rows).apply { failWith = SecurityException(CANARY) }).query(q(listOf(sender))) },
                { reader(FakeInboxSource(rows).apply { failWith = RuntimeException(CANARY) }).query(q(listOf(sender))) },
                { reader(FakeInboxSource(rows), simSlot = { throw RuntimeException(CANARY) }).query(q(listOf(sender))) },
            )) {
                try {
                    failure()
                    fail("expected an error")
                } catch (e: CaptureApiError) {
                    errors += e
                }
            }
        } finally {
            System.setOut(oldOut)
            System.setErr(oldErr)
        }
        assertEquals(4, errors.size)
        for (e in errors) {
            val text = e.toString() + e.message + e.stackTraceToString() + e.cause
            assertFalse(text.contains(CANARY))
            assertNull(e.cause)
        }
        assertTrue(cursors.isNotEmpty())
        for (c in cursors) assertFalse(c.contains(CANARY))
        assertFalse(out.toString().contains(CANARY))
        assertFalse(err.toString().contains(CANARY))
        assertEquals(0, out.size() + err.size())
        assertFalse(reader(FakeInboxSource(emptyList())).toString().contains(CANARY))
    }

    // ---- AC2 on the JVM (the device run is in the instrumented suite) --------------------

    @Test
    fun tenThousandLongMessagesArePagedInConstantMemory() {
        val n = 10_000
        val src = FakeInboxSource(n) { i -> InboxRow10k.row(i, now - day) }
        val r = reader(src)
        val rt = Runtime.getRuntime()
        fun used(): Long {
            repeat(3) { System.gc() }
            return rt.totalMemory() - rt.freeMemory()
        }
        val base = used()
        var cursor: String? = null
        var calls = 0
        var items = 0
        var peak = 0L
        do {
            val p = r.query(q(listOf("NBE"), cursor, 500))
            calls++
            items += p.items.size
            cursor = p.nextCursor
            if (calls % 5 == 0) peak = maxOf(peak, used() - base)
        } while (cursor != null)
        assertEquals(n, items)
        assertTrue("calls=$calls", calls in 20..21)
        assertTrue("peak heap growth ${peak / 1_048_576} MB", peak < 32L * 1_048_576)
        assertTrue("retained ${(used() - base) / 1_048_576} MB", used() - base < 32L * 1_048_576)
    }
}
