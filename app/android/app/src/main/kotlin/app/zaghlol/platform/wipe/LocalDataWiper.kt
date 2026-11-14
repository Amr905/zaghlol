package app.zaghlol.platform.wipe

import android.app.NotificationManager
import android.content.Context
import app.zaghlol.platform.notifications.NotificationPresenter
import androidx.work.WorkManager
import java.io.File
import java.security.KeyStore

/**
 * T-166 "Delete everything", native part (design note in T-166.md, step 8).
 * Dart has already closed the database and deleted the key slots under the
 * bootstrap lease; this removes what only native code can reach.
 *
 * Every part runs even when an earlier one failed; [wipe] throws
 * [WipeIncomplete] at the end if any part failed, so Dart keeps its
 * resume marker and the next launch runs the wipe again. Directory roots
 * are kept (only their contents go). Nothing here logs; no path or message
 * leaves this class.
 */
class LocalDataWiper(
    /** Directories whose contents are deleted (the roots stay). */
    private val roots: List<File>,
    /** Parts run before the files, in order (jobs, notifications, Guard, Keystore). */
    private val parts: List<() -> Unit>,
) {
    fun wipe() {
        var ok = true
        for (part in parts) {
            ok = attempt(part) && ok
        }
        for (root in roots) {
            ok = clearContents(root) && ok
        }
        if (!ok) throw WipeIncomplete()
    }

    private fun attempt(part: () -> Unit): Boolean = try {
        part()
        true
    } catch (e: Exception) {
        false
    }

    companion object {
        /**
         * Deletes everything inside [dir], never [dir] itself and never by
         * following a symlink out of it. True when nothing is left (or [dir]
         * does not exist).
         */
        fun clearContents(dir: File): Boolean {
            val children = dir.listFiles() ?: return !dir.exists()
            var ok = true
            for (child in children) {
                ok = deleteTree(child) && ok
            }
            return ok && (dir.listFiles()?.isEmpty() ?: !dir.exists())
        }

        private fun deleteTree(f: File): Boolean {
            val isLink = try {
                java.nio.file.Files.isSymbolicLink(f.toPath())
            } catch (e: Exception) {
                false
            }
            if (f.isDirectory && !isLink) {
                f.listFiles()?.forEach { deleteTree(it) }
            }
            return f.delete() || !f.exists()
        }

        /** Every AndroidKeyStore alias belongs to this app's uid: all go (no seat keys on Android, D-55). */
        fun deleteAllKeystoreAliases() {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            var failed = false
            for (alias in ks.aliases().toList()) {
                try {
                    ks.deleteEntry(alias)
                } catch (e: Exception) {
                    failed = true
                }
            }
            if (failed) throw WipeIncomplete()
        }

        /**
         * The production wiper. `databases/` (WorkManager's own store) and
         * `shared_prefs/` are not cleared: the app keeps no data there
         * (T-165 policy), and deleting a live WorkManager database would
         * corrupt it; its jobs are cancelled and pruned instead.
         */
        fun production(context: Context, forgetGuardUser: () -> Unit): LocalDataWiper {
            val app = context.applicationContext
            return LocalDataWiper(
                roots = listOf(app.filesDir, app.noBackupFilesDir, app.cacheDir),
                parts = listOf<() -> Unit>(
                    {
                        val wm = WorkManager.getInstance(app)
                        wm.cancelAllWork().result.get()
                        wm.pruneWork().result.get()
                        Unit
                    },
                    {
                        (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
                    },
                    // NOTIF-GW: pending quiet-hours alarms (text lives only in the alarm).
                    { NotificationPresenter(app).cancelAll() },
                    forgetGuardUser,
                    ::deleteAllKeystoreAliases,
                ),
            )
        }
    }
}

/** A part of the wipe failed. Carries nothing; no stack trace is filled. */
class WipeIncomplete : Exception() {
    override fun fillInStackTrace(): Throwable = this
}
