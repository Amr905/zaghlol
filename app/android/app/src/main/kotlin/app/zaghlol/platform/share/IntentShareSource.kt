package app.zaghlol.platform.share

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
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

    /** T-263: ACTION_SEND_MULTIPLE (several photos from Gallery) carries a list; only the first is read. */
    private val uris: List<Uri> = try {
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            list?.filterNotNull().orEmpty()
        } else {
            val single = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            listOfNotNull(single)
        }
    } catch (_: RuntimeException) {
        emptyList()
    }

    private val uri: Uri? = MultiShare.first(uris)

    /** True when the sender shared more than one item and only the first is used. */
    val hasIgnoredItems: Boolean = MultiShare.hasIgnored(uris)

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

    override val streamFileName: String? by lazy {
        try {
            uri?.let { u ->
                resolver.query(u, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
                } ?: u.lastPathSegment
            }
        } catch (_: RuntimeException) {
            null
        }
    }

    override fun resolverType(): String? = try {
        uri?.let { resolver.getType(it) }
    } catch (_: RuntimeException) {
        null
    }

    /** FU-070 S1: passed to the provider, so a cancelled read can also end a blocked `openFile`. */
    private val signal = CancellationSignal()

    override fun open(): InputStream? {
        if (cancelled) return null
        val stream = try {
            uri?.let { u ->
                resolver.openAssetFileDescriptor(u, "r", signal)?.let { afd ->
                    // FU-333: do not leak the descriptor when the stream cannot be created.
                    try {
                        afd.createInputStream()
                    } catch (e: Exception) {
                        runCatching { afd.close() }
                        throw e
                    }
                }
            }
        } catch (_: android.os.OperationCanceledException) {
            null
        } ?: return null
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
        runCatching { signal.cancel() }
        opened?.let { runCatching { it.close() } }
    }
}
