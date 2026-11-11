package app.zaghlol.platform.capture.inbox

import android.database.Cursor
import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.capture.InboxPage
import app.zaghlol.platform.capture.InboxQuery
import app.zaghlol.platform.capture.RawInboxMessage
import app.zaghlol.platform.guard.CaptureGuard
import app.zaghlol.platform.guard.GuardDecision
import java.time.Instant
import java.time.ZoneOffset

/**
 * `AndroidCaptureHostApi.queryInbox` (T-042 design note; platform-channels
 * section 2): a paged read of **allowlisted senders' inbox SMS only**.
 *
 * 1. `READ_SMS` not in the manifest (`*NoSms`) → `NOT_AVAILABLE`, the
 *    provider is never touched; more than [MAX_ADDRESSES] addresses →
 *    `INVALID_ARGUMENT`; not granted → `PERMISSION_DENIED`.
 * 2. Each requested address is kept only if the native Guard allowlists it
 *    ([CaptureGuard.senderKind]: registry, user, `alwaysCapture`; never sender
 *    hints), so a Dart bug can't widen the read. Each kept address is bound
 *    as its ASCII variants `{a, lower(a), upper(a)}` (the provider compares
 *    `address` byte for byte), at most [MAX_BOUND_VARIANTS] per query
 *    (chunks beyond; an address is never split).
 * 3. Selection [selection]: constant text and `?` only, sorted by `_id`;
 *    [pageSize][InboxQuery.pageSize] (1..[MAX_PAGE_SIZE]) counts rows **read**,
 *    kept or dropped, so each call's work and memory are bounded.
 * 4. Every row read is re-checked (address in the bound set and still
 *    allowlisted, `date > since`, `_id` past the cursor) before its body is
 *    read, then decided by the Guard **without** the rate limiter. Only keeps
 *    are returned.
 *
 * No state survives a call. Nothing is logged; errors are code-only
 * (`CaptureApiError(code, null, null)`); no message text, address or count
 * goes into an exception.
 */
