package app.zaghlol.platform.keys

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-015: the process-wide bootstrap lease (design note §3). */
class BootstrapLeaseManagerTest {
  @Test
  fun aSecondAcquireTimesOutWhileTheLeaseIsHeld() {
    val m = BootstrapLeaseManager()
    val first = m.acquire(10)
    assertNotNull(first)
    assertNull(m.acquire(50))
    assertTrue(m.isValid(first!!))
  }

  @Test
  fun releaseLetsTheNextAcquireIn() {
    val m = BootstrapLeaseManager()
    val first = m.acquire(10)!!
    m.release(first)
    assertFalse(m.isValid(first))
    val second = m.acquire(10)
    assertNotNull(second)
    assertTrue(second != first)
  }

  @Test
  fun aWaiterGetsTheLeaseWhenItIsReleased() {
    val m = BootstrapLeaseManager()
    val first = m.acquire(10)!!
    val got = AtomicLong(-1)
    val started = CountDownLatch(1)
    val t = Thread {
      started.countDown()
      got.set(m.acquire(5_000) ?: 0L)
    }
    t.start()
    started.await()
    Thread.sleep(50)
    m.release(first)
    t.join(5_000)
    assertTrue(got.get() > 0)
  }

  @Test
  fun aLeaseExpiresAfterItsTtl() {
    val now = AtomicLong(0)
    val m = BootstrapLeaseManager(ttlNanos = TimeUnit.SECONDS.toNanos(30), nanoClock = { now.get() })
    val first = m.acquire(10)!!
    now.addAndGet(TimeUnit.SECONDS.toNanos(30))
    assertFalse(m.isValid(first))
    val second = m.acquire(10)
    assertNotNull(second)
    assertTrue(m.isValid(second!!))
  }

  @Test
  fun aStaleReleaseIsIgnored() {
    val now = AtomicLong(0)
    val m = BootstrapLeaseManager(nanoClock = { now.get() })
    val first = m.acquire(10)!!
    now.addAndGet(TimeUnit.SECONDS.toNanos(31))
    val second = m.acquire(10)!!
    m.release(first)
    assertTrue(m.isValid(second))
    m.release(0)
    m.release(12345)
    assertTrue(m.isValid(second))
  }

  @Test
  fun leaseIdsAreNeverZero() {
    val m = BootstrapLeaseManager()
    repeat(5) {
      val id = m.acquire(10)!!
      assertTrue(id != 0L)
      m.release(id)
    }
    assertFalse(m.isValid(0))
    assertEquals(false, m.isValid(-1))
  }

  // T-016 (S-2, FU-065): renew extends a current lease and never takes one.

  @Test
  fun renewExtendsAValidLease() {
    val now = AtomicLong(0)
    val m = BootstrapLeaseManager(ttlNanos = TimeUnit.SECONDS.toNanos(30), nanoClock = { now.get() })
    val lease = m.acquire(10)!!
    now.addAndGet(TimeUnit.SECONDS.toNanos(29))
    assertTrue(m.renew(lease))
    // Without the renewal the lease would have expired at 30 s.
    now.addAndGet(TimeUnit.SECONDS.toNanos(29))
    assertTrue(m.isValid(lease))
    now.addAndGet(TimeUnit.SECONDS.toNanos(1))
    assertFalse(m.isValid(lease))
  }

  @Test
  fun renewOfAnExpiredLeaseIsFalseAndDoesNotRevive() {
    val now = AtomicLong(0)
    val m = BootstrapLeaseManager(ttlNanos = TimeUnit.SECONDS.toNanos(30), nanoClock = { now.get() })
    val lease = m.acquire(10)!!
    now.addAndGet(TimeUnit.SECONDS.toNanos(30))
    assertFalse(m.renew(lease))
    assertFalse(m.isValid(lease))
    val next = m.acquire(10)
    assertNotNull(next)
    assertTrue(next != lease)
  }

  @Test
  fun renewOfAStaleIdIsFalseAndLeavesTheCurrentLeaseAlone() {
    val now = AtomicLong(0)
    val m = BootstrapLeaseManager(ttlNanos = TimeUnit.SECONDS.toNanos(30), nanoClock = { now.get() })
    val first = m.acquire(10)!!
    now.addAndGet(TimeUnit.SECONDS.toNanos(31))
    val second = m.acquire(10)!!
    now.addAndGet(TimeUnit.SECONDS.toNanos(20))
    assertFalse(m.renew(first))
    assertFalse(m.renew(0))
    assertFalse(m.renew(-1))
    // The stale renewal did not extend the current lease.
    now.addAndGet(TimeUnit.SECONDS.toNanos(10))
    assertFalse(m.isValid(second))
  }

  @Test
  fun renewAfterReleaseIsFalseAndNeverTakesTheLease() {
    val m = BootstrapLeaseManager()
    val lease = m.acquire(10)!!
    m.release(lease)
    assertFalse(m.renew(lease))
    assertFalse(m.isValid(lease))
    // Nothing was taken: a new acquire succeeds at once.
    assertNotNull(m.acquire(0))
  }
}
