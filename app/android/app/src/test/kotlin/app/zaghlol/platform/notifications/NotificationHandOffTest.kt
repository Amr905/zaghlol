package app.zaghlol.platform.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** L-1: route and cancel extras count only when they carry the hand-off token. */
class NotificationHandOffTest {
  private val route = "/recurring/abc123/paid/2026-12-01"
  private val action = NotificationHandOff.ACTION_TAP
  private val token = NotificationHandOff.token.value

  @Test
  fun `a forged intent without the token is ignored`() {
    assertNull(NotificationRoutes.accept(null, null, route, 42))
    assertNull(NotificationRoutes.accept("android.intent.action.MAIN", null, route, 42))
    assertNull(NotificationRoutes.accept(action, null, route, 42))
  }

  @Test
  fun `a forged intent with a guessed or wrong token is ignored`() {
    assertNull(NotificationRoutes.accept(action, "", route, 42))
    assertNull(NotificationRoutes.accept(action, "0".repeat(32), route, 42))
    assertNull(NotificationRoutes.accept(action, token.dropLast(1), route, 42))
  }

  @Test
  fun `the token alone does not work under another action`() {
    assertNull(NotificationRoutes.accept("android.intent.action.MAIN", token, route, 42))
    assertNull(NotificationRoutes.accept(null, token, route, 42))
  }

  @Test
  fun `the share token is not accepted as a notification token`() {
    assertNull(NotificationRoutes.accept(action, app.zaghlol.platform.share.ShareHandOff.token.value, route, 42))
  }

  @Test
  fun `the real trampoline path is accepted`() {
    val a = NotificationRoutes.accept(action, token, route, 42)
    assertEquals(NotificationRoutes.Accepted(route, 42), a)
  }

  @Test
  fun `an accepted intent still has its route shape-checked`() {
    assertNull(NotificationRoutes.accept(action, token, "no-leading-slash", null)!!.route)
    assertNull(NotificationRoutes.accept(action, token, null, null)!!.route)
    assertNull(NotificationRoutes.accept(action, token, route, null)!!.cancelId)
  }

  @Test
  fun `each process gets its own token`() {
    val other = NotificationHandOffToken()
    assertNotEquals(token, other.value)
    assertTrue(token.matches(action, token))
    assertFalse(other.matches(action, token))
    assertTrue(other.value.matches(Regex("[0-9a-f]{32}")))
  }
}
