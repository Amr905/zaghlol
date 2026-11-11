package app.zaghlol.platform.guard

import android.content.res.AssetManager
import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Reads the bundled base part `assets/guard/guard_base.json` (Flutter asset,
 * generated from the registry by T-036) without a Flutter engine. Plaintext
 * public registry data, protected by the app signature.
 */
object BaseConfigSource {
    /** Where Flutter packs `app/assets/guard/guard_base.json` in the APK. */
    const val ASSET_PATH = "flutter_assets/assets/guard/guard_base.json"

    /**
     * The base bytes, at most [GuardConfig.MAX_BASE_BYTES] + 1 (a larger
     * asset is cut there, so the reader reports `tooLarge`). Throws when the
     * asset is missing or unreadable; the runtime maps that to mode `invalid`
     * and retries on the next load.
     */
    fun read(assets: AssetManager): ByteArray = assets.open(ASSET_PATH).use { readBounded(it, GuardConfig.MAX_BASE_BYTES) }

    /** Reads up to [max] + 1 bytes: enough to tell "too large" without reading an unbounded stream. */
    fun readBounded(input: InputStream, max: Int): ByteArray {
        val out = ByteArrayOutputStream(minOf(max + 1, 64 * 1024))
        val buf = ByteArray(8 * 1024)
        var total = 0
        while (total <= max) {
            val n = input.read(buf, 0, minOf(buf.size, max + 1 - total))
            if (n < 0) break
            out.write(buf, 0, n)
            total += n
        }
        return out.toByteArray()
    }
}
