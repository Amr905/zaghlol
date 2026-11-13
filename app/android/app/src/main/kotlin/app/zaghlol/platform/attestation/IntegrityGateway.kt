package app.zaghlol.platform.attestation

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest

/**
 * T-178: a failure from the Play Integrity SDK. [errorCode] is the
 * `StandardIntegrityErrorCode` of a `StandardIntegrityException`, or null for
 * any other throwable. Carries nothing else (no message, no cause), so no
 * SDK text can reach Dart or a log.
 */
class IntegrityFailure(val errorCode: Int?) : Exception()

/** A prepared standard-request token provider. */
fun interface IntegrityTokenSource {
  /** Requests a token bound to [requestHash]; [done] gets the token or an [IntegrityFailure]. */
  fun request(requestHash: String, done: (Result<String>) -> Unit)
}

/** Seam over `StandardIntegrityManager`, so [AttestationHost] runs on the JVM. */
fun interface IntegrityGateway {
  /** `prepareIntegrityToken(cloudProjectNumber)`; [done] gets a provider or an [IntegrityFailure]. */
  fun prepare(cloudProjectNumber: Long, done: (Result<IntegrityTokenSource>) -> Unit)
}

/**
 * The only class that touches the Play Integrity SDK (standard request).
 * `Task` listeners run on the main thread, like the Pigeon calls.
 */
class PlayIntegrityGateway(context: Context) : IntegrityGateway {
  private val appContext = context.applicationContext

  // Created on first use (inside the try below), not at engine start.
  private val manager: StandardIntegrityManager by lazy { IntegrityManagerFactory.createStandard(appContext) }

  override fun prepare(cloudProjectNumber: Long, done: (Result<IntegrityTokenSource>) -> Unit) {
    val request = try {
      PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(cloudProjectNumber).build()
    } catch (e: Exception) {
      done(Result.failure(failureOf(e)))
      return
    }
    try {
      manager.prepareIntegrityToken(request)
        .addOnSuccessListener { provider -> done(Result.success(ProviderSource(provider))) }
        .addOnFailureListener { e -> done(Result.failure(failureOf(e))) }
    } catch (e: Exception) {
      done(Result.failure(failureOf(e)))
    }
  }

  private class ProviderSource(private val provider: StandardIntegrityTokenProvider) : IntegrityTokenSource {
    override fun request(requestHash: String, done: (Result<String>) -> Unit) {
      try {
        val request = StandardIntegrityTokenRequest.builder().setRequestHash(requestHash).build()
        provider.request(request)
          .addOnSuccessListener { token ->
            val text = token.token()
            if (text.isNullOrEmpty()) done(Result.failure(IntegrityFailure(null))) else done(Result.success(text))
          }
          .addOnFailureListener { e -> done(Result.failure(failureOf(e))) }
      } catch (e: Exception) {
        done(Result.failure(failureOf(e)))
      }
    }
  }

  private companion object {
    fun failureOf(e: Throwable): IntegrityFailure =
      IntegrityFailure((e as? StandardIntegrityException)?.errorCode)
  }
}
