package app.zaghlol.platform.capture.inbox

import android.content.ContentResolver
import android.database.CharArrayBuffer
import android.database.ContentObserver
import android.database.Cursor
import android.database.DataSetObserver
import android.net.Uri
import android.os.Bundle
import app.zaghlol.platform.guard.CaptureGuard
import app.zaghlol.platform.guard.GuardConfig

/**
 * T-042 test support, shared by the JVM tests (`src/test`) and the
 * instrumented suite (`src/androidTest`). Synthetic data only.
 */
object InboxTestConfig {
    const val CANARY = "ZG_CANARY_7731"

    /** The emulator's test sender (`adb emu sms send 5550100 …`). */
    const val EMU_SENDER = "5550100"

    /**
     * A small Guard base: exact senders `5550100`, `nbe`; a regex sender
     * `^cib-(?:egy|alert)$` and `^zb[0-9]{4}$` (chunking tests); sender hint
     * `bank` (not an allowlist); `alwaysCapture` `bdc-alert`; the global OTP
     * pattern; an `nbe` promo pattern; rate 20 per sender per minute.
     */
    val BASE = """
        {"v":4,"registryVersion":3,
         "senders":[
           {"match":"exact","value":"5550100","inst":"zt"},
           {"match":"exact","value":"nbe","inst":"nbe"},
           {"match":"regex","value":"^cib-(?:egy|alert)${'$'}","inst":"cib"},
           {"match":"regex","value":"^zb[0-9]{4}${'$'}","inst":"zb"}],
         "packages":[{"value":"com.example.nbe","inst":"nbe"}],
         "wallet":[{"name":"nbe","inst":"nbe"}],
         "drop":{
           "global":["(?:^|[^a-z])(?:otp|one[- ]?time[- ]pass(?:word|code)|(?:verification|verify|security|activation|login) code|passcode)(?:[^a-z0-9][^0-9]{0,30})?[0-9]{4,8}(?:${'$'}|[^0-9.,]|[.,]${'$'}|[.,][^0-9])"],
           "byInst":{"nbe":["(?:^|[^a-z])offer(?:${'$'}|[^a-z])"]}},
         "last4":{"nbe":["\\*\\*([0-9]{4})"],"*":["(?:card|account) \\*([0-9]{4})"]},
         "generic":{"senderHints":["bank"],"bodyHints":["egp ?[0-9]"],"alwaysCapture":["bdc-alert"]},
         "shortcutKeywords":["debited"],
         "rate":{"perSenderPerMin":20}}
    """.trimIndent()

    /** User part: sender `mycoop` (sms), ignore `nbe` card 4567 on sms. */
    val USER = """
        {"v":1,"baseRegistryVersion":3,
         "ignore":[{"inst":"nbe","last4":"4567","ch":"sms"}],
         "userSenders":[{"value":"mycoop","ch":"sms"}]}
    """.trimIndent()

    fun guard(): CaptureGuard {
        val load = GuardConfig.parse(BASE.toByteArray(), USER.toByteArray())
        return CaptureGuard(checkNotNull(load.config) { "test guard config did not parse: $load" })
    }
}

/** One synthetic inbox row; the body is produced on demand (lazy sources). `toString` prints the id only. */
class InboxRow(
    val id: Long,
    val address: String?,
    val date: Long?,
    val subId: Int? = 1,
    private val bodyOf: () -> String?,
) {
    constructor(id: Long, address: String?, date: Long?, body: String?, subId: Int? = 1) :
        this(id, address, date, subId, { body })

    fun body(): String? = bodyOf()

    override fun toString(): String = "InboxRow($id)"
}

/**
 * An in-memory SMS inbox provider. Evaluates the reader's selection (the
 * template is checked: anything else fails) over [rowAt] for ids in
 * ascending order, or returns every row when [ignoreSelection] (an OEM
 * provider that ignores it). Counts every row it **materialises** into a
 * cursor ([materialisedByAddress]), lazily, without holding them.
 */
class FakeInboxSource(private val count: Int, private val rowAt: (Int) -> InboxRow) : InboxSource {
    constructor(rows: List<InboxRow>) : this(rows.size, rows.sortedBy { it.id }::get)

    var ignoreSelection = false
    var failWith: Throwable? = null
    var returnNull = false
    val queries = ArrayList<Pair<String, List<String>>>()
    val materialisedByAddress = HashMap<String?, Int>()
    var materialised = 0L
    var openCursors = 0

    override fun query(selection: String, selectionArgs: Array<String>, sortOrder: String): Cursor? {
        failWith?.let { throw it }
        queries += selection to selectionArgs.toList()
        if (sortOrder != InboxReader.SORT_ORDER) throw AssertionError("unexpected sort order")
        val n = selectionArgs.size - 2
        if (n < 1 || selection != InboxReader.selection(n)) throw AssertionError("selection is not the template")
        if (returnNull) return null
        val addresses = selectionArgs.copyOfRange(0, n).toHashSet()
        val since = selectionArgs[n].toLong()
        val after = selectionArgs[n + 1].toLong()
        val matches = (0 until count).asSequence().map(rowAt).filter { r ->
            ignoreSelection ||
                (r.address in addresses && r.date != null && r.date > since && r.id > after)
        }.map { r ->
            materialised++
            materialisedByAddress[r.address] = (materialisedByAddress[r.address] ?: 0) + 1
            r
        }
        openCursors++
        return SequenceCursor(matches.iterator()) { openCursors-- }
    }
}

