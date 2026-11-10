package app.zaghlol.platform.spool

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-060 review C1: the spool key is TEE-backed only and never requests StrongBox. */
class SpoolKeySpecTest {
    private fun source(): String {
        val rel = "src/main/kotlin/app/zaghlol/platform/spool/SpoolKey.kt"
        val f = listOf(File(rel), File("app/$rel"), File("app/android/app/$rel")).first { it.exists() }
        return f.readText()
    }

    @Test
    fun policyDoesNotRequestStrongBox() {
        assertFalse(SpoolKey.REQUEST_STRONGBOX)
    }

    @Test
    fun keyGenerationCodeNeverCallsStrongBoxApis() {
        val code = source().lines().filterNot { it.trim().startsWith("*") || it.trim().startsWith("//") || it.trim().startsWith("/**") }
            .joinToString("\n")
        assertFalse(code.contains("setIsStrongBoxBacked"))
        assertFalse(code.contains("StrongBoxUnavailable"))
        assertTrue(code.contains("zaghlol_spool_v1"))
    }
}
