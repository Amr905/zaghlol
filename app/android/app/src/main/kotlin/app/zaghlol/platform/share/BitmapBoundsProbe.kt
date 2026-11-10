package app.zaghlol.platform.share

import android.graphics.BitmapFactory

/** [ImageBoundsProbe] with `BitmapFactory.Options.inJustDecodeBounds`: reads the header only, allocates no pixels. */
object BitmapBoundsProbe : ImageBoundsProbe {
    override fun bounds(data: ByteArray, length: Int): ImageBounds? {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        try {
            BitmapFactory.decodeByteArray(data, 0, length, opts)
        } catch (_: RuntimeException) {
            return null
        }
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return null
        return ImageBounds(opts.outWidth, opts.outHeight)
    }
}
