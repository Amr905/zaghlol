package app.zaghlol.platform.haptics

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        assertEquals(0.7f, p[0].scale, 0.0001f) // 40 % is lifted to the 0.7 floor
        assertEquals(0.7f, p[1].scale, 0.0001f)
    }

    @Test
    fun waveformAlternatesOffAndOn() {
        val w = HapticsPlan.waveform(
            listOf(
                HapticsPlan.Hit(0, HapticsPlan.CLICK, 80),
                HapticsPlan.Hit(90, HapticsPlan.CLICK, 100),
            ),
        )
        // off 0, on 45 (ends 45), off 45 (to 90), on 45.
        assertArrayEquals(longArrayOf(0, 45, 45, 45), w.timings)
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
        assertArrayEquals(longArrayOf(0, 80, 0, 30), w.timings)
    }

    @Test
    fun pulsesAre30_45_80msAndAmplitudeNeverBelow180() {
        val w = HapticsPlan.waveform(
            listOf(
                HapticsPlan.Hit(0, HapticsPlan.TICK, 70),
                HapticsPlan.Hit(200, HapticsPlan.CLICK, 80),
                HapticsPlan.Hit(400, HapticsPlan.THUD, 100),
                HapticsPlan.Hit(600, HapticsPlan.TICK, 1),
            ),
        )
        assertEquals(listOf(30L, 45L, 80L, 30L), listOf(w.timings[1], w.timings[3], w.timings[5], w.timings[7]))
        assertTrue(listOf(1, 3, 5, 7).all { w.amplitudes[it] >= 180 })
    }

    @Test
    fun noAmplitudePhonesUsePredefinedEffectsForOneBeat() {
        val one = { s: Int -> listOf(HapticsPlan.Hit(0, s, 80)) }
        assertEquals(HapticsPlan.EFFECT_CLICK, HapticsPlan.predefinedEffect(one(HapticsPlan.TICK)))
        assertEquals(HapticsPlan.EFFECT_HEAVY_CLICK, HapticsPlan.predefinedEffect(one(HapticsPlan.CLICK)))
        assertEquals(HapticsPlan.EFFECT_HEAVY_CLICK, HapticsPlan.predefinedEffect(one(HapticsPlan.THUD)))
        assertNull(HapticsPlan.predefinedEffect(one(HapticsPlan.CLICK) + one(HapticsPlan.CLICK)))
    }

    @Test
    fun noAmplitudeMultiBeatPatternsStillGetOnOffTimings() {
        val t = HapticsPlan.onOffTimings(
            listOf(HapticsPlan.Hit(0, HapticsPlan.CLICK, 90), HapticsPlan.Hit(90, HapticsPlan.CLICK, 100)),
        )
        assertArrayEquals(longArrayOf(0, 45, 45, 45), t)
    }
}
