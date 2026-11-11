package app.zaghlol.platform.capture

import android.os.Bundle
import android.os.SystemClock
import android.provider.Telephony
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.KeystoreGuardUserCipher
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.KeystoreSpoolCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.SpoolRecord
import app.zaghlol.platform.spool.SpoolStore
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T-040 on a device (design note section 11, T-047 test plan 9): the **real**
 * `SmsReceiver` of the devSms debug build, real telephony (`adb emu sms
 * send`), real Keystore, driven by `.github/scripts/sms-spike-device.sh`.
 *
 * `-e t040Phase armed` (the script starts it in the background):
 * 1. Installs a test intake ([SmsCapture.installForTest]): the t1 golden base
 *   (test APK assets) plus [SmsCaptureScenario.REGISTRY_SENDER], spool
 *   `no_backup/spool-it-t040`, status `no_backup/capture-it-t040`, a
 *   counting scheduler. Writes the user part **through
 *   `AndroidCaptureHost.writeGuardConfig`** (the adapter path) and expects
 *   `guardState == FULL`.
 * 2. Takes a listing (path, size, mtime) of the app's data dirs once it is
 *   quiet, then reports `t040.ready=1`.
 * 3. The script sends the [SmsCaptureScenario] messages. The test waits for
 *   the three kept ones and asserts: exactly those, in order, each once and
 *   whole (the long Arabic one has 7 UCS-2 parts, AC3); channel `sms`; the
 *   inbox row equals the spooled `(source, body)` (accessor decision); the
 *   listing is unchanged except `spool-it-t040/` (no status file: a personal
 *   SMS, an OTP and an ignored card leave no trace, AC1); one enqueue per
 *   kept broadcast.
 * `-e t040Phase manual -e t040Sender <number>` (dual-SIM phone, EC-11): the
 * next SMS from that sender is spooled; `t040.simSlot` is reported.
 *
 * Synthetic messages only; nothing is logged; reported values are counts,
 * slots and flags.
 */
