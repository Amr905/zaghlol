package app.zaghlol.platform.share

/** Hard limits for shared content (T-060). Enforced on bytes actually read, never on declared sizes. */
object ShareLimits {
    const val TEXT_MAX_CHARS = 100_000
    const val IMAGE_MAX_BYTES = 15L * 1024 * 1024
    const val PDF_MAX_BYTES = 20L * 1024 * 1024
    const val CSV_MAX_BYTES = 5L * 1024 * 1024

    /** A share that Dart has not picked up after this long is deleted. */
    const val STALE_AFTER_MS = 24L * 60 * 60 * 1000

    /** UTF-8 needs at most 4 bytes per UTF-16 char pair; this bounds a text stream. */
    const val TEXT_MAX_BYTES = TEXT_MAX_CHARS.toLong() * 4

    fun maxBytes(kind: ShareKind): Long = when (kind) {
        ShareKind.TEXT -> TEXT_MAX_BYTES
        ShareKind.IMAGE -> IMAGE_MAX_BYTES
        ShareKind.PDF -> PDF_MAX_BYTES
        ShareKind.CSV -> CSV_MAX_BYTES
    }
}
