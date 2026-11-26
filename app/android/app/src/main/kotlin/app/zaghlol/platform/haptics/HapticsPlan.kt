package app.zaghlol.platform.haptics

/**
 * T-293: pure translation of the Dart beat table into Android vibration
 * parameters. No Android classes, so it is unit-tested on the JVM.
 * Beats only (offset, strength, intensity): nothing financial crosses here.
 */
object HapticsPlan {
    const val TICK = 0
    const val CLICK = 1
    const val THUD = 2

    // VibrationEffect.Composition.PRIMITIVE_* (API 30), inlined so this stays pure.
    const val PRIMITIVE_CLICK = 1
    const val PRIMITIVE_THUD = 2
    const val PRIMITIVE_TICK = 7

    private const val MAX_HITS = 32
    private const val MAX_OFFSET_MS = 5000

    data class Hit(val atMs: Int, val strength: Int, val pct: Int)
    data class Primitive(val id: Int, val scale: Float, val delayMs: Int)
    class Waveform(val timings: LongArray, val amplitudes: IntArray)

    /** Strict decode of the channel arguments; null when malformed. */
    fun parse(args: Any?): List<Hit>? {
        val raw = (args as? Map<*, *>)?.get("hits") as? List<*> ?: return null
        if (raw.isEmpty() || raw.size > MAX_HITS) return null
        val out = ArrayList<Hit>(raw.size)
        var last = 0
        for (item in raw) {
            val row = item as? List<*> ?: return null
            if (row.size != 3) return null
            val at = (row[0] as? Number)?.toInt() ?: return null
            val strength = (row[1] as? Number)?.toInt() ?: return null
            val pct = (row[2] as? Number)?.toInt() ?: return null
            if (at < last || at > MAX_OFFSET_MS) return null
            if (strength !in TICK..THUD || pct !in 1..100) return null
            out.add(Hit(at, strength, pct))
            last = at
        }
        return out
    }

    /** API 30+ composition: delay is the gap since the previous beat's start. */
    fun primitives(hits: List<Hit>): List<Primitive> {
        var prev = 0
        return hits.map { h ->
            val id = when (h.strength) {
                TICK -> PRIMITIVE_TICK
                CLICK -> PRIMITIVE_CLICK
                else -> PRIMITIVE_THUD
            }
            val p = Primitive(id, h.pct / 100f, h.atMs - prev)
            prev = h.atMs
            p
        }
    }

    private fun pulseMs(strength: Int): Long = when (strength) {
        TICK -> 15L
        CLICK -> 25L
        else -> 45L
    }

    /** Fallback waveform: alternating off / on timings with amplitudes 0..255. */
    fun waveform(hits: List<Hit>): Waveform {
        val timings = ArrayList<Long>()
        val amps = ArrayList<Int>()
        var cursor = 0L
        for (h in hits) {
            val off = maxOf(0L, h.atMs - cursor)
            val on = pulseMs(h.strength)
            timings.add(off)
            amps.add(0)
            timings.add(on)
            amps.add(maxOf(1, minOf(255, h.pct * 255 / 100)))
            cursor = maxOf(cursor + off, h.atMs.toLong()) + on
        }
        return Waveform(timings.toLongArray(), amps.toIntArray())
    }
}
