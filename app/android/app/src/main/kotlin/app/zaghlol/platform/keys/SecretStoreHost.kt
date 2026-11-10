package app.zaghlol.platform.keys

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** Native error codes (platform-channels §6). */
object SecretStoreErrors {
  const val KEY_STORE_FAILED = "KEY_STORE_FAILED"
  const val LEASE_TIMEOUT = "LEASE_TIMEOUT"

  /** Code only: no message, no details, no cause cross the boundary. */
  fun error(code: String) = SecretStoreApiError(code, null, null)
}

/**
 * T-015: the Pigeon `SecretStoreHostApi` (platform-channels §5). Work runs on
 * [worker] (taking the lease can block); replies go through [main]. Every
 * failure is mapped to a code-only [SecretStoreApiError]; no exception text
 * reaches Dart and nothing is logged (FU-050).
 */
class SecretStoreHost(
  private val slots: (SecretSlotMsg) -> SecretSlotStore,
  private val leases: BootstrapLeaseManager = BootstrapLeaseManager.process,
  private val worker: Executor = sharedWorker,
  private val main: (Runnable) -> Unit = { mainHandler.post(it) },
) : SecretStoreHostApi {

  override fun acquireBootstrapLease(timeoutMs: Long, callback: (Result<Long>) -> Unit) =
    dispatch(callback) {
      leases.acquire(timeoutMs) ?: throw SecretStoreErrors.error(SecretStoreErrors.LEASE_TIMEOUT)
    }

  override fun releaseBootstrapLease(lease: Long, callback: (Result<Unit>) -> Unit) =
    dispatch(callback) { leases.release(lease) }

  override fun renewBootstrapLease(lease: Long, callback: (Result<Boolean>) -> Unit) =
    dispatch(callback) { leases.renew(lease) }

  override fun read(slot: SecretSlotMsg, callback: (Result<SecretReadMsg>) -> Unit) =
    dispatch(callback, wipe = { it.value?.fill(0) }) {
      val r =
        try {
          slots(slot).read()
        } catch (e: Throwable) {
          SlotRead(SecretStatusMsg.UNAVAILABLE, null, 1)
        }
      SecretReadMsg(r.status, if (r.status == SecretStatusMsg.FOUND) r.value else null, r.attempts.toLong())
    }

  override fun createIfAbsent(
    lease: Long,
    slot: SecretSlotMsg,
    candidate: ByteArray,
    callback: (Result<ByteArray>) -> Unit,
  ) =
    dispatch(callback, wipe = { it.fill(0) }) {
      try {
        requireLease(lease)
        slots(slot).createIfAbsent(candidate)
      } finally {
        candidate.fill(0)
      }
    }

  override fun delete(lease: Long, slot: SecretSlotMsg, callback: (Result<Unit>) -> Unit) =
    dispatch(callback) {
      requireLease(lease)
      slots(slot).delete()
    }

  private fun requireLease(lease: Long) {
    if (!leases.isValid(lease)) throw SecretStoreErrors.error(SecretStoreErrors.LEASE_TIMEOUT)
  }

  /**
   * Runs [body] on the worker and replies on the main thread. [wipe] runs on
   * a successful value after [callback] returns (S-6): the Pigeon reply
   * encodes the value into its own buffer synchronously inside the callback,
   * so the plaintext key bytes we hold are no longer needed.
   */
  private fun <T> dispatch(
    callback: (Result<T>) -> Unit,
    wipe: (T) -> Unit = {},
    body: () -> T,
  ) {
    worker.execute {
      val result: Result<T> =
        try {
          Result.success(body())
        } catch (e: SecretStoreApiError) {
          Result.failure(SecretStoreErrors.error(e.code))
        } catch (e: Throwable) {
          Result.failure(SecretStoreErrors.error(SecretStoreErrors.KEY_STORE_FAILED))
        }
      main(
        Runnable {
          try {
            callback(result)
          } finally {
            result.getOrNull()?.let { value -> runCatching { wipe(value) } }
          }
        }
      )
    }
  }

  companion object {
    private val sharedWorker: Executor by lazy { Executors.newCachedThreadPool() }
    private val mainHandler: Handler by lazy { Handler(Looper.getMainLooper()) }
  }
}

/**
 * Registers the secret store on an engine. Must be called for **every**
 * engine that opens the database: the UI engine (MainActivity) and the T-008
 * headless engine. All engines share one store and one lease per process.
 */
object SecretStoreRegistration {
  @Volatile private var dbKeyStore: DbKeyStore? = null

  private fun dbKeyStore(context: Context): DbKeyStore =
    dbKeyStore
      ?: synchronized(this) {
        dbKeyStore
          ?: DbKeyStore(
              dir = File(context.applicationContext.noBackupFilesDir, "keys"),
              kek = AndroidKeystoreKek(),
            )
            .also { dbKeyStore = it }
      }

  fun register(messenger: BinaryMessenger, context: Context) {
    val store = dbKeyStore(context)
    SecretStoreHostApi.setUp(
      messenger,
      SecretStoreHost(
        slots = { slot ->
          when (slot) {
            SecretSlotMsg.DB_KEY -> store
          }
        }
      ),
    )
  }
}
