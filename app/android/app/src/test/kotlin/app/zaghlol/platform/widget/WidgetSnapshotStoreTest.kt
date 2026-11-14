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
}
