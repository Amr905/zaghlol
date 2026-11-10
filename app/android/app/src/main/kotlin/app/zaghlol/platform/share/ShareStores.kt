package app.zaghlol.platform.share

import android.content.Context
import java.io.File

object ShareStores {
    /** `noBackupFilesDir/spool/files`: excluded from every backup path (T-165, platform-channels.md 1.3). */
    fun create(context: Context): ShareStore =
        ShareStore(File(context.noBackupFilesDir, "spool/files"), KeystoreShareCipher())
}
