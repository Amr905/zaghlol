package app.zaghlol.platform.keys

import java.io.File
import java.io.IOException
import javax.crypto.AEADBadTagException
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** T-015: the K_db blob store (design note §2), on the JVM with a software KEK. */
class DbKeyStoreTest {
  @get:Rule val tmp = TemporaryFolder()

  private lateinit var dir: File
  private lateinit var kek: SoftwareKek
  private val sleeps = mutableListOf<Long>()

  private fun store(classifier: KeyErrorClassifier = KeyErrorClassifier { null }) =
    DbKeyStore(dir, kek, classifier, sleeper = { sleeps.add(it) })

  @Before
  fun setUp() {
    dir = File(tmp.root, "keys")
    kek = SoftwareKek()
  }

  private fun indexOf(hay: ByteArray, needle: ByteArray): Int {
    outer@ for (i in 0..hay.size - needle.size) {
      for (j in needle.indices) if (hay[i + j] != needle[j]) continue@outer
      return i
    }
    return -1
  }

  @Test
  fun emptyStoreIsNotFoundAfterOneAttempt() {
    val r = store().read()
    assertEquals(SecretStatusMsg.NOT_FOUND, r.status)
    assertNull(r.value)
    assertEquals(1, r.attempts)
    assertTrue(sleeps.isEmpty())
  }

  @Test
  fun createThenReadReturnsTheSameKey() {
    val s = store()
    val stored = s.createIfAbsent(syntheticKey())
    assertArrayEquals(syntheticKey(), stored)
    val r = s.read()
    assertEquals(SecretStatusMsg.FOUND, r.status)
    assertArrayEquals(syntheticKey(), r.value)
    assertEquals(1, kek.creates)
  }

  @Test
  fun blobHasTheDocumentedLayoutAndHoldsNoPlaintext() {
    store().createIfAbsent(syntheticKey())
    val blob = s().blobFile.readBytes()
    assertEquals(61, blob.size)
    assertEquals(1.toByte(), blob[0])
    assertEquals(-1, indexOf(blob, syntheticKey()))
    assertFalse(File(dir, "db_key_v1.bin.tmp").exists())
  }

  private fun s() = store()

  @Test
  fun existingKeyWinsOverANewCandidate() {
    val s = store()
    s.createIfAbsent(syntheticKey(1))
    val before = s.blobFile.readBytes()
    val winner = s.createIfAbsent(syntheticKey(2))
    assertArrayEquals(syntheticKey(1), winner)
    assertArrayEquals(before, s.blobFile.readBytes())
    assertEquals(1, kek.creates)
  }

  @Test
  fun everyCreateMakesAFreshWrappingKey() {
    val s = store()
    s.createIfAbsent(syntheticKey(1))
    s.delete()
    s.createIfAbsent(syntheticKey(2))
    assertEquals(2, kek.creates)
    assertArrayEquals(syntheticKey(2), s.read().value)
  }

  @Test
  fun aliasMissingWithBlobPresentIsUnusable() {
    val s = store()
    s.createIfAbsent(syntheticKey())
    kek.key = null
    val r = s.read()
    assertEquals(SecretStatusMsg.UNUSABLE, r.status)
    assertEquals(1, r.attempts)
  }

  @Test
  fun flippedBlobByteIsUnusable() {
    val s = store(KeyErrorClassifier { null })
    s.createIfAbsent(syntheticKey())
    val blob = s.blobFile.readBytes()
    blob[20] = (blob[20].toInt() xor 0x01).toByte()
    s.blobFile.writeBytes(blob)
    assertEquals(SecretStatusMsg.UNUSABLE, s.read().status)
  }

  @Test
  fun aDifferentWrappingKeyIsUnusable() {
    val s = store()
    s.createIfAbsent(syntheticKey())
    kek.key = SoftwareKek.newKey()
    assertEquals(SecretStatusMsg.UNUSABLE, s.read().status)
  }

