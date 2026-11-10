package app.zaghlol.platform.share

import java.util.concurrent.atomic.AtomicReference

/** Process-wide hand-off between [ShareActivity] and the Flutter side (same process). */
object ShareIntakeState {
    private val rejection = AtomicReference<ShareRejectReason?>(null)
    private val received = AtomicReference<ShareDescriptor?>(null)

    fun setRejected(r: ShareRejectReason) = rejection.set(r)
    fun takeRejection(): ShareRejectReason? = rejection.getAndSet(null)
    fun setReceived(d: ShareDescriptor) = received.set(d)
    fun takeReceived(): ShareDescriptor? = received.getAndSet(null)
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
