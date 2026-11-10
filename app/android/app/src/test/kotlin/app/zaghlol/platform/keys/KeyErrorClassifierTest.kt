package app.zaghlol.platform.keys

import java.io.IOException
import java.security.InvalidKeyException
import java.security.ProviderException
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * T-015: exception → status mapping (design note §2). Only positive evidence
 * is UNUSABLE; everything unknown is UNAVAILABLE. The API 33 KeyStoreException
 * branch is covered through the injected extractor (the Android class can't
 * be built on the JVM).
 */
class KeyErrorClassifierTest {
  private class FakeKeystoreError(val info: KeystoreErrorInfo) : RuntimeException()

  private val classifier = KeyErrorClassifier { (it as? FakeKeystoreError)?.info }

  @Test
  fun aeadTagFailureIsUnusable() {
    assertEquals(ReadFailure.UNUSABLE, classifier.classify(AEADBadTagException()))
  }

  @Test
  fun aeadTagFailureInTheCauseChainIsUnusable() {
    val wrapped = ProviderException(InvalidKeyException(AEADBadTagException()))
    assertEquals(ReadFailure.UNUSABLE, classifier.classify(wrapped))
  }

  @Test
  fun keystoreKeyMissingOrCorruptedIsUnusable() {
    val e = FakeKeystoreError(KeystoreErrorInfo(keyMissingOrCorrupted = true, transient = false))
    assertEquals(ReadFailure.UNUSABLE, classifier.classify(e))
    assertEquals(ReadFailure.UNUSABLE, classifier.classify(ProviderException(e)))
  }

  @Test
  fun transientKeystoreErrorIsUnavailableEvenWhenItNamesTheKey() {
    val e = FakeKeystoreError(KeystoreErrorInfo(keyMissingOrCorrupted = true, transient = true))
    assertEquals(ReadFailure.UNAVAILABLE, classifier.classify(e))
  }

  @Test
  fun otherKeystoreErrorsAreUnavailable() {
    val e = FakeKeystoreError(KeystoreErrorInfo(keyMissingOrCorrupted = false, transient = false))
    assertEquals(ReadFailure.UNAVAILABLE, classifier.classify(e))
  }

  @Test
  fun ioErrorsAreUnavailable() {
    assertEquals(ReadFailure.UNAVAILABLE, classifier.classify(IOException()))
  }

  @Test
  fun unknownErrorsAreUnavailable() {
    for (e in
      listOf(
        RuntimeException(),
        IllegalStateException(),
        UnrecoverableKeyException(),
        InvalidKeyException(),
        ProviderException(),
        OutOfMemoryError(),
      )) {
      assertEquals(e.javaClass.simpleName, ReadFailure.UNAVAILABLE, classifier.classify(e))
    }
  }

  @Test
  fun aSelfReferencingCauseChainEnds() {
    val e = object : RuntimeException() {
      override val cause: Throwable
        get() = this
    }
    assertEquals(ReadFailure.UNAVAILABLE, classifier.classify(e))
  }

  @Test
  fun platformExtractorIsInertBelowApi33OnTheJvm() {
    // Build.VERSION.SDK_INT is 0 in JVM unit tests.
    assertEquals(null, platformKeystoreInfo(RuntimeException()))
  }
}
