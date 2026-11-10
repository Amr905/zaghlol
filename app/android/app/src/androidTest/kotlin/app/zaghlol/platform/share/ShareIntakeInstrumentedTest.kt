package app.zaghlol.platform.share

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import androidx.test.ext.junit.runners.AndroidJUnit4

/**
 * Runs on a device or emulator (`./gradlew connectedDevNoSmsDebugAndroidTest`):
 * the real Keystore key, the real no-backup directory and a real ACTION_SEND intent.
 * Synthetic data only.
 */
@RunWith(AndroidJUnit4::class)
class ShareIntakeInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = ShareStores.create(context)

    @After
    fun cleanUp() {
        store.list().forEach { store.discard(it.id) }
    }

    @Test
    fun keystoreCipherRoundTripsAndRejectsTampering() {
        val cipher = KeystoreShareCipher()
        val plain = "SYNTHETIC-PLAINTEXT".toByteArray()
        val sink = java.io.ByteArrayOutputStream()
        cipher.wrapEncrypt(sink).use { it.write(plain) }
        val encrypted = sink.toByteArray()
        assertFalse(encrypted.contains(plain))
        assertEquals(String(plain), String(cipher.decrypt(encrypted)))

        encrypted[encrypted.size - 1] = (encrypted[encrypted.size - 1].toInt() xor 1).toByte()
        val failed = runCatching { cipher.decrypt(encrypted) }.isFailure
        assertTrue(failed)
    }

    @Test
    fun sharedTextIntentIsStoredInNoBackupStorageAndReadBack() {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, "SYNTHETIC-BANK-SMS EGP 10.00 at TEST")
        val outcome = ShareIntake(store, context.packageName)
            .accept(IntentShareSource(context.contentResolver, intent))
        val d = (outcome as ShareOutcome.Accepted).descriptor
        assertEquals("SYNTHETIC-BANK-SMS EGP 10.00 at TEST", store.read(d.id).text)

        val dir = File(context.noBackupFilesDir, "spool/files")
        assertTrue(dir.isDirectory)
        assertTrue(dir.listFiles().orEmpty().none { it.readBytes().contains("SYNTHETIC-BANK-SMS".toByteArray()) })
        store.discard(d.id)
    }

    @Test
    fun fileSchemeStreamsAreRefused() {
        val file = File(context.filesDir, "secret.png").apply { writeBytes(ByteArray(32)) }
        val intent = Intent(Intent.ACTION_SEND)
            .setType("image/png")
            .putExtra(Intent.EXTRA_STREAM, android.net.Uri.fromFile(file))
        val outcome = ShareIntake(store, context.packageName)
            .accept(IntentShareSource(context.contentResolver, intent))
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, (outcome as ShareOutcome.Rejected).reason)
        file.delete()
    }

    private fun ByteArray.contains(needle: ByteArray): Boolean =
        indices.any { i -> i + needle.size <= size && needle.indices.all { this[i + it] == needle[it] } }
}
