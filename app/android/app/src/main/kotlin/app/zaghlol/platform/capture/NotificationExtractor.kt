package app.zaghlol.platform.capture

import android.app.Notification
import app.zaghlol.platform.guard.rethrowIfFatal

/**
 * The four extras the listener reads (T-043 design note section 5). A seam so
 * a JVM test can count reads and throw. Implementations never print a value.
 */
interface NotificationFields {
    fun title(): CharSequence?

    fun text(): CharSequence?

    fun bigText(): CharSequence?

    fun textLines(): Array<CharSequence>?
}

/**
 * A posted notification as the listener sees it (seam over
 * `StatusBarNotification`). [packageName] and [flags] are cheap, extras-free
 * reads allowed on the main thread; [fields] touches the extras and is called
 * only after the package was admitted, on the intake thread. `toString`
 * prints nothing (package names are treated as sensitive).
 */
interface PostedNotification {
    val packageName: String?
    val flags: Int

    fun fields(): NotificationFields
}

/** Main-thread filter of `onNotificationPosted` (design note section 2): no I/O, no extras. */
object NotificationFilter {
    private const val SKIPPED_FLAGS = Notification.FLAG_GROUP_SUMMARY or Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE

    /** False for our own notification, a group summary, an ongoing or a foreground-service notification. */
    fun accepts(posted: PostedNotification, ownPackage: String): Boolean {
        val pkg = posted.packageName ?: return false
        if (pkg == ownPackage) return false
        return posted.flags and SKIPPED_FLAGS == 0
    }
}

/**
 * Title and content of a notification into the one body the Guard and the
 * parsers see (design note section 5): `title + "\n" + content` when both
 * are non-blank, else the non-blank one; content is `EXTRA_BIG_TEXT`, else
 * `EXTRA_TEXT`, else `EXTRA_TEXT_LINES` joined with `\n`. Lengths are checked
 * on the `CharSequence` **before** `toString()`. Any read failure (lazy
 * extras unparcelling) skips the notification silently. No trimming: the
 * Guard folds. Registry notification templates and fixtures use this exact
 * shape.
 */
object NotificationExtractor {
    const val MAX_TITLE = 256
    const val MAX_CONTENT = 4_000

    /** The body, or null when there is nothing to decide (blank, too long, unreadable). */
    fun extract(fields: NotificationFields): String? = try {
        extractUnsafe(fields)
    } catch (t: Throwable) {
        rethrowIfFatal(t)
        null
    }

    private fun extractUnsafe(f: NotificationFields): String? {
        val title = f.title()
        if (title != null && title.length > MAX_TITLE) return null
        val big = f.bigText()
        val text = f.text()
        val content: CharSequence? = when {
            big != null && !big.isBlank() -> big
            text != null && !text.isBlank() -> text
            else -> joinLines(f.textLines())
        }
        if (content != null && content.length > MAX_CONTENT) return null
        val hasTitle = title != null && !title.isBlank()
        val hasContent = content != null && !content.isBlank()
        return when {
            hasTitle && hasContent -> title.toString() + "\n" + content.toString()
            hasTitle -> title.toString()
            hasContent -> content.toString()
            else -> null
        }
    }

    /** Lines joined with `\n`; null (not "too long") past the cap is handled by the caller's length check. */
    private fun joinLines(lines: Array<CharSequence>?): CharSequence? {
        if (lines == null || lines.isEmpty()) return null
        var total = lines.size - 1
        for (l in lines) {
            total += l.length
            if (total > MAX_CONTENT) return OverLong
        }
        return lines.joinToString("\n") { it.toString() }
    }

    /** Marker for "lines exceed the cap" (length above [MAX_CONTENT], never printed). */
    private object OverLong : CharSequence {
        override val length: Int = MAX_CONTENT + 1

        override fun get(index: Int): Char = ' '

        override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = this

        override fun toString(): String = ""
    }
}
