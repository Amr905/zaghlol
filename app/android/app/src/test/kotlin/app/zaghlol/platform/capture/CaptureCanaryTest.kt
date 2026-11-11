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
 * T-040 design note section 11: the body canary `ZG_CANARY_7731` and the
 * sender canary `ZG_CANARY_SRC` travel assembler → intake → store → status,
 * also with failing ciphers, a full spool, a throwing scheduler and a
 * throwing Guard; nothing reaches stdout/stderr, an exception, a result or
 * a `toString`, and no file holds them in plaintext.
 */
class CaptureCanaryTest {
    private val body = "ZG_CANARY_7731"
    private val sender = "ZG_CANARY_SRC"
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

    private fun clean(s: String?) = s == null || (!s.contains("ZG_CANARY"))

    @Test
    fun canariesNeverLeak() {
        val root = tempDir()
        val guard = GuardRuntime({ GuardFixtures.t1Base }, GuardUserConfigStore(File(root, "guard"), SoftwareGuardUserCipher()), { 0L })
        // The canary sender is a user sender (kept), the canary body travels in every message.
        guard.writeUser(
            """{"v":1,"baseRegistryVersion":3,"ignore":[],"userSenders":[{"value":"$sender","ch":"sms"}]}""".toByteArray(),
        )
        val status = CaptureStatusStore(File(root, "capture/status.bin"), FlakySpoolCipher(2, body))
        val strings = ArrayList<String>()
        val errors = ArrayList<Throwable>()
        val ciphers = listOf(
            SoftwareSpoolCipher(),
            FlakySpoolCipher(0, "$body $sender", failEncrypt = true),
        )
        for ((i, cipher) in ciphers.withIndex()) {
            val store = storeIn(File(root, "spool"), cipher = cipher, status = status, limits = SpoolLimits(maxEntries = 2))
            for (afterWrite in listOf<() -> Unit>({}, { throw IllegalStateException("$body $sender") })) {
                val intake = SmsIntake(
                    CaptureIntake(AndroidGuardChannel.SMS, guard::decide, store, status, afterWrite),
                    bootCount = { throw IllegalStateException(body) },
                )
                for (parts in listOf(
                    listOf(SmsPart(sender, "$body paid EGP 1.00 ", 1), SmsPart(sender, "at SHOP $i", 1)),
                    listOf(SmsPart(sender, "$body your OTP is 123456", 1)),
                    listOf(SmsPart("Mom", "$body see you", 1)),
                    listOf(SmsPart(sender, "x".repeat(5_000) + body, 1)),
                )) {
                    try {
                        val r = intake.process(parts, 1L, 2L, 0)
                        strings += r.toString()
                    } catch (t: Throwable) {
                        errors += t
                    }
                    strings += parts.toString()
                    strings += SmsAssembler.assemble(parts).toString()
                }
                strings += intake.toString()
            }
        }
        // A throwing Guard.
        val throwing = CaptureIntake(AndroidGuardChannel.SMS, { _, _, _ -> throw IllegalStateException("$body $sender") }, storeIn(tempDir()), status, {})
        strings += throwing.process(listOf(CapturedMessage(sender, body)), ReceiveStamp(1, 2, 3, null)).toString()
        strings += CapturedMessage(sender, body).toString()
        strings += ReceiveStamp(1, 2, 3, 1).toString()
        try {
            status.read()
        } catch (t: Throwable) {
            errors += t
        }

        assertTrue("the intake throws nothing", errors.none { it !is app.zaghlol.platform.spool.CaptureStatusUnavailableException })
        for (t in errors) assertTrue(clean(t.toString()) && clean(t.message))
        for (s in strings) assertTrue(s, clean(s))
        assertTrue(clean(out.toString()))
        assertTrue(clean(err.toString()))
        assertEquals("", out.toString() + err.toString())
        for (f in root.walkTopDown().filter { it.isFile }) {
            val raw = String(f.readBytes(), Charsets.ISO_8859_1)
            assertFalse(f.name, raw.contains("ZG_CANARY"))
        }
        assertTrue("something was written", File(root, "spool").list().orEmpty().any { it.endsWith(".bin") })
    }
}
