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

    /** Display name of the shared file when known (used only to rescue generic CSV MIME types). */
    val streamFileName: String? get() = null

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
        // FU-070 S2: providers our own permissions unlock (READ_SMS, contacts, call log):
        // a sender could make us copy the user's messages into a share.
        if (host in SYSTEM_AUTHORITIES) return false
        // Belt and braces: whatever the authority looks like, never read from a provider of our own.
        if (source.streamProviderPackage == ownPackage) return false
        // FU-330: other Telephony authorities (sms-changes, OEM/RCS) are refused by the provider package.
        if (source.streamProviderPackage in SYSTEM_PROVIDER_PACKAGES) return false
        return true
    }

    val SYSTEM_PROVIDER_PACKAGES: Set<String> = setOf("com.android.providers.telephony")

    /** FU-070 S2: authorities of system providers our permissions can read. `media` is allowed (gallery shares). */
    val SYSTEM_AUTHORITIES: Set<String> = setOf("sms", "mms", "mms-sms", "call_log", "com.android.contacts", "contacts")
}

/** T-263: several items in one share (`ACTION_SEND_MULTIPLE`): the first is read, the rest are ignored and the user is told. */
object MultiShare {
    fun <T> first(items: List<T>): T? = items.firstOrNull()

    fun hasIgnored(items: List<*>): Boolean = items.size > 1
}
