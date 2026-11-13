package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardFixtures
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.SoftwareGuardUserCipher
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.FlakySpoolCipher
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.SpoolLimits
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream

/**
 * T-043 design note section 10: the canaries `ZG_CANARY_7731` (title, text)
 * and `ZG_CANARY_PKG` (a registry package) travel filter, extractor, repeat
 * filter, intake and store, also with failing ciphers, a full spool, a
 * throwing scheduler and throwing fields. Nothing reaches stdout/stderr, an
 * exception, a result or a `toString`, and no file holds them in plaintext.
 */
class NotificationCanaryTest {
    private val canary = "ZG_CANARY_7731"
    private val pkg = "ZG_CANARY_PKG"
    private val out = ByteArrayOutputStream()
    private val err = ByteArrayOutputStream()
    private lateinit var oldOut: PrintStream
    private lateinit var oldErr: PrintStream

    @Before
    fun capture() {
        oldOut = System.out
        oldErr = System.err
        System.setOut(PrintStream(out, true))
        System.setErr(PrintStream(err, true))
    }

    @After
    fun restore() {
        System.setOut(oldOut)
        System.setErr(oldErr)
    }

    @Test
    fun canariesNeverLeak() {
        val root = tempDir()
        val base = String(GuardFixtures.t1Base, Charsets.UTF_8).replace("com.example.nbe", pkg).toByteArray()
        val guard = GuardRuntime({ base }, GuardUserConfigStore(File(root, "guard"), SoftwareGuardUserCipher()), { 0L })
        val status = CaptureStatusStore(File(root, "capture/status.bin"), FlakySpoolCipher(2, canary))
        val strings = ArrayList<String>()
        val errors = ArrayList<Throwable>()
        for (cipher in listOf(SoftwareSpoolCipher(), FlakySpoolCipher(0, "$canary $pkg", failEncrypt = true))) {
            val store = storeIn(File(root, "spool"), cipher = cipher, status = status, limits = SpoolLimits(maxEntries = 2))
            for (afterWrite in listOf<() -> Unit>({}, { throw IllegalStateException("$canary $pkg") })) {
                val intake = NotificationIntake(
                    admits = guard::admitsNotificationPackage,
                    intake = CaptureIntake(AndroidGuardChannel.NOTIFICATION, guard::decide, store, status, afterWrite),
                    recent = RecentNotifications({ 0L }),
                    bootCount = { throw IllegalStateException(canary) },
                )
                val posts = listOf(
                    FakePosted(pkg, FakeFields(title = canary, text = "$canary paid EGP 1.00 card **1234")),
                    FakePosted(pkg, FakeFields(title = canary, text = "$canary your OTP is 123456")),
                    FakePosted(pkg, FakeFields(title = canary, text = canary, throwOnRead = true)),
                    FakePosted(pkg, FakeFields(title = canary, bigText = "x".repeat(5_000) + canary)),
                    FakePosted("com.other.app", FakeFields(title = canary, text = canary)),
                )
                for (p in posts) {
                    try {
                        strings += intake.process(p, 1L, 2L).toString()
                    } catch (t: Throwable) {
                        errors += t
                    }
                    strings += p.toString()
                    strings += p.fields.toString()
                }
                strings += intake.toString()
            }
        }
        strings += NotificationItem(FakePosted(pkg), 1L, 2L).toString()
        strings += RecentNotifications({ 0L }).also { it.remember(pkg, canary) }.toString()
        strings += CapturedMessage(pkg, canary).toString()
        assertTrue("the intake throws nothing", errors.isEmpty())
        for (s in strings) assertFalse(s, s.contains("ZG_CANARY"))
        assertEquals("", out.toString() + err.toString())
        for (f in root.walkTopDown().filter { it.isFile }) {
            assertFalse(f.name, String(f.readBytes(), Charsets.ISO_8859_1).contains("ZG_CANARY"))
        }
        assertTrue("something was written", File(root, "spool").list().orEmpty().any { it.endsWith(".bin") })
    }
}
