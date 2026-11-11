package app.zaghlol.platform.spool

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * AC1 for real (T-039 design note section 11): two `am instrument` runs in
 * two processes, driven by `.github/scripts/sms-spike-device.sh`.
 *
 * - `-e spoolPhase write`: writes 20 entries, then halts the process
 *   (`Runtime.halt`, no shutdown hooks, no finally blocks) between the fsync
 *   and the rename of a 21st.
 * - `-e spoolPhase read` (new process): exactly the 20 entries decrypt, the
 *   21st does not exist as an entry, and the drain-time sweep removes its tmp.
 *
 * Without the argument both tests are skipped, so a plain
 * `connectedAndroidTest` run never halts.
 */
@RunWith(AndroidJUnit4::class)
class SpoolKillRecoveryTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val dir = File(context.noBackupFilesDir, "spool-it-kill")
    private val phase: String? = InstrumentationRegistry.getArguments().getString("spoolPhase")

    @Test
    fun phaseWrite() {
        assumeTrue(phase == "write")
        dir.deleteRecursively()
        var moves = 0
        val haltBefore21stRename = object : SpoolFileOps by DefaultSpoolFileOps {
            override fun move(from: File, to: File) {
                if (++moves == 21) Runtime.getRuntime().halt(0)
                DefaultSpoolFileOps.move(from, to)
            }
        }
        val store = SpoolStore(dir, KeystoreSpoolCipher(), files = haltBefore21stRename)
        repeat(21) { store.write(record("entry $it"), AdmissionClass.PRIORITY) }
        error("the process should have halted before the 21st rename")
    }

    @Test
    fun phaseRead() {
        assumeTrue(phase == "read")
        val store = SpoolStore(dir, KeystoreSpoolCipher())
        assertEquals(1, dir.list()!!.count { SpoolStore.isTmpName(it) })
        val ids = store.pendingIds()
        assertEquals(20, ids.size)
        val bodies = ids.map { (store.read(it) as SpoolStore.ReadResult.Ok).record.body }
        assertEquals((0 until 20).map { "entry $it" }, bodies)
        assertEquals(1, store.sweepTmp())
        assertTrue(dir.list()!!.none { it.endsWith(".tmp") })
        assertEquals(20, store.pendingIds().size)
        dir.deleteRecursively()
    }

    private fun record(body: String) = SpoolRecord("sms", "5550100", body, System.currentTimeMillis(), null, null, null, 0, -1)
}
