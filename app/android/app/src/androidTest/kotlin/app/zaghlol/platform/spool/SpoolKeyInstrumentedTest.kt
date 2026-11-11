package app.zaghlol.platform.spool

import android.os.Build
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.zaghlol.platform.capture.AndroidCaptureHost
import java.io.File
import java.security.KeyStore
import javax.crypto.SecretKeyFactory
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T-039 on a device or emulator (sms-spike workflow): the real AndroidKeyStore
 * spool key and the real no-backup directory. Synthetic data only. Uses its
 * own directories (`spool-it-key`, `capture-it-key`), never the app's spool.
 */
@RunWith(AndroidJUnit4::class)
class SpoolKeyInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val dir = File(context.noBackupFilesDir, "spool-it-key")
    private val statusFile = File(context.noBackupFilesDir, "capture-it-key/status.bin")

    @After
    fun cleanUp() {
        dir.deleteRecursively()
        statusFile.parentFile?.deleteRecursively()
    }

    @Test
    fun keyIsNonExportableTeeOrSoftwareNotStrongBoxAndNeedsNoUserAuth() {
        val key = SpoolKey.get()
        assertNull(key.encoded)
        val info = SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore").getKeySpec(key, KeyInfo::class.java) as KeyInfo
        assertFalse(info.isUserAuthenticationRequired)
        assertEquals(256, info.keySize)
        if (Build.VERSION.SDK_INT >= 31) {
            assertNotEquals(KeyProperties.SECURITY_LEVEL_STRONGBOX, info.securityLevel)
        }
        assertNotNull(SpoolKey.creationDateMs())
    }

    @Test
    fun entriesRoundTripWithTheKeystoreKeyAndCarryNoPlaintext() {
        val store = SpoolStore(dir, KeystoreSpoolCipher())
        val id = (store.write(record("ZG_CANARY_7731 EGP 1.00"), AdmissionClass.PRIORITY) as SpoolStore.WriteResult.Written).id
        assertFalse(String(File(dir, "$id.bin").readBytes(), Charsets.ISO_8859_1).contains("ZG_CANARY"))
        assertEquals("ZG_CANARY_7731 EGP 1.00", (store.read(id) as SpoolStore.ReadResult.Ok).record.body)
    }

    /** AC2 / AC5: a test-only alias delete → stale-key entries deleted without the ladder, reported. */
    @Test
    fun lostKeyDeletesOldEntriesOnProofAndReportsIt() {
        val sleeps = ArrayList<Long>()
        val status = CaptureStatusStore(statusFile, KeystoreSpoolCipher())
        val store = SpoolStore(
            dir = dir,
            cipher = KeystoreSpoolCipher(),
            status = status,
            keyCreatedAtMs = SpoolKey::creationDateMs,
            sleep = { sleeps += it },
        )
        val old = (1..3).map { (store.write(record("old $it"), AdmissionClass.PRIORITY) as SpoolStore.WriteResult.Written).id }
        Thread.sleep(1_500) // the Keystore creation date may have 1 s resolution
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(SpoolKey.ALIAS)
        val fresh = (store.write(record("new"), AdmissionClass.PRIORITY) as SpoolStore.WriteResult.Written).id
        val created = SpoolKey.creationDateMs()
        assumeTrue("Keystore reports no creation date on this image; the ladder path applies", created != null)

        val host = AndroidCaptureHost(1, store, SpoolClaim(), status, null, null, null, null)
        assertEquals(listOf(fresh), host.drainSpool(10).map { it.id })
        assertEquals(emptyList<Long>(), sleeps)
        assertTrue(old.none { File(dir, "$it.bin").exists() })
        val s = host.getSpoolStatus()
        assertNotNull(s.keyInvalidatedAtMs)
        assertEquals(3L, s.decryptDeleted)
        // The status survived (it was written with the new key after the loss).
        assertEquals(3L, CaptureStatusStore(statusFile, KeystoreSpoolCipher()).read().decryptDeleted)
    }

    private fun record(body: String) = SpoolRecord("sms", "5550100", body, System.currentTimeMillis(), null, null, null, 0, -1)
}
