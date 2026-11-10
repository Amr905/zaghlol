package app.zaghlol.platform.share

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareClassifierTest {
    @Test
    fun mapsDeclaredMimeTypesToKinds() {
        assertEquals(ShareKind.TEXT, ShareClassifier.kindForMime("text/plain"))
        assertEquals(ShareKind.TEXT, ShareClassifier.kindForMime("Text/Plain; charset=UTF-8"))
        assertEquals(ShareKind.CSV, ShareClassifier.kindForMime("text/csv"))
        assertEquals(ShareKind.PDF, ShareClassifier.kindForMime("application/pdf"))
        assertEquals(ShareKind.IMAGE, ShareClassifier.kindForMime("image/jpeg"))
        assertEquals(ShareKind.IMAGE, ShareClassifier.kindForMime("image/*"))
    }

    @Test
    fun refusesEverythingElse() {
        assertNull(ShareClassifier.kindForMime(null))
        assertNull(ShareClassifier.kindForMime(""))
        assertNull(ShareClassifier.kindForMime("application/zip"))
        assertNull(ShareClassifier.kindForMime("application/octet-stream"))
        assertNull(ShareClassifier.kindForMime("text/html"))
    }

    @Test
    fun sniffsSupportedImages() {
        assertEquals("image/png", ShareClassifier.sniffImage(PNG_HEAD))
        assertEquals("image/jpeg", ShareClassifier.sniffImage(JPEG_HEAD))
        val webp = "RIFF".toByteArray() + byteArrayOf(1, 2, 3, 4) + "WEBP".toByteArray()
        assertEquals("image/webp", ShareClassifier.sniffImage(webp))
        val heic = byteArrayOf(0, 0, 0, 0x18) + "ftyp".toByteArray() + "heic".toByteArray()
        assertEquals("image/heif", ShareClassifier.sniffImage(heic))
    }

    @Test
    fun refusesUnsupportedOrTruncatedImages() {
        assertNull(ShareClassifier.sniffImage(GIF_HEAD))
        assertNull(ShareClassifier.sniffImage("<svg xmlns=".toByteArray()))
        assertNull(ShareClassifier.sniffImage(byteArrayOf(0x89.toByte(), 0x50)))
        assertNull(ShareClassifier.sniffImage(ByteArray(0)))
    }

    @Test
    fun detectsPdfByMagic() {
        assertTrue(ShareClassifier.isPdf(PDF_HEAD))
        assertFalse(ShareClassifier.isPdf("PK\u0003\u0004".toByteArray()))
        assertFalse(ShareClassifier.isPdf("%PD".toByteArray()))
    }

    @Test
    fun csvAcceptsAnyTextEncodingButNotBinary() {
        val cp1256 = byteArrayOf(0xC7.toByte(), 0xE1.toByte(), 0x2C, 0x31, 0x30, 0x0A)
        assertTrue(ShareClassifier.looksLikeCsv(cp1256, cp1256.size))
        val binary = byteArrayOf(0x41, 0x00, 0x42)
        assertFalse(ShareClassifier.looksLikeCsv(binary, binary.size))
        assertFalse(ShareClassifier.looksLikeCsv(ByteArray(0), 0))
    }

    @Test
    fun strictUtf8RejectsInvalidSequencesAndNul() {
        val ok = "synthetic مرحبا 100.50".toByteArray(Charsets.UTF_8)
        assertEquals("synthetic مرحبا 100.50", ShareClassifier.decodeUtf8Strict(ok, ok.size))
        val bad = byteArrayOf(0x41, 0xC7.toByte(), 0xE1.toByte())
        assertNull(ShareClassifier.decodeUtf8Strict(bad, bad.size))
        val nul = byteArrayOf(0x41, 0x00)
        assertNull(ShareClassifier.decodeUtf8Strict(nul, nul.size))
    }
}