/** A forward-only cursor over [rows] with the reader's projection. Holds one row at a time. */
class SequenceCursor(private val rows: Iterator<InboxRow>, private val onClose: () -> Unit) : Cursor {
    private var current: InboxRow? = null
    private var position = -1
    private var closed = false

    private fun row(): InboxRow = current ?: throw IllegalStateException("no row")

    override fun moveToNext(): Boolean {
        check(!closed)
        if (!rows.hasNext()) {
            current = null
            position++
            return false
        }
        current = rows.next()
        position++
        return true
    }

    override fun getColumnIndexOrThrow(columnName: String): Int =
        COLUMNS.indexOf(columnName).also { require(it >= 0) { "no such column" } }

    override fun getColumnIndex(columnName: String): Int = COLUMNS.indexOf(columnName)

    override fun getColumnName(columnIndex: Int): String = COLUMNS[columnIndex]

    override fun getColumnNames(): Array<String> = COLUMNS.toTypedArray()

    override fun getColumnCount(): Int = COLUMNS.size

    private fun value(i: Int): Any? {
        val r = row()
        return when (i) {
            0 -> r.id
            1 -> r.address
            2 -> r.body()
            3 -> r.date
            4 -> r.subId
            else -> throw IllegalArgumentException("column")
        }
    }

    override fun isNull(columnIndex: Int): Boolean = when (columnIndex) {
        2 -> false // the body is read lazily; a null body is reported by getString
        else -> value(columnIndex) == null
    }

    override fun getString(columnIndex: Int): String? = value(columnIndex)?.toString()

    override fun getLong(columnIndex: Int): Long = (value(columnIndex) as Number).toLong()

    override fun getInt(columnIndex: Int): Int = (value(columnIndex) as Number).toInt()

    override fun getShort(columnIndex: Int): Short = getInt(columnIndex).toShort()

    override fun getFloat(columnIndex: Int): Float = throw UnsupportedOperationException()

    override fun getDouble(columnIndex: Int): Double = throw UnsupportedOperationException()

    override fun getBlob(columnIndex: Int): ByteArray = throw UnsupportedOperationException()

    override fun getType(columnIndex: Int): Int = throw UnsupportedOperationException()

    override fun copyStringToBuffer(columnIndex: Int, buffer: CharArrayBuffer?) = throw UnsupportedOperationException()

    override fun close() {
        if (!closed) {
            closed = true
            onClose()
        }
    }

    override fun isClosed(): Boolean = closed

    // Not used by the reader (getCount would force the whole result).
    override fun getCount(): Int = throw UnsupportedOperationException("getCount")

    override fun getPosition(): Int = position

    override fun move(offset: Int): Boolean = throw UnsupportedOperationException()

    override fun moveToPosition(position: Int): Boolean = throw UnsupportedOperationException()

    override fun moveToFirst(): Boolean = throw UnsupportedOperationException()

    override fun moveToLast(): Boolean = throw UnsupportedOperationException()

    override fun moveToPrevious(): Boolean = throw UnsupportedOperationException()

    override fun isFirst(): Boolean = position == 0

    override fun isLast(): Boolean = throw UnsupportedOperationException()

    override fun isBeforeFirst(): Boolean = position < 0

    override fun isAfterLast(): Boolean = position >= 0 && current == null

    @Deprecated("Deprecated in Java")
    override fun deactivate() = Unit

    @Deprecated("Deprecated in Java")
    override fun requery(): Boolean = false

    override fun registerContentObserver(observer: ContentObserver?) = Unit

    override fun unregisterContentObserver(observer: ContentObserver?) = Unit

    override fun registerDataSetObserver(observer: DataSetObserver?) = Unit

    override fun unregisterDataSetObserver(observer: DataSetObserver?) = Unit

    override fun setNotificationUri(cr: ContentResolver?, uri: Uri?) = Unit

    override fun getNotificationUri(): Uri? = null

    override fun getWantsAllOnMoveCalls(): Boolean = false

    override fun setExtras(extras: Bundle?) = Unit

    override fun getExtras(): Bundle = throw UnsupportedOperationException()

    override fun respond(extras: Bundle?): Bundle = throw UnsupportedOperationException()

    override fun toString(): String = "SequenceCursor"

    companion object {
        val COLUMNS = listOf("_id", "address", "body", "date", "sub_id")
    }
}

/** Access switches. */
class FakeInboxAccess(var declared: Boolean = true, var granted: Boolean = true) : InboxAccess {
    override fun declared() = declared

    override fun granted() = granted
}

/** AC2: 10,000 rows of 4,000-char bodies, each built on demand (the source holds none of them). */
object InboxRow10k {
    const val BODY_LENGTH = CaptureGuard.MAX_BODY_LENGTH
    private val PAD = "x".repeat(BODY_LENGTH)

    fun row(i: Int, date: Long, address: String = "NBE"): InboxRow = InboxRow(i + 1L, address, date, 1) {
        val head = "Purchase EGP ${i % 997}.00 at SYNTH SHOP $i "
        head + PAD.substring(0, BODY_LENGTH - head.length)
    }
}
