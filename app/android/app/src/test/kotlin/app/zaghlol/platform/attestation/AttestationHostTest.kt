package app.zaghlol.platform.attestation

import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode as Code
import java.io.File
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * T-178 (platform-channels §4a): R2-1 hash pass-through, provider caching and
 * the one re-prepare, the error map, fail-closed config and code-only errors.
 * The Play SDK sits behind [IntegrityGateway]; all values are synthetic.
 */
class AttestationHostTest {
  /** Scripted gateway: records every call; answers synchronously unless [deferPrepare]. */
  private class FakeGateway : IntegrityGateway {
    val prepareCalls = mutableListOf<Long>()
    val requestHashes = mutableListOf<String>()
    /** Results for successive prepare calls; success when empty. */
    val prepareFailures = ArrayDeque<Int?>()
    /** Results for successive requests: a token, or an error code (Int) / null-code failure. */
    val requestScript = ArrayDeque<Any?>()
    var deferPrepare = false
    val deferred = mutableListOf<(Result<IntegrityTokenSource>) -> Unit>()

    private val source = IntegrityTokenSource { hash, done ->
      requestHashes += hash
      when (val next = if (requestScript.isEmpty()) "token-${requestHashes.size}" else requestScript.removeFirst()) {
        is String -> done(Result.success(next))
        is Int -> done(Result.failure(IntegrityFailure(next)))
        else -> done(Result.failure(IntegrityFailure(null)))
      }
    }

    override fun prepare(cloudProjectNumber: Long, done: (Result<IntegrityTokenSource>) -> Unit) {
      prepareCalls += cloudProjectNumber
      if (deferPrepare) {
        deferred += done
        return
      }
      answer(done)
    }

    fun answer(done: (Result<IntegrityTokenSource>) -> Unit) {
      if (prepareFailures.isNotEmpty()) {
        done(Result.failure(IntegrityFailure(prepareFailures.removeFirst())))
      } else {
        done(Result.success(source))
      }
    }
  }

  private val project = 123456789012L

  private fun hash(seed: Int = 7) = ByteArray(32) { ((seed + 31 * it) and 0xFF).toByte() }

  private fun attest(host: AttestationHost, bytes: ByteArray): Result<AttestationProof> {
    var out: Result<AttestationProof>? = null
    host.attest(bytes, false) { out = it }
    return out ?: error("no callback")
  }

  private fun codeOf(result: Result<*>): String {
    val e = result.exceptionOrNull() as? AttestationApiError ?: error("expected AttestationApiError")
    // Code only: nothing from the SDK, the hash or a token crosses the boundary.
    assertNull(e.message)
    assertNull(e.details)
    assertNull(e.cause)
    return e.code
  }

  // R2-1: the requestHash is base64url (unpadded) of exactly the Dart bytes.
  @Test
  fun requestHashIsUnpaddedBase64UrlOfTheExactInput() {
    val gw = FakeGateway()
    val host = AttestationHost(gw, project)
    val input = hash()
    val proof = attest(host, input).getOrThrow()

    assertEquals(1, gw.requestHashes.size)
    val sent = gw.requestHashes.single()
    assertEquals(43, sent.length)
    assertTrue(sent.none { it == '=' || it == '+' || it == '/' })
    assertArrayEquals(input, Base64.getUrlDecoder().decode(sent))
    assertEquals("play_integrity", proof.type)
    assertEquals("token-1", proof.token)
    assertNull(proof.keyId)
    assertNull(proof.assertion)
    assertNull(proof.attestationObject)
  }