@RunWith(AndroidJUnit4::class)
class SmsReceiverEmulatorTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val phase: String? = args.getString("t040Phase")

    private val noBackup = target.noBackupFilesDir
    private val spoolDir = File(noBackup, "spool-it-t040")
    private val statusDir = File(noBackup, "capture-it-t040")
    private val guardDir = File(noBackup, "guard-it-t040")

    private fun report(key: String, value: String) =
        instrumentation.sendStatus(2, Bundle().apply { putString(key, value) })

    private fun fixture(path: String): ByteArray = instrumentation.context.assets.open(path).use { it.readBytes() }

    private class Rig(val intake: SmsIntake, val store: SpoolStore, val host: AndroidCaptureHost, val enqueues: AtomicInteger)

    private fun rig(): Rig {
        for (d in listOf(spoolDir, statusDir, guardDir)) d.deleteRecursively()
        val guard = GuardRuntime(
            { SmsCaptureScenario.base(fixture("configs/t1_base.json")) },
            GuardUserConfigStore(guardDir, KeystoreGuardUserCipher()),
            SystemClock::elapsedRealtime,
        )
        val status = CaptureStatusStore(File(statusDir, "status.bin"), KeystoreSpoolCipher())
        val store = SpoolStore(spoolDir, KeystoreSpoolCipher(), status)
        val enqueues = AtomicInteger()
        val intake = SmsIntake(
            CaptureIntake(AndroidGuardChannel.SMS, guard::decide, store, status, { enqueues.incrementAndGet() }),
            bootCount = { -1 },
        )
        val host = AndroidCaptureHost(
            engineId = 1,
            store = store,
            claim = SpoolClaim(),
            status = status,
            scheduler = null,
            guardWriter = GuardAdapters.writerFor(guard),
            guardState = GuardAdapters.stateFor(guard),
            device = null,
        )
        return Rig(intake, store, host, enqueues)
    }

    /** Files under the app's data dirs: relative path → (size, mtime). Directories by name only. */
    private fun listing(): Map<String, Pair<Long, Long>> {
        val data = target.dataDir
        val out = HashMap<String, Pair<Long, Long>>()
        for (name in listOf("files", "no_backup", "cache", "databases", "shared_prefs")) {
            val root = File(data, name)
            if (!root.exists()) continue
            root.walkTopDown().forEach { f ->
                val rel = f.relativeTo(data).path
                out[rel] = if (f.isFile) f.length() to f.lastModified() else -1L to -1L
            }
        }
        return out
    }

    private fun quietListing(): Map<String, Pair<Long, Long>> {
        var last = listing()
        repeat(10) {
            Thread.sleep(2_000)
            val next = listing()
            if (next == last) return next
            last = next
        }
        return last
    }

    private fun records(store: SpoolStore): List<SpoolRecord> =
        store.pendingIds().map { (store.read(it) as SpoolStore.ReadResult.Ok).record }

    private fun waitFor(timeoutMs: Long, done: () -> Boolean): Boolean {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < end) {
            if (done()) return true
            Thread.sleep(250)
        }
        return done()
    }

    /** The inbox rows of [address] (`address`, `body`), newest first. Needs READ_SMS (`install -g`). */
    private fun inbox(address: String): List<Pair<String, String>> {
        val rows = ArrayList<Pair<String, String>>()
        target.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY),
            "${Telephony.Sms.ADDRESS} = ?",
            arrayOf(address),
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            while (c.moveToNext()) rows += (c.getString(0) ?: "") to (c.getString(1) ?: "")
        }
        return rows
    }

    @Test
    fun armed() {
        assumeTrue("driven by sms-spike-device.sh only", phase == "armed")
        val rig = rig()
        val handle = SmsCapture.installForTest(rig.intake)
        try {
            rig.host.writeGuardConfig(SmsCaptureScenario.USER_JSON.toByteArray())
            assertEquals(GuardConfigState.FULL, rig.host.getSpoolStatus().guardState)
            val before = quietListing()
            report("t040.ready", "1")

            val kept = SmsCaptureScenario.KEPT
            assertTrue(
                "kept entries: ${rig.store.pendingCount()} of ${kept.size}",
                waitFor(120_000) { rig.store.pendingCount() >= kept.size },
            )
            Thread.sleep(10_000) // anything late or doubled shows up here
            val recs = records(rig.store)
            assertEquals("exactly the kept messages", kept.size, recs.size)
            assertEquals("source and body, in order, each once and whole", kept, recs.map { it.source to it.body })
            for (r in recs) assertEquals("sms", r.channel)
            val long = recs.single { it.body.startsWith(SmsCaptureScenario.LONG_START) }
            assertTrue(long.body.endsWith(SmsCaptureScenario.LONG_END))
            assertEquals(1, Regex(SmsCaptureScenario.LONG_START).findAll(recs.joinToString("|") { it.body }).count())
            report("t040.slot", recs.map { it.simSlot?.toString() ?: "null" }.toSet().joinToString(","))

            // Accessor decision: the inbox row equals the spooled (source, body).
            var inboxOk = 0
            for (r in recs) {
                val match = waitFor(30_000) { inbox(r.source).any { (a, b) -> a == r.source && b == r.body } }
                assertTrue("no inbox row equals the spooled message (${r.body.length} chars)", match)
                inboxOk++
            }
            report("t040.inbox", "$inboxOk/${recs.size}")

            // AC1: nothing else changed (no status file: no alert was raised).
            val after = listing()
            val spoolPrefix = spoolDir.relativeTo(target.dataDir).path
            val changed = (before.keys + after.keys)
                .filter { before[it] != after[it] }
                .filterNot { it == spoolPrefix || it.startsWith("$spoolPrefix/") }
                .sorted()
            assertEquals("files changed outside the test spool", emptyList<String>(), changed)
            assertFalse(File(statusDir, "status.bin").exists())
            assertEquals("one enqueue per kept broadcast", SmsCaptureScenario.KEPT_BROADCASTS, rig.enqueues.get())
            report("t040.result", "ok")
        } finally {
            handle.close()
            for (d in listOf(spoolDir, statusDir, guardDir)) d.deleteRecursively()
        }
    }

    @Test
    fun manualSimSlot() {
        assumeTrue("manual dual-SIM step only", phase == "manual")
        val sender = args.getString("t040Sender")
        assertNotNull("-e t040Sender <number>", sender)
        val rig = rig()
        val handle = SmsCapture.installForTest(rig.intake)
        try {
            val user = "{\"v\":1,\"baseRegistryVersion\":3,\"ignore\":[],\"userSenders\":[{\"value\":\"$sender\",\"ch\":\"sms\"}]}"
            rig.host.writeGuardConfig(user.toByteArray())
            report("t040.ready", "1")
            assertTrue("no SMS from the sender within 180 s", waitFor(180_000) { rig.store.pendingCount() >= 1 })
            report("t040.simSlot", records(rig.store).first().simSlot?.toString() ?: "null")
        } finally {
            handle.close()
            for (d in listOf(spoolDir, statusDir, guardDir)) d.deleteRecursively()
        }
    }
}
