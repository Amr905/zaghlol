package app.zaghlol.platform.notifications

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleBookTest {
  private fun alert(id: Int, at: Long, body: String = "b$id \t=&é") =
    ScheduledAlert(at, mapOf(NotificationPresenter.K_ID to id, NotificationPresenter.K_BODY to body))

  private fun book(): Pair<ScheduleBook, File> {
    val f = File.createTempFile("sched", ".txt")
    f.delete()
    return ScheduleBook(FileScheduleStore(f)) to f
  }

  @Test
  fun `reboot re-arms future alerts with same id time and text, drops past-due`() {
    val (b, _) = book()
    b.add(alert(1, 2_000))
    b.add(alert(2, 500))
    b.add(alert(3, 3_000))
    val armed = mutableListOf<Pair<Map<String, Any?>, Long>>()
    assertEquals(2, b.rearm(1_000) { m, at -> armed.add(m to at) })
    assertEquals(listOf(1 to 2_000L, 3 to 3_000L), armed.map { (it.first[NotificationPresenter.K_ID] as Int) to it.second })
    assertEquals("b1 \t=&é", armed[0].first[NotificationPresenter.K_BODY])
    // The dropped one is gone; nothing fires in a burst on a second boot either.
    val again = mutableListOf<Long>()
    b.rearm(1_000) { _, at -> again.add(at) }
    assertEquals(listOf(2_000L, 3_000L), again)
  }

  @Test
  fun `rescheduling an id replaces it, cancel and fire remove it`() {
    val (b, _) = book()
    b.add(alert(1, 2_000, "old"))
    b.add(alert(1, 4_000, "redacted"))
    b.add(alert(2, 2_000))
    b.remove(2)
    val got = mutableListOf<Map<String, Any?>>()
    b.rearm(0) { m, _ -> got.add(m) }
    assertEquals(1, got.size)
    assertEquals("redacted", got[0][NotificationPresenter.K_BODY])
  }

  @Test
  fun `clear (delete-all and the hide-amounts cancelScheduled) leaves nothing to re-arm`() {
    val (b, f) = book()
    b.add(alert(1, 2_000))
    b.clear()
    assertEquals(0, b.rearm(0) { _, _ -> })
    assertFalse(f.exists())
    assertTrue(true)
  }

  @Test
  fun `writes leave no temp file and two books over one file share the lock`() {
    val (a, f) = book()
    val b = ScheduleBook(FileScheduleStore(f))
    val threads =
      (1..8).map { n ->
        Thread {
          repeat(25) { i -> (if (n % 2 == 0) a else b).add(alert(n * 100 + i, 10_000L + i)) }
        }
      }
    threads.forEach { it.start() }
    threads.forEach { it.join() }
    assertFalse(File(f.parentFile, f.name + ".tmp").exists())
    var count = 0
    a.rearm(0) { _, _ -> count++ }
    assertEquals(200, count)
  }
}
