package app.zaghlol.platform.share

import java.io.IOException
import java.io.InputStream

/** What an incoming ACTION_SEND carries, with Android types hidden so the intake logic is JVM-testable. */
interface ShareSource {
    /** The intent's declared MIME type. */
    val intentType: String?

    /** `EXTRA_TEXT`, when present. */
    val text: CharSequence?

    /** `EXTRA_STREAM` scheme (lowercase), or null when there is no stream. */
    val streamScheme: String?

    /** `EXTRA_STREAM` host (`Uri.getHost()`, lowercase, no user info or port), or null. */
    val streamHost: String?

    /** True when the stream URI carries `userinfo@` in its authority (always refused, F4). */
    val streamHasUserInfo: Boolean

    /** Package of the provider the resolver would actually use for the stream, when it can be resolved. */
    val streamProviderPackage: String?

    /** The provider's own MIME type for the stream, when it reports one. */
    fun resolverType(): String?

    /** Opens the stream; null when the provider refuses or [cancel] was called. */
    @Throws(IOException::class)
    fun open(): InputStream?

    /** Closes the opened stream from another thread so a blocked read ends (F3 deadline). Idempotent. */
    fun cancel() {}
}

sealed class ShareOutcome {
    data class Accepted(val descriptor: ShareDescriptor) : ShareOutcome()
    data class Rejected(val reason: ShareRejectReason) : ShareOutcome()
}

/** Which stream URIs may be read at all (F4). Pure, so the rules are JVM-tested. */
object ShareUriPolicy {
    fun isAllowed(source: ShareSource, ownPackage: String): Boolean {
        // A file:// URI would make us read our own private files for another app.
        if (source.streamScheme != "content") return false
        // `content://x@our.provider/...` resolves to our provider (the resolver strips a user id),
        // so any user info is refused outright.
        if (source.streamHasUserInfo) return false
        val host = source.streamHost?.lowercase()
        if (host.isNullOrEmpty()) return false
        val own = ownPackage.lowercase()
        if (host == own || host.startsWith("$own.")) return false
        // Belt and braces: whatever the authority looks like, never read from a provider of our own.
        if (source.streamProviderPackage == ownPackage) return false
        return true
    }
}
