package app.zaghlol.platform.ocr

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TessdataInstallerTest {
    @get:Rule val tmp = TemporaryFolder()

    private val model = ByteArray(5000) { (it * 31).toByte() }
    private val hash = MessageDigest.getInstance("SHA-256").digest(model).joinToString("") { "%02x".format(it) }

    private fun installer(root: File, asset: () -> InputStream = { model.inputStream() }) =
        TessdataInstaller(root, asset, hash, model.size.toLong())

    @Test
    fun theBundledAssetMatchesThePinnedSizeAndHash() {
        val f = File("src/main/assets/tessdata/ara.traineddata")
        assertTrue("asset missing at ${f.absolutePath}", f.isFile)
        assertEquals(TessdataSpec.SIZE_BYTES, f.length())
        assertEquals(TessdataSpec.SHA256, TessdataInstaller.sha256Of(f.inputStream()))
    }

    @Test
    fun installsAndIsIdempotent() {
        val root = tmp.newFolder("ocr")
        val i = installer(root)
        i.ensureInstalled()
        val f = File(root, "tessdata/ara.traineddata")
        assertArrayEquals(model, f.readBytes())
        val before = f.lastModified()
        i.ensureInstalled()
        assertEquals(before, f.lastModified())
        assertEquals(root.absolutePath, i.dataPath)
        assertFalse(File(root, "tessdata/ara.traineddata.tmp").exists())
    }

    @Test
    fun aCopyThatDoesNotMatchTheHashIsReplacedFromTheAsset() {
        val root = tmp.newFolder("ocr")
        File(root, "tessdata").mkdirs()
        File(root, "tessdata/ara.traineddata").writeBytes(ByteArray(10))
        installer(root).ensureInstalled()
        assertArrayEquals(model, File(root, "tessdata/ara.traineddata").readBytes())
    }

    @Test
    fun aTamperedAssetIsRefusedAndLeavesNothingBehind() {
        val root = tmp.newFolder("ocr")
        val bad = model.copyOf().also { it[0] = (it[0] + 1).toByte() }
        try {
            installer(root) { bad.inputStream() }.ensureInstalled()
            throw AssertionError("expected IOException")
        } catch (_: IOException) {
        }
        assertFalse(File(root, "tessdata/ara.traineddata").exists())
        assertFalse(File(root, "tessdata/ara.traineddata.tmp").exists())
    }

    @Test
    fun anOversizedAssetStreamIsCutOff() {
        val root = tmp.newFolder("ocr")
        try {
            installer(root) { (model + ByteArray(100)).inputStream() }.ensureInstalled()
            throw AssertionError("expected IOException")
        } catch (_: IOException) {
        }
        assertFalse(File(root, "tessdata/ara.traineddata.tmp").exists())
    }

    @Test
    fun anEntryThatCannotBeReplacedIsLeftAlone() {
        // An entry we can neither read nor replace (a directory where the file should be) is left alone.
        val root = tmp.newFolder("ocr")
        val dirAsFile = File(root, "tessdata/ara.traineddata").also { it.mkdirs() }
        try {
            installer(root).ensureInstalled()
        } catch (_: IOException) {
        }
        assertTrue(dirAsFile.isDirectory)
    }
}
