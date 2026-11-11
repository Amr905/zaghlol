package app.zaghlol.spike.sms

import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.File

class SpikeMetricsTest {
    @Test
    fun rowHasStageDeltasFromReceive() {
        var now = 0L
        val f = File(tempDir(), "m.csv")
        val rx = 1_000_000_000L
        val m = SpikeMetrics(
            f,
            { 7 },
            { SpikeMetrics.Conditions(34, true, false, 40, 20_000) },
            { now },
            processStartNs = { rx - 750_000_000 },
        )
        val id = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        m.spooled(id, rx, rx + 5_000_000, rxWallMs = 1_762_000_000_123)
        m.enqueued(id, rx + 6_000_000)
        val cycle = SpikeMetrics.Cycle(SpikeMetrics.Path.COLD_PROCESS).apply {
            workerNs = rx + 100_000_000
            dartReadyNs = rx + 900_000_000
            dbOpenNs = rx + 1_000_000_000
        }
        now = rx + 1_100_000_000
        m.drained(id, rx, 7, cycle)
        now = rx + 1_200_000_000
        m.mark("parsed", listOf(id))
        now = rx + 1_300_000_000
        m.mark("commit", listOf(id))
        now = rx + 1_350_000_000
        m.mark("acked", listOf(id))
        val lines = f.readLines()
        assertEquals(SpikeMetrics.HEADER, lines[0])
        assertEquals("$id,cold_process,34,1,0,40,20000,1762000000123,-750,5,6,100,900,1000,1100,1200,1300,1350", lines[1])
    }

    @Test
    fun rowFromAnotherBootIsDiscarded() {
        val f = File(tempDir(), "m.csv")
        val boot = 7
        val m = SpikeMetrics(f, { boot }, { SpikeMetrics.Conditions(34, false, false, 10, 0) }, { 0 })
        val id = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        m.drained(id, 0, 6, null)
        m.mark("acked", listOf(id))
        assertFalse(f.exists())
    }

    @Test
    fun rowWithoutReceiveSideStampsLeavesWallAndProcessStartEmpty() {
        val f = File(tempDir(), "m.csv")
        val m = SpikeMetrics(f, { 7 }, { SpikeMetrics.Conditions(34, false, false, 10, 0) }, { 0 }, { 5 })
        val id = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
        m.drained(id, 0, 7, null) // spooled in an earlier process: no wall / process stamps
        m.mark("acked", listOf(id))
        assertEquals("$id,unknown,34,0,0,10,0,,,,,,,,0,,,0", f.readLines()[1])
    }
}
