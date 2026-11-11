package app.zaghlol.platform.capture.inbox

import android.database.Cursor

/**
 * The SMS inbox as [InboxReader] queries it (T-042 design note section 1).
 * Production: [ContentResolverInboxSource] over `Telephony.Sms.Inbox`
 * (`type = inbox` only) with [InboxReader.PROJECTION]. Tests: an in-memory
 * provider that evaluates the selection and counts the rows it materialises.
 *
 * [selection] is always [InboxReader.selection] (constant text, `?` only);
 * every value is in [selectionArgs]. May throw [SecurityException] (not
 * granted); a null cursor is a provider failure.
 */
fun interface InboxSource {
    fun query(selection: String, selectionArgs: Array<String>, sortOrder: String): Cursor?
}

/** Whether the build may read the inbox at all, and whether the user granted it. */
interface InboxAccess {
    /** `READ_SMS` is in the merged manifest (Sms builds only, ADR-004). */
    fun declared(): Boolean

    /** `READ_SMS` is granted now. */
    fun granted(): Boolean
}
