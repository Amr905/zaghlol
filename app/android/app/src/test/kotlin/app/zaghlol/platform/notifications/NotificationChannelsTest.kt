package app.zaghlol.platform.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationChannelsTest {
  @Test
  fun `channel ids are stable and unique`() {
    // A renamed id would orphan the user's per-channel settings: this list is
    // the released contract.
    assertEquals(
      listOf(
        "zaghlol_alert_budget",
        "zaghlol_alert_spike",
        "zaghlol_alert_due",
        "zaghlol_alert_duplicate",
        "zaghlol_alert_renewal",
        "zaghlol_alert_backup_failure",
        "zaghlol_alert_weekly",
      ),
      NotificationChannels.IDS,
    )
    assertEquals(NotificationChannels.IDS.size, NotificationChannels.IDS.toSet().size)
  }

  @Test
  fun `an unknown channel falls back to the first one`() {
    assertEquals("zaghlol_alert_budget", NotificationChannels.resolve("nope"))
    assertEquals("zaghlol_alert_weekly", NotificationChannels.resolve("zaghlol_alert_weekly"))
  }

  @Test
  fun `routes are short in-app paths only`() {
    assertEquals("/budget", NotificationRoutes.clean("/budget"))
    assertEquals("/transactions/abc-123", NotificationRoutes.clean("/transactions/abc-123"))
    assertNull(NotificationRoutes.clean(null))
    assertNull(NotificationRoutes.clean(""))
    assertNull(NotificationRoutes.clean("https://evil"))
    assertNull(NotificationRoutes.clean("/with space"))
    assertNull(NotificationRoutes.clean("/" + "a".repeat(200)))
  }

  @Test
  fun `the launch route is taken once`() {
    NotificationRoutes.setLaunchRoute("/insights")
    assertEquals("/insights", NotificationRoutes.takeLaunchRoute())
    assertNull(NotificationRoutes.takeLaunchRoute())
    NotificationRoutes.setLaunchRoute("javascript:x")
    assertFalse(NotificationRoutes.takeLaunchRoute() != null)
  }
}
