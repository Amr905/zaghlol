package app.zaghlol.platform.launchtheme

import android.content.Context
import android.content.res.Configuration
import java.io.File

/**
 * T-224: the user's theme choice (light / dark / system, nothing else), kept in
 * a file under noBackupFilesDir (excluded from backup and device transfer,
 * T-165) so MainActivity can apply it before the first frame.
 */
object LaunchTheme {
    const val FILE = "launch_theme"
    private val ALLOWED = setOf("light", "dark", "system")

    /** The stored choice, or "system" when absent, unreadable or not allowed. */
    fun read(dir: File): String =
        try {
            File(dir, FILE).readText().trim().takeIf { it in ALLOWED } ?: "system"
        } catch (_: Exception) {
            "system"
        }

    /** Stores [value]; returns false (and writes nothing) unless it is allowed. */
    fun write(dir: File, value: String?): Boolean {
        if (value == null || value !in ALLOWED) return false
        return try {
            val tmp = File(dir, "$FILE.tmp")
            tmp.writeText(value)
            tmp.renameTo(File(dir, FILE))
        } catch (_: Exception) {
            false
        }
    }

    /** The uiMode night bits to force for [choice], or null to follow the system. */
    fun nightBits(choice: String): Int? =
        when (choice) {
            "dark" -> Configuration.UI_MODE_NIGHT_YES
            "light" -> Configuration.UI_MODE_NIGHT_NO
            else -> null
        }

    /** [base] with the stored choice forced, so theme and splash resources resolve in it. */
    fun wrap(base: Context): Context {
        val bits = nightBits(read(base.noBackupFilesDir)) ?: return base
        val config = Configuration(base.resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or bits
        return base.createConfigurationContext(config)
    }
}
