package app.zaghlol.platform.share

import android.content.Context
import java.io.File

object ShareStores {
    /**
     * `noBackupFilesDir/share/`: excluded from every backup path (T-165). It is
     * deliberately not under `spool/` (F8): the share store purges by age,
     * while T-039 spool entries are deleted only on ack.
     */
    fun dir(context: Context): File = File(context.noBackupFilesDir, "share")

    fun create(context: Context): ShareStore = ShareStore(dir(context), KeystoreShareCipher())
}
