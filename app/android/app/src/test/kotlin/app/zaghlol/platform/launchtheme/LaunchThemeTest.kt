package app.zaghlol.platform.launchtheme

import java.io.File
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue

class LaunchThemeTest {
    private fun dir(): File = java.nio.file.Files.createTempDirectory("launch_theme").toFile()

    @Test
    fun isNightReadsOnlyTheNightBits() {
        val night = android.content.res.Configuration.UI_MODE_NIGHT_YES
        val day = android.content.res.Configuration.UI_MODE_NIGHT_NO
        val type = android.content.res.Configuration.UI_MODE_TYPE_NORMAL
        assertTrue(LaunchTheme.isNight(night or type))
        assertFalse(LaunchTheme.isNight(day or type))
        assertFalse(LaunchTheme.isNight(0))
    }

    @Test
    fun missingFileFollowsSystem() {
        assertEquals("system", LaunchTheme.read(dir()))
    }

    @Test
    fun roundTripsAllowedValues() {
        val d = dir()
        for (v in listOf("dark", "light", "system")) {
            assertTrue(LaunchTheme.write(d, v))
            assertEquals(v, LaunchTheme.read(d))
        }
    }

    @Test
    fun rejectsOtherValuesAndKeepsTheOldOne() {
        val d = dir()
        LaunchTheme.write(d, "dark")
        assertFalse(LaunchTheme.write(d, "purple"))
        assertFalse(LaunchTheme.write(d, null))
        assertEquals("dark", LaunchTheme.read(d))
    }

    @Test
    fun garbageOnDiskReadsAsSystem() {
        val d = dir()
        File(d, LaunchTheme.FILE).writeText("<script>")
        assertEquals("system", LaunchTheme.read(d))
    }
}
