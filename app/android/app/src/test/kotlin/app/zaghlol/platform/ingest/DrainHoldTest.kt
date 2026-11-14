package app.zaghlol.platform.ingest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** FU-194: the restore's drain hold (persisted, bounded, ordered with the engine start). */
class DrainHoldTest {
    private val dir: File = Files.createTempDirectory("fu194").toFile()
    private val file = File(dir, "capture/" + DrainHold.FILE_NAME)
    private var now = 1_800_000_000_000L
    private fun hold() = DrainHold(file) { now }

    @Test
    fun aHoldSurvivesANewProcessAndReleaseClearsIt() {
        hold().hold(60_000)
        val again = hold() // a new process reads the file
        assertTrue(again.isHeld())
        assertFalse(again.admitEngine())
        again.release()
        assertFalse(file.exists())
        assertFalse(hold().isHeld())
        assertTrue(hold().admitEngine())
    }

    /** Negative proof: an expired hold (e.g. left by a crashed restore) no longer blocks the drain. */
    @Test
    fun anExpiredHoldNoLongerBlocks() {
        val h = hold()
        h.hold(60_000)
        now += 60_000
        assertFalse(h.isHeld())
        assertTrue(h.admitEngine())
        assertFalse("also from the file in a new process", hold().isHeld())
    }

    @Test
    fun theTtlIsCappedAndAClockSetBackCountsAsExpired() {
        val h = hold()
        h.hold(Long.MAX_VALUE)
        now += DrainHold.MAX_TTL_MS
        assertFalse("capped at 10 min", h.isHeld())
        h.hold(60_000)
        now -= DrainHold.MAX_TTL_MS + 1 // the clock went back: expiry too far ahead
        assertFalse(h.isHeld())
    }

    @Test
    fun anUnreadableFileIsNotAHold() {
        file.parentFile!!.mkdirs()
        file.writeText("not a number")
        assertFalse(hold().isHeld())
    }

    @Test
    fun holdReportsTheAdmittedEngineUntilItIsGone() {
        val h = hold()
        assertTrue(h.admitEngine())
        assertTrue("an engine admitted before the hold is reported", h.hold(60_000))
        assertTrue(h.headlessActive())
        h.engineGone()
        assertFalse(h.headlessActive())
        assertFalse("no new engine while held", h.admitEngine())
        assertFalse(h.hold(60_000))
    }

    @Test
    fun aFailedWriteSetsNoHold() {
        file.parentFile!!.mkdirs()
        File(file.parentFile, file.name + ".tmp").mkdirs() // the tmp path is a directory: the write fails
        val h = hold()
        try {
            h.hold(60_000)
            throw AssertionError("expected an IOException")
        } catch (_: java.io.IOException) {
        }
        assertFalse(h.isHeld())
        assertEquals(false, file.exists())
    }
}
