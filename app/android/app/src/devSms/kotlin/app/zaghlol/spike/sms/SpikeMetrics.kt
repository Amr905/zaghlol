package app.zaghlol.spike.sms

import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Spike-only latency recorder (design note section 7). One clock: every
 * stamp is `elapsedRealtimeNanos` taken natively, Dart marks included (they
 * are stamped when they reach this class). One CSV row per message, written
 * when the message is acked (t9), to `noBackupFilesDir/spike/metrics.csv`.
 *
 * A row holds a ULID, the path, device conditions, the receive wall clock
 * (`rx_wall_ms`, to match the system's broadcast history; review F2) and
 * stage deltas in ms from t0 (receive), including `t_proc`, the start of the
 * process that received the message (negative: before t0). Never a sender,
 * body, amount or anything derived from them. Rows whose boot count changed
 * between receive and ack are discarded.
 */
class SpikeMetrics(
    private val file: File,
    private val bootCount: () -> Int,
    private val conditions: () -> Conditions,
    private val nanoClock: () -> Long = System::nanoTime,
    /** `Process.getStartElapsedRealtime()` in ns (same clock as the stamps); -1 unknown. */
    private val processStartNs: () -> Long = { -1L },
) {
    enum class Path(val label: String) {
        COLD_PROCESS("cold_process"),
        WARM_PROCESS("warm_process"),
        WARM_ENGINE("warm_engine"),
        FOREGROUND("foreground"),
    }

    class Conditions(
        val sdk: Int,
        val batteryExempt: Boolean,
        val deviceIdle: Boolean,
        val standbyBucket: Int,
        val lingerMs: Long,
    )

    /** Engine-level stamps of the current cycle. */
    class Cycle(val path: Path) {
        @Volatile var workerNs = -1L
        @Volatile var dartReadyNs = -1L
        @Volatile var dbOpenNs = -1L
    }

    private class Row(val rxNs: Long, val bootCount: Int) {
        var rxWallMs = -1L
        var procStartNs = -1L
        var spooledNs = -1L
        var enqueuedNs = -1L
        var cycle: Cycle? = null
        val stage = LongArray(4) { -1L } // t6 drained, t7 parsed, t8 commit, t9 acked
    }

    private val rows = ConcurrentHashMap<String, Row>()
    private val writeLock = Any()

    fun spooled(id: String, rxNs: Long, nowNs: Long, rxWallMs: Long = -1L) {
        val row = rows.getOrPut(id) { Row(rxNs, bootCount()) }
        row.spooledNs = nowNs
        row.rxWallMs = rxWallMs
        row.procStartNs = try {
            processStartNs()
        } catch (_: Exception) {
            -1L
        }
    }

    fun enqueued(id: String, nowNs: Long) {
        rows[id]?.enqueuedNs = nowNs
    }

    /** Called by the spool host when [id] is handed to an engine running [cycle]. */
    fun drained(id: String, rxNs: Long, recordBootCount: Int, cycle: Cycle?) {
        val row = rows.getOrPut(id) { Row(rxNs, recordBootCount) }
        row.cycle = cycle
        row.stage[0] = nanoClock()
    }

    /** A Dart mark: `parsed`, `commit` or `acked` for [ids]. */
    fun mark(stage: String, ids: List<String>) {
        val now = nanoClock()
        val index = when (stage) {
            "parsed" -> 1
            "commit" -> 2
            "acked" -> 3
            else -> return
        }
        for (id in ids) {
            val row = rows[id] ?: continue
            row.stage[index] = now
            if (index == 3) {
                rows.remove(id)
                write(id, row)
            }
        }
    }

    private fun write(id: String, row: Row) {
        if (row.bootCount != bootCount()) return // different boot: monotonic clock not comparable
        try {
            val c = conditions()
            val cycle = row.cycle
            val cols = listOf(
                id,
                cycle?.path?.label ?: "unknown",
                c.sdk.toString(),
                if (c.batteryExempt) "1" else "0",
                if (c.deviceIdle) "1" else "0",
                c.standbyBucket.toString(),
                c.lingerMs.toString(),
                if (row.rxWallMs < 0) "" else row.rxWallMs.toString(),
                delta(row, row.procStartNs),
                delta(row, row.spooledNs),
                delta(row, row.enqueuedNs),
                delta(row, cycle?.workerNs ?: -1),
                delta(row, cycle?.dartReadyNs ?: -1),
                delta(row, cycle?.dbOpenNs ?: -1),
                delta(row, row.stage[0]),
                delta(row, row.stage[1]),
                delta(row, row.stage[2]),
                delta(row, row.stage[3]),
            )
            synchronized(writeLock) {
                file.parentFile?.mkdirs()
                val fresh = !file.exists()
                if (!fresh && file.length() > MAX_FILE_BYTES) return
                FileOutputStream(file, true).use { out ->
                    if (fresh) out.write((HEADER + "\n").toByteArray())
                    out.write((cols.joinToString(",") + "\n").toByteArray())
                }
            }
        } catch (_: Exception) {
            SpikeLog.e(SpikeLog.Code.METRICS_FAILED)
        }
    }

    private fun delta(row: Row, ns: Long): String = if (ns < 0) "" else ((ns - row.rxNs) / 1_000_000).toString()

    companion object {
        const val HEADER = "ulid,path,sdk,batt_exempt,doze,bucket,linger_ms,rx_wall_ms,t_proc," +
            "t1_spooled,t2_enqueued,t3_worker,t4_dart,t5_db_open,t6_drained,t7_parsed,t8_commit,t9_acked"
        const val MAX_FILE_BYTES = 1L * 1024 * 1024
    }
}