  // R2-1 against the shared vectors the backend checks (restore-binding-v1.json).
  @Test
  fun requestHashMatchesEverySharedVector() {
    val path = System.getProperty("zaghlol.bindingVectors") ?: error("zaghlol.bindingVectors not set")
    val text = File(path).readText()
    val pairs = Regex("\"bodyHashHex\":\\s*\"([0-9a-f]{64})\",\\s*\"requestHashB64u\":\\s*\"([A-Za-z0-9_-]+)\"")
      .findAll(text).map { it.groupValues[1] to it.groupValues[2] }.toList()
    assertTrue("no vectors found", pairs.size >= 2)
    for ((hex, b64u) in pairs) {
      val bytes = ByteArray(32) { hex.substring(2 * it, 2 * it + 2).toInt(16).toByte() }
      val gw = FakeGateway()
      attest(AttestationHost(gw, project), bytes).getOrThrow()
      assertEquals(b64u, gw.requestHashes.single())
      assertEquals(b64u, AttestationHost.requestHashOf(bytes))
    }
  }

  @Test
  fun providerIsPreparedOnceAndCached() {
    val gw = FakeGateway()
    val host = AttestationHost(gw, project)
    var prepared: Result<Unit>? = null
    host.prepare { prepared = it }
    assertTrue(prepared!!.isSuccess)
    attest(host, hash(1)).getOrThrow()
    attest(host, hash(2)).getOrThrow()
    assertEquals(listOf(project), gw.prepareCalls)
  }

  // Two actors: concurrent calls while prepare is in flight share one SDK prepare.
  @Test
  fun concurrentCallsCoalesceIntoOnePrepare() {
    val gw = FakeGateway().apply { deferPrepare = true }
    val host = AttestationHost(gw, project)
    val results = mutableListOf<Result<AttestationProof>>()
    host.attest(hash(1), false) { results += it }
    host.attest(hash(2), false) { results += it }
    var prepared: Result<Unit>? = null
    host.prepare { prepared = it }
    assertEquals(1, gw.prepareCalls.size)
    gw.answer(gw.deferred.single())
    assertEquals(2, results.size)
    assertTrue(results.all { it.isSuccess })
    assertTrue(prepared!!.isSuccess)
    assertArrayEquals(hash(1), Base64.getUrlDecoder().decode(gw.requestHashes[0]))
    assertArrayEquals(hash(2), Base64.getUrlDecoder().decode(gw.requestHashes[1]))
  }

  @Test
  fun providerInvalidRePreparesOnceThenSucceeds() {
    val gw = FakeGateway()
    gw.requestScript += Code.INTEGRITY_TOKEN_PROVIDER_INVALID
    gw.requestScript += "fresh-token"
    val input = hash()
    val proof = attest(AttestationHost(gw, project), input).getOrThrow()
    assertEquals("fresh-token", proof.token)
    assertEquals(2, gw.prepareCalls.size)
    // The retry carries the same bytes.
    assertEquals(gw.requestHashes[0], gw.requestHashes[1])
    assertArrayEquals(input, Base64.getUrlDecoder().decode(gw.requestHashes[1]))
  }

  @Test
  fun providerInvalidTwiceIsTransientWithoutLooping() {
    val gw = FakeGateway()
    gw.requestScript += Code.INTEGRITY_TOKEN_PROVIDER_INVALID
    gw.requestScript += Code.INTEGRITY_TOKEN_PROVIDER_INVALID
    gw.requestScript += "never-reached"
    assertEquals("ATTEST_TRANSIENT", codeOf(attest(AttestationHost(gw, project), hash())))
    assertEquals(2, gw.prepareCalls.size)
    assertEquals(2, gw.requestHashes.size)
  }

