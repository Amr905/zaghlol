package app.zaghlol.platform.share

import java.io.IOException
import java.io.InputStream

/** What an incoming ACTION_SEND carries, with Android types hidden so the intake logic is JVM-testable. */
interface ShareSource {
    /** The intent's declared MIME type. */
    val intentType: String?

    /** `EXTRA_TEXT`, when present. */
    val text: CharSequence?

    /** `EXTRA_STREAM` scheme and authority, or null when there is no stream. */
    val streamScheme: String?
    val streamAuthority: String?

    /** The provider's own MIME type for the stream, when it reports one. */
    fun resolverType(): String?

    /** Opens the stream; null when the provider refuses. */
    @Throws(IOException::class)
    fun open(): InputStream?
}

sealed class ShareOutcome {
    data class Accepted(val descriptor: ShareDescriptor) : ShareOutcome()
    data class Rejected(val reason: ShareRejectReason) : ShareOutcome()
}
