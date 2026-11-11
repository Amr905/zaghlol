package app.zaghlol.platform.capture.inbox

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.provider.Telephony
import android.telephony.SubscriptionManager
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

/**
 * `sub_id` to the SIM slot index: `SubscriptionManager.getSlotIndex` on API
 * 29+ (no permission needed); below it null (the older lookups need
 * `READ_PHONE_STATE`, which the app does not request). One mapping for live
 * capture and the inbox; T-040 should reuse it.
 */
object SimSlot {
    fun of(subId: Int): Long? {
        if (subId < 0 || Build.VERSION.SDK_INT < 29) return null
        val slot = SubscriptionManager.getSlotIndex(subId)
        return if (slot >= 0) slot.toLong() else null
    }
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