  // The full error map (platform-channels §4a / §6), for request and prepare.
  @Test
  fun errorMapCoversEveryStandardCode() {
    val expected = mapOf<Int?, String>(
      Code.NETWORK_ERROR to "ATTEST_TRANSIENT",
      Code.TOO_MANY_REQUESTS to "ATTEST_TRANSIENT",
      Code.GOOGLE_SERVER_UNAVAILABLE to "ATTEST_TRANSIENT",
      Code.CLIENT_TRANSIENT_ERROR to "ATTEST_TRANSIENT",
      Code.INTEGRITY_TOKEN_PROVIDER_INVALID to "ATTEST_TRANSIENT",
      Code.PLAY_SERVICES_VERSION_OUTDATED to "ATTEST_PLAY_SERVICES_OUTDATED",
      Code.PLAY_STORE_VERSION_OUTDATED to "ATTEST_PLAY_SERVICES_OUTDATED",
      Code.API_NOT_AVAILABLE to "ATTEST_UNAVAILABLE",
      Code.PLAY_STORE_NOT_FOUND to "ATTEST_UNAVAILABLE",
      Code.APP_NOT_INSTALLED to "ATTEST_UNAVAILABLE",
      Code.PLAY_SERVICES_NOT_FOUND to "ATTEST_UNAVAILABLE",
      Code.APP_UID_MISMATCH to "ATTEST_UNAVAILABLE",
      Code.CANNOT_BIND_TO_SERVICE to "ATTEST_UNAVAILABLE",
      Code.CLOUD_PROJECT_NUMBER_IS_INVALID to "ATTEST_UNAVAILABLE",
      Code.REQUEST_HASH_TOO_LONG to "ATTEST_UNAVAILABLE",
      Code.INTERNAL_ERROR to "ATTEST_UNAVAILABLE",
      -999 to "ATTEST_UNAVAILABLE",
      null to "ATTEST_UNAVAILABLE",
    )
    for ((code, want) in expected) {
      assertEquals("map $code", want, AttestationHost.mapErrorCode(code))

      // Through prepare (attest and prepare()).
      val gw = FakeGateway().apply { prepareFailures += code; prepareFailures += code }
      val host = AttestationHost(gw, project)
      assertEquals("attest/prepare $code", want, codeOf(attest(host, hash())))
      var prepared: Result<Unit>? = null
      host.prepare { prepared = it }
      assertEquals("prepare() $code", want, codeOf(prepared!!))
      assertTrue(gw.requestHashes.isEmpty())

      // Through request (provider-invalid is covered by its own tests).
      if (code != Code.INTEGRITY_TOKEN_PROVIDER_INVALID) {
        val gw2 = FakeGateway().apply { requestScript += code }
        assertEquals("request $code", want, codeOf(attest(AttestationHost(gw2, project), hash())))
        assertEquals(1, gw2.prepareCalls.size)
      }
    }
  }

  // Fail closed: no cloud project number in this build → never call Google.
  @Test
  fun missingProjectNumberFailsClosedWithoutCallingGoogle() {
    for (bad in listOf(0L, -1L)) {
      val gw = FakeGateway()
      val host = AttestationHost(gw, bad)
      assertEquals("ATTEST_UNAVAILABLE", codeOf(attest(host, hash())))
      var prepared: Result<Unit>? = null
      host.prepare { prepared = it }
      assertEquals("ATTEST_UNAVAILABLE", codeOf(prepared!!))
      assertTrue(gw.prepareCalls.isEmpty())
      assertTrue(gw.requestHashes.isEmpty())
    }
  }

  @Test
  fun wrongLengthHashIsRefusedWithoutCallingGoogle() {
    for (n in listOf(0, 31, 33, 64)) {
      val gw = FakeGateway()
      assertEquals("ATTEST_UNAVAILABLE", codeOf(attest(AttestationHost(gw, project), ByteArray(n))))
      assertTrue(gw.prepareCalls.isEmpty())
      assertTrue(gw.requestHashes.isEmpty())
    }
  }

  @Test
  fun forceNewKeyDoesNotChangeTheAndroidRequest() {
    val gw = FakeGateway()
    val host = AttestationHost(gw, project)
    var out: Result<AttestationProof>? = null
    host.attest(hash(), true) { out = it }
    assertEquals("play_integrity", out!!.getOrThrow().type)
    assertArrayEquals(hash(), Base64.getUrlDecoder().decode(gw.requestHashes.single()))
  }

  @Test
  fun aFailedPrepareIsNotCached() {
    val gw = FakeGateway().apply { prepareFailures += Code.NETWORK_ERROR }
    val host = AttestationHost(gw, project)
    assertEquals("ATTEST_TRANSIENT", codeOf(attest(host, hash())))
    attest(host, hash()).getOrThrow()
    assertEquals(2, gw.prepareCalls.size)
  }
}