  @Test
  fun malformedBlobsAreUnusable() {
    val s = store()
    s.createIfAbsent(syntheticKey())
    val good = s.blobFile.readBytes()
    s.blobFile.writeBytes(good.copyOf(60))
    assertEquals(SecretStatusMsg.UNUSABLE, s.read().status)
    val badVersion = good.copyOf()
    badVersion[0] = 2
    s.blobFile.writeBytes(badVersion)
    assertEquals(SecretStatusMsg.UNUSABLE, s.read().status)
    s.blobFile.writeBytes(ByteArray(0))
    assertEquals(SecretStatusMsg.UNUSABLE, s.read().status)
  }

  @Test
  fun ioErrorsAreUnavailableAfterRetries() {
    val s = store()
    s.createIfAbsent(syntheticKey())
    kek.getError = IOException("synthetic")
    val r = s.read()
    assertEquals(SecretStatusMsg.UNAVAILABLE, r.status)
    assertNull(r.value)
    assertEquals(4, r.attempts)
    assertEquals(listOf(100L, 300L, 900L), sleeps)
  }

  @Test
  fun unknownErrorsAreUnavailableNeverUnusable() {
    val s = store()
    s.createIfAbsent(syntheticKey())
    kek.getError = IllegalStateException("synthetic")
    assertEquals(SecretStatusMsg.UNAVAILABLE, s.read().status)
    kek.getError = java.security.UnrecoverableKeyException("synthetic")
    assertEquals(SecretStatusMsg.UNAVAILABLE, s.read().status)
  }

  @Test
  fun aTransientErrorThatClearsIsFoundOnRetry() {
    val s = store()
    s.createIfAbsent(syntheticKey())
    var failures = 2
    val flaky =
      object : Kek by kek {
        override fun get() =
          if (failures-- > 0) throw IOException("synthetic") else kek.get()
      }
    val r = DbKeyStore(dir, flaky, KeyErrorClassifier { null }, sleeper = { sleeps.add(it) }).read()
    assertEquals(SecretStatusMsg.FOUND, r.status)
    assertEquals(3, r.attempts)
  }

  @Test
  fun createRefusesOverAnUnusableBlobAndLeavesItAlone() {
    val s = store()
    s.createIfAbsent(syntheticKey(1))
    kek.key = null
    val before = s.blobFile.readBytes()
    try {
      s.createIfAbsent(syntheticKey(2))
      fail("expected KeyStoreFailure")
    } catch (e: KeyStoreFailure) {
      // expected
    }
    assertArrayEquals(before, s.blobFile.readBytes())
  }

  @Test
  fun createRefusesWhileTheStateIsUnknown() {
    val s = store()
    s.createIfAbsent(syntheticKey(1))
    val before = s.blobFile.readBytes()
    kek.getError = IOException("synthetic")
    try {
      s.createIfAbsent(syntheticKey(2))
      fail("expected KeyStoreFailure")
    } catch (e: KeyStoreFailure) {
      // expected
    }
    assertArrayEquals(before, s.blobFile.readBytes())
  }

  @Test
  fun degenerateCandidatesAreRefused() {
    val s = store()
    for (bad in listOf(ByteArray(32) { 7 }, ByteArray(31) { it.toByte() }, ByteArray(0))) {
      try {
        s.createIfAbsent(bad)
        fail("expected KeyStoreFailure")
      } catch (e: KeyStoreFailure) {
        // expected
      }
    }
    assertFalse(s.blobFile.exists())
    assertEquals(0, kek.creates)
  }

  @Test
  fun aFailedReadBackDeletesTheNewBlob() {
    val s = store()
    kek.swapAfterCreate = true
    try {
      s.createIfAbsent(syntheticKey())
      fail("expected KeyStoreFailure")
    } catch (e: KeyStoreFailure) {
      // expected
    }
    assertFalse(s.blobFile.exists())
    assertNull(kek.key)
  }

  @Test
  fun deleteRemovesBlobAndAliasAndIsIdempotent() {
    val s = store()
    s.createIfAbsent(syntheticKey())
    s.delete()
    assertFalse(s.blobFile.exists())
    assertNull(kek.key)
    s.delete()
    assertEquals(SecretStatusMsg.NOT_FOUND, s.read().status)
  }

  @Test
  fun aeadTagFailureFromTheCipherIsClassifiedUnusable() {
    assertEquals(ReadFailure.UNUSABLE, KeyErrorClassifier { null }.classify(AEADBadTagException()))
  }
}
