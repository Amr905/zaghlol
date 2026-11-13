package app.zaghlol.platform.clock

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-180. Synthetic readings only. */
class TrustedClockHostTest {
  private class Fake(
    var wall: Long,
    var mono: Long,
    var boot: Long?,
  ) : ClockReadings {
    override fun wallMs() = wall

    override fun monotonicMs() = mono

    override fun bootCount() = boot
  }

  @Test
  fun sampleCarriesAllThreeReadings() {
    val s = TrustedClockHost(Fake(1_700_000_000_000L, 5_000L, 7L)).sample()
    assertEquals(1_700_000_000_000L, s.wallMs)
    assertEquals(5_000L, s.monotonicMs)
    assertEquals(7L, s.bootCount)
  }

  @Test
  fun missingBootCountIsNull() {
    assertNull(TrustedClockHost(Fake(1L, 2L, null)).sample().bootCount)
  }

  /** Negative-proof target: a wall-clock change must not move the monotonic value. */
  @Test
  fun wallClockChangeDoesNotMoveMonotonic() {
    val f = Fake(1_000L, 500L, 3L)
    val host = TrustedClockHost(f)
    val before = host.sample()
    f.wall += 86_400_000L // user sets the date a day ahead
    val after = host.sample()
    assertEquals(before.monotonicMs, after.monotonicMs)
    assertEquals(before.bootCount, after.bootCount)
  }

  /** The Android source reads elapsedRealtime (counts sleep), not uptimeMillis. */
  @Test
  fun sourceUsesElapsedRealtimeAndBootCount() {
    val src =
      File("src/main/kotlin/app/zaghlol/platform/clock/TrustedClockHost.kt").readText()
    assertTrue(src.contains("SystemClock.elapsedRealtime()"))
    assertTrue(src.contains("Settings.Global.BOOT_COUNT"))
    assertTrue(src.contains("System.currentTimeMillis()"))
    assertTrue(!src.contains("uptimeMillis"))
  }
}
