package app.zaghlol.platform.share

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.zaghlol.platform.spool.SpoolKey
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.zip.CRC32
import java.util.zip.Deflater
import javax.crypto.AEADBadTagException
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs on a device or emulator (`./gradlew connectedDevNoSmsDebugAndroidTest`):
 * the real Keystore key, the real no-backup directory, BitmapFactory and real
 * ACTION_SEND intents. Synthetic data only.
 */
@RunWith(AndroidJUnit4::class)
class ShareIntakeInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = ShareStores.create(context)
    private fun intake() = ShareIntake(store, context.packageName, BitmapBoundsProbe)

    @After
    fun cleanUp() {
        store.list().forEach { store.discard(it.id) }
    }

    @Test
    fun keystoreCipherRoundTripsAndRejectsTamperingAndWrongAad() {
        val cipher = KeystoreShareCipher()
        val plain = "SYNTHETIC-PLAINTEXT".toByteArray()
        val aad = "aad-1".toByteArray()
        val sink = ByteArrayOutputStream()
        cipher.wrapEncrypt(sink, aad).use { it.write(plain) }
        val encrypted = sink.toByteArray()
        assertFalse(encrypted.contains(plain))
        assertEquals(String(plain), String(cipher.decrypt(encrypted, aad)))

        assertTrue(runCatching { cipher.decrypt(encrypted, "aad-2".toByteArray()) }.exceptionOrNull() is AEADBadTagException)
        encrypted[encrypted.size - 1] = (encrypted[encrypted.size - 1].toInt() xor 1).toByte()
        assertTrue(runCatching { cipher.decrypt(encrypted, aad) }.exceptionOrNull() is AEADBadTagException)
    }

    @Test
    fun concurrentSpoolKeyCallersAllGetTheSameKey() {
        val pool = Executors.newFixedThreadPool(8)
        val aad = "aad".toByteArray()
        val blobs = (1..8).map {
            pool.submit(Callable {
                val sink = ByteArrayOutputStream()
                KeystoreShareCipher().wrapEncrypt(sink, aad).use { s -> s.write("SYNTHETIC-$it".toByteArray()) }
                sink.toByteArray()
            })
        }.map { it.get() }
        pool.shutdown()
        blobs.forEachIndexed { i, b -> assertEquals("SYNTHETIC-${i + 1}", String(KeystoreShareCipher().decrypt(b, aad))) }
        assertEquals(SpoolKey.ALIAS, "zaghlol_spool_v1")
    }

    @Test
    fun sharedTextIsStoredInItsOwnNoBackupDirectoryAndReadBack() {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, "SYNTHETIC-BANK-SMS EGP 10.00 at TEST")
        val d = (intake().accept(IntentShareSource(context, intent)) as ShareOutcome.Accepted).descriptor
        assertEquals("SYNTHETIC-BANK-SMS EGP 10.00 at TEST", store.read(d.id).text)

        val dir = File(context.noBackupFilesDir, "share")
        assertEquals(dir, ShareStores.dir(context))
        assertTrue(File(dir, "${d.id}.meta").isFile)
        assertFalse("share files never live under the T-039 spool", File(context.noBackupFilesDir, "spool/files/${d.id}.meta").exists())
        assertTrue(dir.listFiles().orEmpty().none { it.readBytes().contains("SYNTHETIC-BANK-SMS".toByteArray()) })
        store.discard(d.id)
    }

    @Test
    fun fileSchemeStreamsAreRefused() {
        val file = File(context.filesDir, "secret.png").apply { writeBytes(ByteArray(32)) }
        val intent = Intent(Intent.ACTION_SEND)
            .setType("image/png")
            .putExtra(Intent.EXTRA_STREAM, Uri.fromFile(file))
        val outcome = intake().accept(IntentShareSource(context, intent))
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, (outcome as ShareOutcome.Rejected).reason)
        file.delete()
    }

    @Test
    fun userInfoInTheAuthorityIsDetectedAndRefusedWithRealUriParsing() {
        val uri = Uri.parse("content://x@${context.packageName}.provider/files/a.png")
        val source = IntentShareSource(context, Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri))
        assertTrue(source.streamHasUserInfo)
        assertEquals("${context.packageName}.provider", source.streamHost)
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, (intake().accept(source) as ShareOutcome.Rejected).reason)
    }

    @Test
    fun bitmapProbeReadsRealBoundsWithoutDecodingPixels() {
        val small = Bitmap.createBitmap(12, 7, Bitmap.Config.ARGB_8888)
        val png = ByteArrayOutputStream().also { small.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        assertEquals(ImageBounds(12, 7), BitmapBoundsProbe.bounds(png, png.size))

        val bomb = pngHeaderOnly(width = 9_000, height = 9_000) // 81 MP, a few hundred bytes
        assertEquals(ImageBounds(9_000, 9_000), BitmapBoundsProbe.bounds(bomb, bomb.size))
    }

    /** Signature + IHDR + one tiny IDAT + IEND, with correct CRCs: enough for a header-only decode. */
    private fun pngHeaderOnly(width: Int, height: Int): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
        val ihdr = ByteArrayOutputStream().also {
            DataOutputStream(it).apply { writeInt(width); writeInt(height); write(byteArrayOf(8, 2, 0, 0, 0)) }
        }.toByteArray()
        chunk(out, "IHDR", ihdr)
        val deflater = Deflater().apply { setInput(ByteArray(4)); finish() }
        val buf = ByteArray(64)
        chunk(out, "IDAT", buf.copyOf(deflater.deflate(buf)))
        chunk(out, "IEND", ByteArray(0))
        return out.toByteArray()
    }

    private fun chunk(out: ByteArrayOutputStream, type: String, data: ByteArray) {
        val d = DataOutputStream(out)
        d.writeInt(data.size)
        val typeBytes = type.toByteArray(Charsets.US_ASCII)
        d.write(typeBytes)
        d.write(data)
        val crc = CRC32().apply { update(typeBytes); update(data) }
        d.writeInt(crc.value.toInt())
    }

    private fun ByteArray.contains(needle: ByteArray): Boolean =
        indices.any { i -> i + needle.size <= size && needle.indices.all { this[i + it] == needle[it] } }
}
