package app.zaghlol.platform.share

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Proof that a `SHARE_READY` intent came from [ShareActivity] (F7).
 * `MainActivity` is exported (launcher), so any app can send it that action;
 * only an intent that carries this per-process random token is honoured.
 * The token never leaves the process except inside our own explicit intent.
 */
class ShareHandOffToken(random: SecureRandom = SecureRandom()) {
    val value: String = ByteArray(16).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }

    fun matches(action: String?, presented: String?): Boolean {
        if (action != ShareHandOff.ACTION_SHARE_READY || presented == null) return false
        return MessageDigest.isEqual(value.toByteArray(Charsets.US_ASCII), presented.toByteArray(Charsets.US_ASCII))
    }
}

object ShareHandOff {
    const val ACTION_SHARE_READY = "app.zaghlol.action.SHARE_READY"
    const val EXTRA_TOKEN = "app.zaghlol.extra.SHARE_TOKEN"

    val token = ShareHandOffToken()
}
