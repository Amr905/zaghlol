package app.zaghlol.platform.wipe

import app.zaghlol.platform.capture.AndroidCaptureHost
import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.nio.file.Files

class LocalDataWiperTest {
    private fun tempDir(): File = Files.createTempDirectory("t166").toFile()

    @Test
    fun clearsContentsAndKeepsRoots() {
        val a = tempDir()
        val b = tempDir()
        File(a, "spool/held").mkdirs()
        File(a, "spool/held/x.bin").writeBytes(byteArrayOf(1))
        File(a, "guard").mkdirs()
        File(a, "guard/guard.user.enc").writeBytes(byteArrayOf(2))
        File(b, "status.bin").writeBytes(byteArrayOf(3))
        val ran = mutableListOf<String>()

        LocalDataWiper(listOf(a, b), listOf({ ran.add("jobs") }, { ran.add("keys") })).wipe()

        assertEquals(listOf("jobs", "keys"), ran)
        assertTrue(a.isDirectory && a.listFiles()!!.isEmpty())
        assertTrue(b.isDirectory && b.listFiles()!!.isEmpty())
    }

    @Test
    fun aFailingPartDoesNotStopTheRestButIsReported() {
        val a = tempDir()
        File(a, "keys").mkdirs()
        File(a, "keys/db_key_v1.bin").writeBytes(byteArrayOf(1))
        val ran = mutableListOf<String>()
        try {
            LocalDataWiper(listOf(a), listOf({ throw IllegalStateException("x") }, { ran.add("after") })).wipe()
            fail("expected WipeIncomplete")
        } catch (e: WipeIncomplete) {
            assertEquals(null, e.message)
        }
        assertEquals(listOf("after"), ran)
        assertTrue(a.listFiles()!!.isEmpty())
    }

    @Test
    fun aMissingRootIsAlreadyClear() {
        val gone = File(tempDir(), "never")
        assertTrue(LocalDataWiper.clearContents(gone))
        LocalDataWiper(listOf(gone), emptyList()).wipe()
    }

    @Test
    fun doesNotFollowASymlinkOutOfTheRoot() {
        val root = tempDir()
        val outside = tempDir()
        val keep = File(outside, "keep.txt").apply { writeBytes(byteArrayOf(9)) }
        Files.createSymbolicLink(File(root, "link").toPath(), outside.toPath())

        assertTrue(LocalDataWiper.clearContents(root))

        assertTrue(keep.exists())
        assertTrue(root.listFiles()!!.isEmpty())
    }

    private fun host(wiper: (() -> Unit)?): AndroidCaptureHost {
        val status = statusIn(tempDir())
        return AndroidCaptureHost(1, storeIn(tempDir(), status = status), SpoolClaim(clock = { 0 }), status, null, null, null, null, wiper = wiper)
    }

    @Test
    fun hostWithoutAWiperIsNotAvailable() {
        try {
            host(null).wipeLocalData()
            fail("expected NOT_AVAILABLE")
        } catch (e: CaptureApiError) {
            assertEquals(AndroidCaptureHost.NOT_AVAILABLE, e.code)
            assertEquals(null, e.message)
        }
    }

    @Test
    fun hostMapsAWipeFailureToACodeOnlyIoError() {
        var calls = 0
        host { calls++ }.wipeLocalData()
        assertEquals(1, calls)
        try {
            host { throw WipeIncomplete() }.wipeLocalData()
            fail("expected IO_ERROR")
        } catch (e: CaptureApiError) {
            assertEquals(AndroidCaptureHost.IO_ERROR, e.code)
            assertEquals(null, e.details)
        }
    }
}
