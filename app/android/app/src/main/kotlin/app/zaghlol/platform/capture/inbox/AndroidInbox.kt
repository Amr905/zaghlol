package app.zaghlol.platform.capture.inbox

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.provider.Telephony
import app.zaghlol.platform.capture.SimSlot
import app.zaghlol.platform.guard.GuardRuntime

/** `Telephony.Sms.Inbox` (inbox rows only; never `content://sms`, which holds sent messages and drafts). */
class ContentResolverInboxSource(private val resolver: ContentResolver) : InboxSource {
    override fun query(selection: String, selectionArgs: Array<String>, sortOrder: String): Cursor? =
        resolver.query(Telephony.Sms.Inbox.CONTENT_URI, InboxReader.PROJECTION, selection, selectionArgs, sortOrder)
}

/** `READ_SMS` in the merged manifest (Sms builds only) and granted. */
class ContextInboxAccess(private val context: Context) : InboxAccess {
    override fun declared(): Boolean {
        val pm = context.packageManager
        val info: PackageInfo = if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        }
        return info.requestedPermissions?.contains(Manifest.permission.READ_SMS) == true
    }

    override fun granted(): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
}

/** Composition of the production reader. */
object InboxReaders {
    /**
     * The reader for the **UI** engine's `AndroidCaptureHost` (`inbox =`).
     * The headless engine's host gets none, so background work never reads
     * the inbox (FU-088).
     */
    fun forUiEngine(context: Context): InboxReader {
        val app = context.applicationContext
        return InboxReader(
            source = ContentResolverInboxSource(app.contentResolver),
            access = ContextInboxAccess(app),
            guard = { GuardRuntime.get(app).current().guard },
            simSlot = SimSlot::of,
            nowMs = System::currentTimeMillis,
        )
    }
}
