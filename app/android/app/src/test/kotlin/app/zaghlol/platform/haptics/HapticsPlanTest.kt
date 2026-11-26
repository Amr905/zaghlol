package app.zaghlol.platform.haptics

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class HapticsPlanTest {
    private fun args(vararg rows: List<Int>) = mapOf("hits" to rows.toList())

    @Test
    fun parsesAValidTable() {
        val hits = HapticsPlan.parse(args(listOf(0, 0, 40), listOf(700, 2, 100)))
        assertNotNull(hits)
        assertEquals(HapticsPlan.Hit(700, 2, 100), hits!![1])
    }

    @Test
    fun rejectsMalformedInput() {
        assertNull(HapticsPlan.parse(null))
        assertNull(HapticsPlan.parse(mapOf("hits" to emptyList<Any>())))
        assertNull(HapticsPlan.parse(args(listOf(10, 0, 40), listOf(5, 0, 40)))) // goes back in time
        assertNull(HapticsPlan.parse(args(listOf(0, 3, 40)))) // unknown strength
        assertNull(HapticsPlan.parse(args(listOf(0, 0, 0)))) // no intensity
        assertNull(HapticsPlan.parse(args(listOf(9999, 0, 50)))) // too late
        assertNull(HapticsPlan.parse(mapOf("hits" to List(40) { listOf(0, 0, 50) }))) // too many
    }

    @Test
    fun primitivesUseGapsAndScales() {
        val hits = listOf(
            HapticsPlan.Hit(0, HapticsPlan.TICK, 40),
            HapticsPlan.Hit(140, HapticsPlan.CLICK, 50),
            HapticsPlan.Hit(700, HapticsPlan.THUD, 100),
        )
        val p = HapticsPlan.primitives(hits)
        assertEquals(listOf(7, 1, 2), p.map { it.id })
        assertEquals(listOf(0, 140, 560), p.map { it.delayMs })
        assertEquals(1.0f, p[2].scale, 0.0001f)
        assertEquals(0.4f, p[0].scale, 0.0001f)
    }

    @Test
    fun waveformAlternatesOffAndOn() {
        val w = HapticsPlan.waveform(
            listOf(
                HapticsPlan.Hit(0, HapticsPlan.CLICK, 80),
                HapticsPlan.Hit(90, HapticsPlan.CLICK, 100),
            ),
        )
        // off 0, on 25 (ends 25), off 65 (to 90), on 25.
        assertArrayEquals(longArrayOf(0, 25, 65, 25), w.timings)
        assertArrayEquals(intArrayOf(0, 204, 0, 255), w.amplitudes)
    }

    @Test
    fun waveformNeverOverlapsWhenBeatsAreCloserThanAPulse() {
        val w = HapticsPlan.waveform(
            listOf(
                HapticsPlan.Hit(0, HapticsPlan.THUD, 100),
                HapticsPlan.Hit(10, HapticsPlan.TICK, 100),
            ),
        )
        assertArrayEquals(longArrayOf(0, 45, 0, 15), w.timings)
    }
}
