package app.zaghlol

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.os.ParcelFileDescriptor

// T-165 NEGATIVE CONTROL ONLY (task/T-165-proof, never merge): a custom agent
// that the aapt2 assertion must reject.
class T165ProofBackupAgent : BackupAgent() {
    override fun onBackup(
        oldState: ParcelFileDescriptor?,
        data: BackupDataOutput?,
        newState: ParcelFileDescriptor?,
    ) {}

    override fun onRestore(
        data: BackupDataInput?,
        appVersionCode: Int,
        newState: ParcelFileDescriptor?,
    ) {}
}
