package app.zaghlol.platform.attestation

import android.content.Context
import app.zaghlol.BuildConfig
import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import io.flutter.plugin.common.BinaryMessenger
import java.util.Base64

/**
 * T-178: the Pigeon `AttestationHostApi` on Android (platform-channels §4a).
 * Play Integrity **standard request**, bound to the exact 32 bytes Dart
 * passes (R2-1): `requestHash = base64url(bodyHash)`, unpadded. Native code
 * never builds or alters the hash and never sees the install ID.
 *
 * Threading: Pigeon calls and the SDK's `Task` listeners both run on the main
 * thread, so the cached provider and the waiter list are main-thread
 * confined. Concurrent prepares coalesce into one SDK call.
 *
 * Errors are code-only [AttestationApiError]s (`message`/`details` null), so
 * no token, hash or SDK text crosses the boundary. Nothing here logs.
 */
class AttestationHost(
  private val gateway: IntegrityGateway,
  private val cloudProjectNumber: Long,
) : AttestationHostApi {
  private var provider: IntegrityTokenSource? = null
  private var waiters: MutableList<(Result<IntegrityTokenSource>) -> Unit>? = null

  override fun prepare(callback: (Result<Unit>) -> Unit) {
    ensureProvider { result ->
      callback(result.fold({ Result.success(Unit) }, { Result.failure(mapFailure(it)) }))
    }
  }

  override fun attest(bodyHash: ByteArray, forceNewKey: Boolean, callback: (Result<AttestationProof>) -> Unit) {
    // forceNewKey is iOS-only (App Attest keys); Play Integrity has no key.
    if (bodyHash.size != HASH_LENGTH) {
      callback(Result.failure(apiError(ATTEST_UNAVAILABLE)))
      return
    }
    val requestHash = requestHashOf(bodyHash)
    requestToken(requestHash, providerRetried = false, callback)
  }

  private fun requestToken(
    requestHash: String,
    providerRetried: Boolean,
    callback: (Result<AttestationProof>) -> Unit,
  ) {
    ensureProvider { prepared ->
      val source = prepared.getOrElse {
        callback(Result.failure(mapFailure(it)))
        return@ensureProvider
      }
      source.request(requestHash) { result ->
        result.fold(
          { token -> callback(Result.success(AttestationProof(type = TYPE_PLAY_INTEGRITY, token = token))) },
          { e ->
            val code = (e as? IntegrityFailure)?.errorCode
            if (code == StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID && !providerRetried) {
              // Re-prepare once: drop this provider (unless another call already replaced it).
              if (provider === source) provider = null
              requestToken(requestHash, providerRetried = true, callback)
            } else {
              callback(Result.failure(mapFailure(e)))
            }
          },
        )
      }
    }
  }

  private fun ensureProvider(done: (Result<IntegrityTokenSource>) -> Unit) {
    provider?.let {
      done(Result.success(it))
      return
    }
    if (cloudProjectNumber <= 0L) {
      // Fail closed: no project number in this build, never call Google.
      done(Result.failure(IntegrityFailure(null)))
      return
    }
    waiters?.let {
      it.add(done)
      return
    }
    val list = mutableListOf(done)
    waiters = list
    gateway.prepare(cloudProjectNumber) { result ->
      waiters = null
      result.onSuccess { provider = it }
      list.forEach { it(result) }
    }
  }

  companion object {
    const val ATTEST_TRANSIENT = "ATTEST_TRANSIENT"
    const val ATTEST_PLAY_SERVICES_OUTDATED = "ATTEST_PLAY_SERVICES_OUTDATED"
    const val ATTEST_UNAVAILABLE = "ATTEST_UNAVAILABLE"
    const val TYPE_PLAY_INTEGRITY = "play_integrity"
    const val HASH_LENGTH = 32

    /** base64url without padding (43 chars for 32 bytes), as the server expects. */
    fun requestHashOf(bodyHash: ByteArray): String = Base64.getUrlEncoder().encodeToString(bodyHash)

    /** `StandardIntegrityErrorCode` (or null: not a Play error) → contract code (§6). */
    fun mapErrorCode(code: Int?): String =
      when (code) {
        StandardIntegrityErrorCode.NETWORK_ERROR,
        StandardIntegrityErrorCode.TOO_MANY_REQUESTS,
        StandardIntegrityErrorCode.GOOGLE_SERVER_UNAVAILABLE,
        StandardIntegrityErrorCode.CLIENT_TRANSIENT_ERROR,
        -> ATTEST_TRANSIENT
        // Reached only after the one re-prepare (or from prepare() itself).
        StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID -> ATTEST_TRANSIENT
        StandardIntegrityErrorCode.PLAY_SERVICES_VERSION_OUTDATED,
        StandardIntegrityErrorCode.PLAY_STORE_VERSION_OUTDATED,
        -> ATTEST_PLAY_SERVICES_OUTDATED
        else -> ATTEST_UNAVAILABLE
      }

    private fun mapFailure(e: Throwable): AttestationApiError =
      apiError(mapErrorCode((e as? IntegrityFailure)?.errorCode))

    private fun apiError(code: String) = AttestationApiError(code, null, null)
  }
}

/** Registers the attestation host on the UI engine (restore runs in the foreground). */
object AttestationRegistration {
  fun register(messenger: BinaryMessenger, context: Context) {
    AttestationHostApi.setUp(
      messenger,
      AttestationHost(PlayIntegrityGateway(context), BuildConfig.PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER),
    )
  }

  fun unregister(messenger: BinaryMessenger) {
    AttestationHostApi.setUp(messenger, null)
  }
}
