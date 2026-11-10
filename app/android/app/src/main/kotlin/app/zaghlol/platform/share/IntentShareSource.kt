package app.zaghlol.platform.share

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import java.io.InputStream

/** [ShareSource] over an ACTION_SEND intent. Malformed extras are treated as absent, never thrown. */
class IntentShareSource(
    context: Context,
    intent: Intent,
) : ShareSource {
    private val resolver = context.contentResolver

    override val intentType: String? = intent.type

    override val text: CharSequence? = try {
        intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
    } catch (_: RuntimeException) {
        null
    }

    private val uri: Uri? = try {
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
    } catch (_: RuntimeException) {
        null
    }

    override val streamScheme: String? = uri?.scheme?.lowercase()
    override val streamHost: String? = uri?.host?.lowercase()
    override val streamHasUserInfo: Boolean = uri?.userInfo != null || uri?.encodedAuthority?.contains('@') == true

    override val streamProviderPackage: String? = try {
        uri?.authority?.let { auth ->
            // The resolver strips a `userId@` prefix the same way (ContentProvider.getAuthorityWithoutUserId).
            val name = auth.substringAfterLast('@')
            val pm = context.packageManager
            val info = if (Build.VERSION.SDK_INT >= 33) {
                pm.resolveContentProvider(name, PackageManager.ComponentInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.resolveContentProvider(name, 0)
            }
            info?.packageName
        }
    } catch (_: RuntimeException) {
        null
    }

    @Volatile private var cancelled = false
    @Volatile private var opened: InputStream? = null

    override fun resolverType(): String? = try {
        uri?.let { resolver.getType(it) }
    } catch (_: RuntimeException) {
        null
    }

    override fun open(): InputStream? {
        if (cancelled) return null
        val stream = uri?.let { resolver.openInputStream(it) } ?: return null
        opened = stream
        // cancel() may have run between the check above and the assignment.
        if (cancelled) {
            runCatching { stream.close() }
            return null
        }
        return stream
    }

    override fun cancel() {
        cancelled = true
        opened?.let { runCatching { it.close() } }
    }
}
