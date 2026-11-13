package app.zaghlol.platform.capture

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecentNotificationsTest {
    private var now = 0L
    private val recent = RecentNotifications({ now })

    @Test
    fun sameBodyWithinTheTtlIsARepeatAndAfterItIsNot() {
        assertFalse(recent.isRepeat("p", "b"))
        recent.remember("p", "b")
        assertTrue(recent.isRepeat("p", "b"))
        now = RecentNotifications.TTL_MS - 1
        assertTrue(recent.isRepeat("p", "b"))
        now = RecentNotifications.TTL_MS
        assertFalse(recent.isRepeat("p", "b"))
    }

    @Test
    fun aNewBodyOrAnotherPackageIsNew() {
        recent.remember("p", "b")
        assertFalse(recent.isRepeat("p", "b2"))
        assertFalse(recent.isRepeat("q", "b"))
        // The 0x00 separator: ("ab","c") is not ("a","bc").
        recent.remember("ab", "c")
        assertFalse(recent.isRepeat("a", "bc"))
    }

    @Test
    fun lruEvictsTheOldestAt129() {
        for (i in 0 until RecentNotifications.CAPACITY) recent.remember("p", "b$i")
        assertTrue(recent.isRepeat("p", "b0")) // also refreshes b0's recency
        recent.remember("p", "b128") // 129th distinct entry
        assertFalse("b1 is now the eldest and is evicted", recent.isRepeat("p", "b1"))
        assertTrue(recent.isRepeat("p", "b0"))
        assertTrue(recent.isRepeat("p", "b128"))
    }

    @Test
    fun printsNothing() {
        recent.remember("pkg-secret", "body-secret")
        assertFalse(recent.toString().contains("secret"))
    }
}
