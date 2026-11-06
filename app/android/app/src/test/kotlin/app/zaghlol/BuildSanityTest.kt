package app.zaghlol

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Placeholder JVM unit test proving the Gradle unit-test lane runs in CI.
 * Capture Guard and spool tests (JUnit + Robolectric) arrive with the native tasks.
 */
class BuildSanityTest {
    @Test
    fun mainActivityLivesInTheAppNamespace() {
        assertEquals("app.zaghlol.MainActivity", MainActivity::class.java.name)
    }
}
