package app.zaghlol.platform.share

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.io.InputStream

/** [ShareSource] over an ACTION_SEND intent. Malformed extras are treated as absent, never thrown. */
class IntentShareSource(
    private val resolver: ContentResolver,
    intent: Intent,
) : ShareSource {
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
    override val streamAuthority: String? = uri?.authority

    override fun resolverType(): String? = try {
        uri?.let { resolver.getType(it) }
    } catch (_: RuntimeException) {
        null
    }

    override fun open(): InputStream? = uri?.let { resolver.openInputStream(it) }
}
