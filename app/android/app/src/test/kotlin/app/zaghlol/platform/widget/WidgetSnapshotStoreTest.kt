package app.zaghlol.platform.widget

import app.zaghlol.platform.spool.SoftwareSpoolCipher
import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** T-118: the encrypted widget snapshot store and the channel host (synthetic strings only). */
class WidgetSnapshotStoreTest {
    private lateinit var dir: File
    private lateinit var file: File

    @Before
    fun setUp() {
        dir = Files.createTempDirectory("widget").toFile()
        file = File(dir, "widget/snapshot.bin")
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun view(primary: String = "314.28 EGP/day", days: Int? = 7) =
        WidgetView(WidgetView.STATE_OK, primary, "7 days to payday", "EGP", 1_700_000_000_000L, days)

    @Test
    fun roundTripsAndIsNotPlaintextOnDisk() {
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        store.write(view())
        assertEquals(view(), store.readOrNull())
        val raw = file.readBytes()
        assertFalse(String(raw, Charsets.ISO_8859_1).contains("314"))
        assertFalse(String(raw, Charsets.ISO_8859_1).contains("EGP"))
    }

    @Test
    fun hiddenAmountSnapshotHoldsOnlyTheMask() {
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        store.write(view(primary = "•••/day"))
        val read = store.readOrNull()!!
        assertEquals("•••/day", read.primaryText)
        assertFalse(Regex("[0-9٠-٩]").containsMatchIn(read.primaryText))
    }

    @Test
    fun absentOrTamperedOrWrongKeyReadsAsNullAndKeepsTheFile() {
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        assertNull(store.readOrNull())
        store.write(view())
        val bytes = file.readBytes()
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 1).toByte()
        file.writeBytes(bytes)
        assertNull(store.readOrNull())
        assertTrue(file.exists())
        store.write(view())
        val other = WidgetSnapshotStore(file, SoftwareSpoolCipher(ByteArray(32) { 9 }))
        assertNull(other.readOrNull())
    }

    @Test
    fun aadBindsTheFileToTheWidgetPurpose() {
        val cipher = SoftwareSpoolCipher()
        file.parentFile!!.mkdirs()
        file.writeBytes(cipher.encrypt(WidgetSnapshotStore.encode(view()), "zaghlol.capture.v1|status".toByteArray()))
        assertNull(WidgetSnapshotStore(file, cipher).readOrNull())
    }

    @Test
    fun clearIsIdempotentAndLeavesNoTmp() {
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        store.clear()
        store.write(view())
        store.clear()
        store.clear()
        assertNull(store.readOrNull())
        assertEquals(emptyList<String>(), file.parentFile!!.list()!!.toList())
    }

    @Test
    fun overlongTextIsTruncatedNotRejected() {
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        store.write(view(primary = "x".repeat(10_000)))
        assertEquals(WidgetView.MAX_TEXT_CHARS, store.readOrNull()!!.primaryText.length)
    }

    @Test
    fun hostStoresRefreshesAndMapsFailuresToCodeOnlyErrors() {
        var refreshed = 0
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        val host = WidgetBridgeHost(store) { refreshed++ }
        host.updateSnapshot(
            WidgetSnapshot(WidgetDisplayState.NO_BUDGET, "Set a budget", "", "EGP", 5L, null),
        )
        assertEquals(1, refreshed)
        val read = store.readOrNull()!!
        assertEquals(WidgetView.STATE_NO_BUDGET, read.state)
        assertNull(read.daysToPayday)
        host.clear()
        assertEquals(2, refreshed)
        assertNull(store.readOrNull())

        // A directory where the file should be: the write fails, the error carries only the code.
        val bad = WidgetBridgeHost(WidgetSnapshotStore(dir.also { File(it, "x").mkdirs() }, SoftwareSpoolCipher())) {}
        try {
            bad.updateSnapshot(WidgetSnapshot(WidgetDisplayState.OK, "secret-sentinel", "", "EGP", 1L, 1L))
            org.junit.Assert.fail("expected an error")
        } catch (e: WidgetBridgeApiError) {
            assertEquals("IO_ERROR", e.code)
            assertNull(e.message)
            assertNull(e.details)
        }
        assertNotNull(read)
    }

    private val cairo = java.time.ZoneId.of("Africa/Cairo")

    private fun at(y: Int, m: Int, d: Int, h: Int, min: Int) =
        java.time.ZonedDateTime.of(y, m, d, h, min, 0, 0, cairo).toInstant().toEpochMilli()

    @Test
    fun daysToPaydayRollsAtLocalMidnightFromTheStoredList() {
        val v = WidgetView(
            WidgetView.STATE_OK, "•••/day", "3 days", "EGP", at(2026, 11, 3, 23, 50), 3,
            listOf("3 days", "2 days", "1 day"),
        )
        assertEquals("3 days", v.secondaryAt(at(2026, 11, 3, 23, 59), cairo))
        assertEquals("2 days", v.secondaryAt(at(2026, 11, 4, 0, 1), cairo))
        assertEquals("1 day", v.secondaryAt(at(2026, 11, 5, 12, 0), cairo))
        // Past the list: blank, never a stale count; a clock set back keeps day 0.
        assertEquals("", v.secondaryAt(at(2026, 11, 9, 12, 0), cairo))
        assertEquals("3 days", v.secondaryAt(at(2026, 11, 1, 12, 0), cairo))
    }

    @Test
    fun aV1FileWithoutTheListKeepsItsStoredLine() {
        val v = view()
        assertEquals("7 days to payday", v.secondaryAt(Long.MAX_VALUE / 2, cairo))
    }

    @Test
    fun theDayListRoundTripsAndIsCapped() {
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        val many = (1..100).map { "d$it" }
        store.write(view().copy(secondaryByDay = many))
        assertEquals(many.take(WidgetSnapshotStore.MAX_DAYS), store.readOrNull()!!.secondaryByDay)
    }

    @Test
    fun midnightDelayIsToJustAfterTheNextLocalMidnight() {
        assertEquals(11L * 60 * 60_000 + 31 * 60_000, WidgetMidnightWorker.delayToNextMidnightMs(at(2026, 11, 3, 12, 30), cairo))
    }

    @Test
    fun hostStoresTheDayList() {
        val store = WidgetSnapshotStore(file, SoftwareSpoolCipher())
        WidgetBridgeHost(store) {}.updateSnapshot(
            WidgetSnapshot(WidgetDisplayState.OK, "•••/day", "2 days", "EGP", 5L, 2L, listOf("2 days", "1 day")),
        )
        assertEquals(listOf("2 days", "1 day"), store.readOrNull()!!.secondaryByDay)
    }
}
