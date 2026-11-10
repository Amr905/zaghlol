package app.zaghlol.platform.share

import java.util.concurrent.atomic.AtomicReference

/**
 * Process-wide slot for the last refusal (a refused share has nothing on disk).
 * Accepted shares are not announced through here: Dart and `MainActivity`
 * always list the store, so two quick shares are never collapsed (F7).
 */
object ShareIntakeState {
    private val rejection = AtomicReference<ShareRejectReason?>(null)

    fun setRejected(r: ShareRejectReason) = rejection.set(r)
    fun takeRejection(): ShareRejectReason? = rejection.getAndSet(null)
}

/** Pigeon host implementation. Errors carry codes from platform-channels.md and never any content. */
class ShareIntakeHost(private val store: ShareStore) : ShareIntakeHostApi {
    override fun listPendingShares(): List<ShareDescriptor> = try {
        store.list()
    } catch (_: java.io.IOException) {
        throw ShareIntakeApiError("IO_ERROR", "could not list shares")
    }

    override fun readShare(id: String): ShareContent = try {
        store.read(id)
    } catch (_: ShareStore.NotFound) {
        throw ShareIntakeApiError("IO_ERROR", "unknown share")
    } catch (_: ShareStore.Transient) {
        // F6: the share is kept; Dart may retry.
        throw ShareIntakeApiError("IO_ERROR", "share could not be read now")
    } catch (_: OutOfMemoryError) {
        throw ShareIntakeApiError("IO_ERROR", "share could not be read now")
    } catch (_: ShareStore.DecryptFailed) {
        throw ShareIntakeApiError("SPOOL_DECRYPT_FAILED", "share could not be decrypted")
    }

    override fun discardShare(id: String) = try {
        store.discard(id)
    } catch (_: ShareStore.NotFound) {
        // Idempotent: an invalid or unknown id is already gone.
    }

    override fun takePendingRejection(): ShareRejectReason? = ShareIntakeState.takeRejection()
}
