package app.zaghlol.platform.diag

import app.zaghlol.BuildConfig
import java.io.File

/**
 * SMS-device: per-sender stage counters for the debug-only "SMS diagnostics"
 * screen (Settings, About; dev flavours only: `BuildConfig.SMS_DIAG`).
 *
 * Counts and sender names only. **Never a body**, never a timestamp, never an
 * amount. A sender that looks like a phone number is recorded as `(number)`
 * (a contact's number is not a bank id). In every non-dev build [forDir]
 * returns [NONE] and nothing is counted or written.
 */
interface SmsDiagSink {
    /** Counts one [stage] (`received`, `kept:registry`, `drop:no_digit`, `spooled`...) for [sender]. Never throws. */
    fun record(sender: String, stage: String)

    object NONE : SmsDiagSink {
        override fun record(sender: String, stage: String) = Unit
    }
}

/**
 * The counters, kept in memory and in one plain file
 * (`sender TAB stage TAB count` lines) so a count made by the receiver while
 * the UI was closed is still there when the screen opens.
 */
class SmsDiagStore(private val file: File) : SmsDiagSink {
    private val lock = Any()
    private var counts: MutableMap<Pair<String, String>, Int>? = null

    override fun record(sender: String, stage: String) {
        try {
            synchronized(lock) {
                val m = loaded()
                val key = labelOf(sender) to clean(stage)
                m[key] = (m[key] ?: 0) + 1
                persist(m)
            }
        } catch (_: Exception) {
            // A diagnostic must never break capture.
        }
    }

    /** sender -> stage -> count. */
    fun snapshot(): Map<String, Map<String, Int>> = synchronized(lock) {
        val out = LinkedHashMap<String, MutableMap<String, Int>>()
        for ((k, n) in loaded().toSortedMap(compareBy<Pair<String, String>>({ it.first }, { it.second }))) {
            out.getOrPut(k.first) { LinkedHashMap() }[k.second] = n
        }
        out
    }

    fun reset() {
        synchronized(lock) {
            counts = HashMap()
            file.delete()
        }
    }

    private fun loaded(): MutableMap<Pair<String, String>, Int> {
        counts?.let { return it }
        val m = HashMap<Pair<String, String>, Int>()
        try {
            if (file.isFile) {
                file.forEachLine { line ->
                    val p = line.split('\t')
                    val n = p.getOrNull(2)?.toIntOrNull()
                    if (p.size == 3 && n != null) m[p[0] to p[1]] = n
                }
            }
        } catch (_: Exception) {
            // Unreadable: start again.
        }
        counts = m
        return m
    }

    private fun persist(m: Map<Pair<String, String>, Int>) {
        file.parentFile?.mkdirs()
        val tmp = File(file.path + ".tmp")
        tmp.writeText(m.entries.joinToString("\n") { "${it.key.first}\t${it.key.second}\t${it.value}" })
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
    }

    companion object {
        private val PHONE_SHAPE = Regex("^\\+?[0-9][0-9 ()-]{5,}$")

        /** What the screen shows for [sender]: the id, `(number)` for a phone number, `(none)` when empty. */
        fun labelOf(sender: String): String {
            val s = clean(sender.trim())
            return when {
                s.isEmpty() -> "(none)"
                PHONE_SHAPE.matches(s) -> "(number)"
                else -> s.take(40)
            }
        }

        private fun clean(s: String): String = s.map { if (it.isISOControl() || it == '\t') ' ' else it }.joinToString("")
    }
}

object SmsDiag {
    @Volatile
    private var store: SmsDiagStore? = null

    /** The process-wide store under [noBackupDir], or [SmsDiagSink.NONE] outside dev builds. */
    fun forDir(noBackupDir: File): SmsDiagSink = storeFor(noBackupDir) ?: SmsDiagSink.NONE

    fun storeFor(noBackupDir: File): SmsDiagStore? {
        if (!BuildConfig.SMS_DIAG) return null
        store?.let { return it }
        return synchronized(this) { store ?: SmsDiagStore(File(noBackupDir, "diag/sms_counts.tsv")).also { store = it } }
    }
}