class InboxReader(
    private val source: InboxSource,
    private val access: InboxAccess,
    /** The Guard to decide with (production: `GuardRuntime.current().guard`). */
    private val guard: () -> CaptureGuard,
    /** `sub_id` (≥ 0) to a SIM slot, or null when unknown. */
    private val simSlot: (Int) -> Long?,
    /** Wall clock in ms (the inbox `date` column is wall-clock time). */
    private val nowMs: () -> Long,
) {
    fun query(query: InboxQuery): InboxPage = try {
        queryUnsafe(query)
    } catch (e: CaptureApiError) {
        throw CaptureApiError(e.code, null, null)
    } catch (_: SecurityException) {
        throw CaptureApiError(PERMISSION_DENIED, null, null)
    } catch (_: Throwable) {
        throw CaptureApiError(IO_ERROR, null, null)
    }

    private fun queryUnsafe(query: InboxQuery): InboxPage {
        if (!access.declared()) throw apiError(NOT_AVAILABLE)
        val requested: List<*> = query.senderAddresses
        if (requested.size > MAX_ADDRESSES) throw apiError(INVALID_ARGUMENT)
        if (!access.granted()) throw apiError(PERMISSION_DENIED)

        val g = guard()
        val chunks = chunksOf(allowlisted(g, requested))
        if (chunks.isEmpty()) return LAST_EMPTY
        val since = query.sinceEpochMs
        val crc = InboxCursor.crcOf(chunks, since)
        val start = query.afterCursor?.let { InboxCursor.decode(it, crc, chunks.size) ?: throw apiError(INVALID_ARGUMENT) }
            ?: InboxCursor.Position(0, 0)

        val now = nowMs()
        if (since > now) return LAST_EMPTY
        val effectiveSince = maxOf(since, floorOf(now))
        val pageSize = query.pageSize.coerceIn(1, MAX_PAGE_SIZE.toLong()).toInt()

        val items = ArrayList<RawInboxMessage>()
        var read = 0
        var chunk = start.chunk
        var after = start.lastId
        while (chunk < chunks.size) {
            val bound = chunks[chunk]
            val scan = scanChunk(g, bound, effectiveSince, after, pageSize - read, items)
            read += scan.read
            if (!scan.exhausted) {
                // A full page: continue after the highest id read. No progress
                // means the provider ignores `_id > ?`; stop rather than loop.
                if (scan.maxId <= after) throw apiError(IO_ERROR)
                return InboxPage(items, InboxCursor.encode(chunk, scan.maxId, crc), read.toLong())
            }
            chunk++
            after = 0
        }
        return InboxPage(items, null, read.toLong())
    }

    private class Scan(val read: Int, val exhausted: Boolean, val maxId: Long)

    /** Reads at most [budget] rows of one chunk; appends Guard keeps to [out]. */
    private fun scanChunk(
        g: CaptureGuard,
        bound: List<String>,
        since: Long,
        after: Long,
        budget: Int,
        out: MutableList<RawInboxMessage>,
    ): Scan {
        val args = ArrayList<String>(bound.size + 2)
        args.addAll(bound)
        args.add(since.toString())
        args.add(after.toString())
        val boundSet = HashSet(bound)
        val cursor: Cursor = source.query(selection(bound.size), args.toTypedArray(), SORT_ORDER) ?: throw apiError(IO_ERROR)
        var read = 0
        var maxId = after
        var exhausted = false
        cursor.use { c ->
            val iId = c.getColumnIndexOrThrow(COL_ID)
            val iAddress = c.getColumnIndexOrThrow(COL_ADDRESS)
            val iBody = c.getColumnIndexOrThrow(COL_BODY)
            val iDate = c.getColumnIndexOrThrow(COL_DATE)
            val iSub = c.getColumnIndexOrThrow(COL_SUB_ID)
            while (read < budget) {
                if (!c.moveToNext()) {
                    exhausted = true
                    break
                }
                read++
                // Re-check every row against the query before its body is read
                // (an OEM provider that ignores part of the selection).
                if (c.isNull(iId)) continue
                val id = c.getLong(iId)
                if (id <= after) continue
                if (id > maxId) maxId = id
                if (c.isNull(iAddress) || c.isNull(iDate) || c.isNull(iBody)) continue
                val address = c.getString(iAddress) ?: continue
                if (address !in boundSet || g.senderKind(SMS, address) == null) continue
                val date = c.getLong(iDate)
                if (date <= since) continue
                val body = c.getString(iBody) ?: continue
                if (g.decide(SMS, address, body) !is GuardDecision.Keep) continue
                val slot = if (c.isNull(iSub)) null else c.getInt(iSub).takeIf { it >= 0 }?.let(simSlot)
                out += RawInboxMessage(address, body, date, slot, id.toString())
            }
        }
        return Scan(read, exhausted, maxId)
    }

    override fun toString(): String = "InboxReader"

    companion object {
        const val NOT_AVAILABLE = "NOT_AVAILABLE"
        const val PERMISSION_DENIED = "PERMISSION_DENIED"
        const val INVALID_ARGUMENT = "INVALID_ARGUMENT"
        const val IO_ERROR = "IO_ERROR"

        /** Most addresses per query; more is `INVALID_ARGUMENT`. */
        const val MAX_ADDRESSES = 1000

        /** Most rows read per call. */
        const val MAX_PAGE_SIZE = 500

        /**
         * Bound arguments per query. SQLite before 3.32 (API 26–29) allows
         * 999; two go to `date` and `_id`.
         */
        const val MAX_BOUND_ARGS = 900
        const val MAX_BOUND_VARIANTS = MAX_BOUND_ARGS - 2

        /** `since` is raised to now minus this many months (A-11: 24 months of history, plus one). */
        const val MAX_HISTORY_MONTHS = 25L

        const val SMS = "sms"
        const val COL_ID = "_id"
        const val COL_ADDRESS = "address"
        const val COL_BODY = "body"
        const val COL_DATE = "date"
        const val COL_SUB_ID = "sub_id"

        /** Never `content://sms` (that includes sent messages and drafts). */
        val PROJECTION: Array<String> get() = arrayOf(COL_ID, COL_ADDRESS, COL_BODY, COL_DATE, COL_SUB_ID)

        /** No `LIMIT` (strict-grammar providers may reject it); [MAX_PAGE_SIZE] bounds the rows read instead. */
        const val SORT_ORDER = "_id ASC"

        private val LAST_EMPTY get() = InboxPage(emptyList(), null, 0)

        /** The only selection text ever sent: built from constants, `?` for every value. */
        fun selection(variantCount: Int): String {
            require(variantCount in 1..MAX_BOUND_VARIANTS)
            val sb = StringBuilder("address IN (")
            repeat(variantCount) { i -> sb.append(if (i == 0) "?" else ",?") }
            return sb.append(") AND date > ? AND _id > ?").toString()
        }

        /** now − [MAX_HISTORY_MONTHS] calendar months (UTC). */
        internal fun floorOf(nowMs: Long): Long =
            Instant.ofEpochMilli(nowMs).atZone(ZoneOffset.UTC).minusMonths(MAX_HISTORY_MONTHS).toInstant().toEpochMilli()

        /** Requested addresses the Guard allowlists, distinct and sorted (deterministic cursor). */
        internal fun allowlisted(g: CaptureGuard, requested: List<*>): List<String> {
            val kept = java.util.TreeSet<String>()
            for (a in requested) {
                if (a !is String || a.isEmpty()) continue
                if (g.senderKind(SMS, a) != null) kept += a
            }
            return kept.toList()
        }

        /** ASCII-only case variants of [a] (no locale rules: `İ`, `ß` stay as they are). */
        internal fun variantsOf(a: String): List<String> = linkedSetOf(a, asciiLower(a), asciiUpper(a)).toList()

        /**
         * Groups each address's variants not bound before into chunks of at
         * most [MAX_BOUND_VARIANTS]; an address is never split.
         */
        internal fun chunksOf(addresses: List<String>): List<List<String>> {
            val seen = HashSet<String>()
            val chunks = ArrayList<List<String>>()
            var current = ArrayList<String>()
            for (a in addresses) {
                val group = variantsOf(a).filter { seen.add(it) }
                if (group.isEmpty()) continue
                if (current.size + group.size > MAX_BOUND_VARIANTS) {
                    chunks += current
                    current = ArrayList()
                }
                current.addAll(group)
            }
            if (current.isNotEmpty()) chunks += current
            return chunks
        }

        private fun asciiLower(s: String): String {
            val chars = s.toCharArray()
            for (i in chars.indices) if (chars[i] in 'A'..'Z') chars[i] = chars[i] + ('a' - 'A')
            return String(chars)
        }

        private fun asciiUpper(s: String): String {
            val chars = s.toCharArray()
            for (i in chars.indices) if (chars[i] in 'a'..'z') chars[i] = chars[i] - ('a' - 'A')
            return String(chars)
        }

        private fun apiError(code: String) = CaptureApiError(code, null, null)
    }
}
