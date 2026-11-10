package app.zaghlol.platform.keys

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T-015: the Pigeon host's error mapping (platform-channels §6). Errors carry a
 * code only (no message, no details), reads never fail, and writes need the
 * current lease.
 */
class SecretStoreHostTest {
  private class FakeSlot : SecretSlotStore {
    var value: ByteArray? = null
    var readError: Throwable? = null
    var writeError: Throwable? = null
    var writes = 0
    var lastCandidate: ByteArray? = null

    override fun read(): SlotRead {
      readError?.let { throw it }
      val v = value ?: return SlotRead(SecretStatusMsg.NOT_FOUND, null, 1)
      return SlotRead(SecretStatusMsg.FOUND, v.copyOf(), 1)
    }

    override fun createIfAbsent(candidate: ByteArray): ByteArray {
      writes++
      lastCandidate = candidate
      writeError?.let { throw it }
      value?.let { return it.copyOf() }
      value = candidate.copyOf()
      return candidate.copyOf()
    }

    override fun delete() {
      writes++
      writeError?.let { throw it }
      value = null
    }
  }

  private val slot = FakeSlot()
  private val leases = BootstrapLeaseManager()
  private val host =
    SecretStoreHost(slots = { slot }, leases = leases, worker = { it.run() }, main = { it.run() })

  private fun <T> call(block: ((Result<T>) -> Unit) -> Unit): Result<T> {
    var out: Result<T>? = null
    block { out = it }
    return out!!
  }

  private fun assertCodeOnly(result: Result<*>, code: String) {
    val e = result.exceptionOrNull()
    assertTrue(e is SecretStoreApiError)
    e as SecretStoreApiError
    assertEquals(code, e.code)
    assertNull(e.message)
    assertNull(e.details)
    assertNull(e.cause)
  }

  @Test
  fun leaseTimeoutIsACodeOnlyError() {
    val held = call<Long> { host.acquireBootstrapLease(10, it) }.getOrThrow()
    assertTrue(held > 0)
    assertCodeOnly(call<Long> { host.acquireBootstrapLease(20, it) }, "LEASE_TIMEOUT")
  }

  @Test
  fun writesWithoutTheCurrentLeaseFailWithLeaseTimeout() {
    assertCodeOnly(
      call<ByteArray> { host.createIfAbsent(99, SecretSlotMsg.DB_KEY, syntheticKey(), it) },
      "LEASE_TIMEOUT",
    )
    assertCodeOnly(call<Unit> { host.delete(99, SecretSlotMsg.DB_KEY, it) }, "LEASE_TIMEOUT")
    assertEquals(0, slot.writes)
  }

  @Test
  fun storeFailuresAreKeyStoreFailedWithoutMessage() {
    val lease = call<Long> { host.acquireBootstrapLease(10, it) }.getOrThrow()
    slot.writeError = IllegalStateException("synthetic detail that must not cross")
    assertCodeOnly(
      call<ByteArray> { host.createIfAbsent(lease, SecretSlotMsg.DB_KEY, syntheticKey(), it) },
      "KEY_STORE_FAILED",
    )
    assertCodeOnly(call<Unit> { host.delete(lease, SecretSlotMsg.DB_KEY, it) }, "KEY_STORE_FAILED")
    slot.writeError = KeyStoreFailure()
    assertCodeOnly(call<Unit> { host.delete(lease, SecretSlotMsg.DB_KEY, it) }, "KEY_STORE_FAILED")
  }

  @Test
  fun createReturnsTheWinnerAndZeroesTheCandidateBuffer() {
    val lease = call<Long> { host.acquireBootstrapLease(10, it) }.getOrThrow()
    slot.value = syntheticKey(5)
    val candidate = syntheticKey(6)
    val stored =
      call<ByteArray> { host.createIfAbsent(lease, SecretSlotMsg.DB_KEY, candidate, it) }
        .getOrThrow()
    assertArrayEquals(syntheticKey(5), stored)
    assertTrue(candidate.all { it == 0.toByte() })
  }

  @Test
  fun readNeverFailsAndMapsErrorsToUnavailable() {
    slot.readError = RuntimeException("synthetic")
    val r = call<SecretReadMsg> { host.read(SecretSlotMsg.DB_KEY, it) }.getOrThrow()
    assertEquals(SecretStatusMsg.UNAVAILABLE, r.status)
    assertNull(r.value)
  }

  @Test
  fun readReturnsTheValueOnlyWhenFound() {
    val notFound = call<SecretReadMsg> { host.read(SecretSlotMsg.DB_KEY, it) }.getOrThrow()
    assertEquals(SecretStatusMsg.NOT_FOUND, notFound.status)
    assertNull(notFound.value)
    slot.value = syntheticKey()
    val found = call<SecretReadMsg> { host.read(SecretSlotMsg.DB_KEY, it) }.getOrThrow()
    assertEquals(SecretStatusMsg.FOUND, found.status)
    assertArrayEquals(syntheticKey(), found.value)
    assertEquals(1L, found.attempts)
  }

  @Test
  fun releaseThenWriteFails() {
    val lease = call<Long> { host.acquireBootstrapLease(10, it) }.getOrThrow()
    call<Unit> { host.releaseBootstrapLease(lease, it) }.getOrThrow()
    assertCodeOnly(call<Unit> { host.delete(lease, SecretSlotMsg.DB_KEY, it) }, "LEASE_TIMEOUT")
  }
}
