package app.zaghlol.platform.guard

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileNotFoundException
import javax.crypto.AEADBadTagException
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs on a device or emulator (`connectedDevSmsDebugAndroidTest`, the
 * `sms-spike` matrix API 26/30/34/36 = four ICU versions): the shared golden
 * file on device regex (AC1), the real bundled base asset, the real Keystore
 * round trip of the user part (AC4) and the real no-backup path (L-1).
 * Synthetic data only; the golden dir is an androidTest asset dir.
 */
@RunWith(AndroidJUnit4::class)
class GuardGoldenInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val testAssets = instrumentation.context.assets
    private val target = instrumentation.targetContext
    private val testDir = File(target.noBackupFilesDir, "guard-instrumented-test")

    private fun fixture(path: String): ByteArray = testAssets.open(path).use { it.readBytes() }

    @After
    fun cleanUp() {
        testDir.deleteRecursively()
    }

    @Test
    fun allGoldenEntriesPassOnDeviceRegex() {
        val result = GuardGoldenRunner(::fixture).runAll()
        assertTrue(result.toString(), result.failures.isEmpty())
        assertEquals(result.count, result.total)
        assertTrue(result.total >= 237)
    }

    /** Parse + compile and the worst adversarial `decide`, with loose CI bounds; the numbers go to the instrumentation status. */
    @Test
    fun timingWithinBounds() {
        val runner = GuardGoldenRunner(::fixture)
        runner.runAll()
        val parseMs = runner.parseNanos("t1") / 1_000_000.0
        val (worstId, worstNanos) = runner.worstAdversarialNanos()
        val worstMs = worstNanos / 1_000_000.0
        // Status code 2 is "in progress" for the instrumentation result parser: extra
        // values only, no effect on the test result.
        instrumentation.sendStatus(
            2,
            Bundle().apply {
                putString("guard.timing", "api=${android.os.Build.VERSION.SDK_INT} parse_ms=$parseMs worst_decide_ms=$worstMs worst_case=$worstId")
            },
        )
        assertTrue("parse+compile $parseMs ms", parseMs <= 100.0)
        assertTrue("worst decide $worstMs ms ($worstId)", worstMs <= 25.0)
    }

    @Test
    fun goldenFilesAreNotInTheAppApk() {
        for (path in listOf("golden.json", "configs/t1_base.json", "flutter_assets/golden.json")) {
            try {
                target.assets.open(path).close()
                throw AssertionError("$path is packaged in the app APK")
            } catch (e: FileNotFoundException) {
                // expected
            }
        }
    }

    @Test
    fun bundledBaseLoads() {
        val bytes = try {
            BaseConfigSource.read(target.assets)
        } catch (e: FileNotFoundException) {
            null
        }
        assumeTrue("app/assets/guard/guard_base.json is not bundled yet (T-036)", bytes != null)
        val load = GuardConfig.parse(bytes!!, null)
        assertEquals(GuardConfigMode.BASE_ONLY, load.mode)
    }

    @Test
    fun userPartPathIsUnderNoBackupDir() {
        val dir = GuardUserConfigStore.dirUnder(target.noBackupFilesDir).canonicalFile
        assertTrue(dir.path.startsWith(target.noBackupFilesDir.canonicalPath + File.separator))
        assertFalse(dir.path.startsWith(target.filesDir.canonicalPath))
        assertFalse(dir.path.startsWith(target.cacheDir.canonicalPath))
    }

    /** AC4 on the real Keystore: ciphertext on disk only, AAD-bound, round trip through the runtime. */
    @Test
    fun keystoreRoundTripAndCiphertextOnDisk() {
        val cipher = KeystoreGuardUserCipher()
        val store = GuardUserConfigStore(testDir, cipher)
        val canary = (
            "{\"v\":1,\"baseRegistryVersion\":3,\"ignore\":[{\"inst\":\"zgcanaryinst\",\"last4\":\"7731\",\"ch\":\"sms\"}]," +
                "\"userSenders\":[{\"value\":\"ZG_CANARY_SRC\",\"ch\":\"sms\"}]}"
            ).toByteArray()
        store.write(canary)
        val disk = store.file.readBytes()
        for (needle in listOf("zgcanaryinst", "7731", "ignore", "ZG_CANARY_SRC")) {
            assertFalse(needle, String(disk, Charsets.ISO_8859_1).contains(needle))
        }
        assertArrayEquals(canary, (store.read() as GuardUserConfigStore.Read.Plain).bytes)
        try {
            cipher.decrypt(disk, "zaghlol.guard.v1|base".toByteArray())
            throw AssertionError("AAD swap decrypted")
        } catch (e: AEADBadTagException) {
            // expected
        }

        val rt = GuardRuntime({ fixture("configs/t1_base.json") }, store, { 0L })
        rt.writeUser(fixture("configs/t1_user.json"))
        assertEquals(GuardConfigMode.FULL, rt.current().mode)
        val d = GuardRuntime({ fixture("configs/t1_base.json") }, store, { 0L })
            .decide(AndroidGuardChannel.SMS, "NBE", "Purchase EGP 10.00 card **4567")
        assertEquals("ignored_card", (d as GuardDecision.Drop).reason.wire)
    }
}
