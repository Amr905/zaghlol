package app.zaghlol.platform.device

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-103: the root heuristic, the secure-window switch and the passcode check. */
class DeviceSecurityHostTest {
  private class FakeEnv(
    var files: Set<String> = emptySet(),
    var tags: String? = "release-keys",
    var secure: Boolean = true,
    var throwOnSecure: Boolean = false,
    var throwOnFile: Boolean = false,
  ) : DeviceEnv {
    val applied = mutableListOf<Boolean>()

    override fun fileExists(path: String): Boolean {
      if (throwOnFile) throw SecurityException()
      return path in files
    }

    override fun buildTags(): String? = tags

    override fun isDeviceSecure(): Boolean {
      if (throwOnSecure) throw IllegalStateException()
      return secure
    }

    override fun applySecureWindow(secure: Boolean) {
      applied += secure
    }
  }

  @After
  fun reset() {
    SecureWindowState.requested = false
  }

  @Test
  fun cleanDeviceIsNotRooted() {
    assertFalse(DeviceSecurityHost(FakeEnv()).isDeviceRooted())
  }

  @Test
  fun suBinaryMeansRooted() {
    assertTrue(DeviceSecurityHost(FakeEnv(files = setOf("/system/xbin/su"))).isDeviceRooted())
  }

  @Test
  fun testKeysMeansRooted() {
    assertTrue(DeviceSecurityHost(FakeEnv(tags = "dev-keys,test-keys")).isDeviceRooted())
  }

  @Test
  fun unreadablePathIsNotAGuess() {
    assertFalse(DeviceSecurityHost(FakeEnv(throwOnFile = true)).isDeviceRooted())
  }

  @Test
  fun secureWindowIsAppliedAndRemembered() {
    val env = FakeEnv()
    val host = DeviceSecurityHost(env)
    host.setSecureWindow(true)
    assertTrue(SecureWindowState.requested)
    host.setSecureWindow(false)
    assertFalse(SecureWindowState.requested)
    assertEquals(listOf(true, false), env.applied)
  }

  @Test
  fun deviceSecureFollowsKeyguardAndFailsToFalse() {
    assertTrue(DeviceSecurityHost(FakeEnv(secure = true)).isDeviceSecure())
    assertFalse(DeviceSecurityHost(FakeEnv(secure = false)).isDeviceSecure())
    assertFalse(DeviceSecurityHost(FakeEnv(throwOnSecure = true)).isDeviceSecure())
  }
}
