package app.zaghlol.platform.launchtheme

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LaunchThemeTest {
    private fun dir(): File = createTempDir("launch_theme")

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
