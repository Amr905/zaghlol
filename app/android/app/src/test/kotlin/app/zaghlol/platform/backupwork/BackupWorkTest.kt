package app.zaghlol.platform.backupwork

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupWorkTest {
    private fun mark() = BackupDueMark(File(java.nio.file.Files.createTempDirectory("bw").toFile(), "backupwork/due"))

    @Test
    fun dueIsReadOnceThenCleared() {
        val m = mark()
        assertFalse(m.take())
        m.set()
        m.set() // firing twice before the app opens is still one mark
        assertTrue(m.take())
        assertFalse(m.take())
    }

    @Test
    fun clearDropsAPendingMark() {
        val m = mark()
        m.set()
        m.clear()
        assertFalse(m.take())
    }

    @Test
    fun flexIsAQuarterOfThePeriodWithTheSystemMinimum() {
        assertEquals(360L, BackupWorkPlan.flexMinutes(1))
        assertEquals(2520L, BackupWorkPlan.flexMinutes(7))
        assertEquals(10800L, BackupWorkPlan.flexMinutes(30))
    }

    @Test
    fun onlyDailyWeeklyMonthlyAreAllowed() {
        assertEquals(setOf(1, 7, 30), BackupWorkPlan.ALLOWED_DAYS)
    }
}
