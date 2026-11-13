package app.zaghlol.platform.capture

/** Synthetic notification fields that count every read; values are made up. */
class FakeFields(
    private val title: CharSequence? = null,
    private val text: CharSequence? = null,
    private val bigText: CharSequence? = null,
    private val lines: Array<CharSequence>? = null,
    private val throwOnRead: Boolean = false,
) : NotificationFields {
    var reads = 0
        private set

    private fun <T> read(v: T): T {
        reads++
        if (throwOnRead) throw IllegalStateException("ZG_CANARY_7731 unparcel")
        return v
    }

    override fun title() = read(title)

    override fun text() = read(text)

    override fun bigText() = read(bigText)

    override fun textLines() = read(lines)

    override fun toString(): String = "FakeFields"
}

class FakePosted(
    override val packageName: String?,
    val fields: FakeFields = FakeFields(title = "Bank", text = "Purchase EGP 10.00 card **1234"),
    override val flags: Int = 0,
) : PostedNotification {
    override fun fields(): NotificationFields = fields

    override fun toString(): String = "FakePosted"
}

/** A [CharSequence] that counts `toString()` calls (an over-long field must never be copied). */
class CountingChars(private val s: String) : CharSequence {
    var toStrings = 0
        private set
    override val length: Int get() = s.length

    override fun get(index: Int): Char = s[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = s.subSequence(startIndex, endIndex)

    override fun toString(): String {
        toStrings++
        return s
    }
}
