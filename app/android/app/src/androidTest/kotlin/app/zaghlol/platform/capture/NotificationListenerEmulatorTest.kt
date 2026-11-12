package app.zaghlol.platform.capture

import android.os.Bundle
import android.os.SystemClock
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
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T-043 on a device (design note section 10): the **real**
 * `BankNotificationListener` of the devSms debug build, posts from the shell
 * package (`cmd notification post`), real Keystore; driven by
 * `.github/scripts/sms-spike-device.sh` (phase t043).
 *
 * `-e t043Phase armed`: a test intake ([NotificationCapture.installForTest]) with the t1
 * golden base and the user part `userSenders: [com.android.shell on
 * notification]`, written through `AndroidCaptureHost.writeGuardConfig`; spool
 * `no_backup/spool-it-t043`. Reports `t043.ready=1`; the script then posts a
 * debit, the same debit again (repeat), the same tag with new text (update)
 * and an OTP. Expects exactly two entries (first and update), body ==
 * `title + "\n" + text`, source `com.android.shell`, channel `notification`,
 * one enqueue each.
 *
 * `-e t043Phase denied` (AC2): the user part has no shell package; the script
 * posts one debit. Expects no entry and the data-dir listing unchanged.
 *
 * Synthetic messages only; nothing is logged; reported values are counts and flags.
 */
@RunWith(AndroidJUnit4::class)
class NotificationListenerEmulatorTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val phase: String? = InstrumentationRegistry.getArguments().getString("t043Phase")

    private val noBackup = target.noBackupFilesDir
    private val spoolDir = File(noBackup, "spool-it-t043")
    private val statusDir = File(noBackup, "capture-it-t043")
    private val guardDir = File(noBackup, "guard-it-t043")

    private fun report(key: String, value: String) = instrumentation.sendStatus(2, Bundle().apply { putString(key, value) })

    private fun fixture(path: String): ByteArray = instrumentation.context.assets.open(path).use { it.readBytes() }

    private class Rig(val intake: NotificationIntake, val store: SpoolStore, val host: AndroidCaptureHost, val enqueues: AtomicInteger)

    private fun rig(): Rig {
        for (d in listOf(spoolDir, statusDir, guardDir)) d.deleteRecursively()
        val guard = GuardRuntime(
            { fixture("configs/t1_base.json") },
            GuardUserConfigStore(guardDir, KeystoreGuardUserCipher()),
            SystemClock::elapsedRealtime,
        )
        val status = CaptureStatusStore(File(statusDir, "status.bin"), KeystoreSpoolCipher())
        val store = SpoolStore(spoolDir, KeystoreSpoolCipher(), status)
        val enqueues = AtomicInteger()
        val intake = NotificationIntake(
            admits = guard::admitsNotificationPackage,
            intake = CaptureIntake(AndroidGuardChannel.NOTIFICATION, guard::decide, store, status, { enqueues.incrementAndGet() }),
            recent = RecentNotifications(SystemClock::elapsedRealtime),
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

    private fun listing(): Map<String, Pair<Long, Long>> {
        val data = target.dataDir
        val out = HashMap<String, Pair<Long, Long>>()
        for (name in listOf("files", "no_backup", "cache", "databases", "shared_prefs")) {
            val root = File(data, name)
            if (!root.exists()) continue
            root.walkTopDown().forEach { f ->
                out[f.relativeTo(data).path] = if (f.isFile) f.length() to f.lastModified() else -1L to -1L
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

    private fun waitFor(timeoutMs: Long, done: () -> Boolean): Boolean {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < end) {
            if (done()) return true
            Thread.sleep(250)
        }
        return done()
    }

    private fun records(store: SpoolStore): List<SpoolRecord> =
        store.pendingIds().map { (store.read(it) as SpoolStore.ReadResult.Ok).record }

    private fun userJson(withShell: Boolean): String {
        val senders = if (withShell) "[{\"value\":\"com.android.shell\",\"ch\":\"notification\"}]" else "[]"
        return "{\"v\":1,\"baseRegistryVersion\":3,\"ignore\":[],\"userSenders\":$senders}"
    }

    @Test
    fun armed() {
        assumeTrue("driven by sms-spike-device.sh only", phase == "armed")
        val rig = rig()
        val handle = NotificationCapture.installForTest(rig.intake)
        try {
            rig.host.writeGuardConfig(userJson(true).toByteArray())
            quietListing()
            report("t043.ready", "1")
            assertTrue("kept entries: ${rig.store.pendingCount()} of 2", waitFor(90_000) { rig.store.pendingCount() >= 2 })
            Thread.sleep(10_000) // the repeat and the OTP would show up here
            val recs = records(rig.store).sortedBy { it.receivedAtMs }
            assertEquals("first + update only (repeat deduped, OTP dropped)", 2, recs.size)
            for (r in recs) {
                assertEquals("notification", r.channel)
                assertEquals("com.android.shell", r.source)
            }
            assertEquals(EXPECTED_FIRST, recs[0].body)
            assertEquals(EXPECTED_UPDATE, recs[1].body)
            assertEquals(2, rig.enqueues.get())
            report("t043.result", "ok")
        } finally {
            handle.close()
            for (d in listOf(spoolDir, statusDir, guardDir)) d.deleteRecursively()
        }
    }

    @Test
    fun denied() {
        assumeTrue("driven by sms-spike-device.sh only", phase == "denied")
        val rig = rig()
        val handle = NotificationCapture.installForTest(rig.intake)
        try {
            rig.host.writeGuardConfig(userJson(false).toByteArray())
            val before = quietListing()
            report("t043.ready", "1")
            Thread.sleep(25_000) // the script posts one debit from the shell package meanwhile
            assertEquals("no entry for a package that is not in the registry", 0, rig.store.pendingCount())
            assertEquals("no enqueue", 0, rig.enqueues.get())
            assertEquals("the data dirs are unchanged (AC2)", before, listing())
            report("t043.result", "ok")
        } finally {
            handle.close()
            for (d in listOf(spoolDir, statusDir, guardDir)) d.deleteRecursively()
        }
    }

    companion object {
        /** `.github/scripts/sms-spike-device.sh` posts exactly these (title, text); keep in sync. */
        const val TITLE = "SYNTH BANK"
        const val TEXT_FIRST = "Debit EGP 150.00 card 4321 at SYNTH SHOP"
        const val TEXT_UPDATE = "Debit EGP 150.00 card 4321 at SYNTH SHOP 2"
        const val EXPECTED_FIRST = "$TITLE\n$TEXT_FIRST"
        const val EXPECTED_UPDATE = "$TITLE\n$TEXT_UPDATE"
    }
}
