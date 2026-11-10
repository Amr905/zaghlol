package app.zaghlol.platform.keys

import java.util.concurrent.TimeUnit

/**
 * T-015: the process-wide bootstrap lease (design note §3). Serialises the key
 * bootstrap and database creation/wipe between every Flutter engine in the
 * process (the UI engine and the T-008 headless engine). A lease expires
 * [ttlNanos] after it was taken, so a dead engine can't block the others.
 *
 * No logging in this package (FU-050).
 */
class BootstrapLeaseManager(
  private val ttlNanos: Long = TimeUnit.SECONDS.toNanos(30),
  private val nanoClock: () -> Long = System::nanoTime,
) {
  private val lock = Object()
  private var current = 0L
  private var expiresAt = 0L
  private var nextId = 1L

  /** Takes the lease, waiting at most [timeoutMs]. Returns null on timeout. */
  fun acquire(timeoutMs: Long): Long? {
    val deadline = nanoClock() + TimeUnit.MILLISECONDS.toNanos(timeoutMs.coerceAtLeast(0))
    synchronized(lock) {
      while (true) {
        val now = nanoClock()
        if (current == 0L || now - expiresAt >= 0) {
          current = nextId++
          expiresAt = now + ttlNanos
          return current
        }
        val remaining = deadline - now
        if (remaining <= 0) return null
        val waitNanos = minOf(remaining, expiresAt - now)
        val waitMs = TimeUnit.NANOSECONDS.toMillis(waitNanos).coerceAtLeast(1)
        lock.wait(waitMs)
      }
    }
  }

  /** Releases [lease]; a stale or unknown lease is ignored. */
  fun release(lease: Long) {
    synchronized(lock) {
      if (lease != 0L && lease == current) {
        current = 0L
        lock.notifyAll()
      }
    }
  }

  /**
   * T-016 (S-2, FU-065): if [lease] is the current, unexpired lease, sets its
   * expiry to now + [ttlNanos] and returns true; otherwise false. Never takes
   * a lease. Same-lease renewals are unbounded, but an engine that stops
   * renewing (or dies) still loses the lease [ttlNanos] after its last renewal.
   */
  fun renew(lease: Long): Boolean =
    synchronized(lock) {
      val now = nanoClock()
      if (lease != 0L && lease == current && now - expiresAt < 0) {
        expiresAt = now + ttlNanos
        true
      } else {
        false
      }
    }

  /** True while [lease] is the current, unexpired lease. */
  fun isValid(lease: Long): Boolean =
    synchronized(lock) { lease != 0L && lease == current && nanoClock() - expiresAt < 0 }

  companion object {
    /** The one lease of this process, shared by every engine. */
    val process = BootstrapLeaseManager()
  }
}
