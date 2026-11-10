package app.zaghlol.platform.share

/** Hard limits for shared content (T-060). Enforced on bytes actually read, never on declared sizes. */
object ShareLimits {
    const val TEXT_MAX_CHARS = 100_000
    const val IMAGE_MAX_BYTES = 15L * 1024 * 1024
    const val PDF_MAX_BYTES = 20L * 1024 * 1024
    const val CSV_MAX_BYTES = 5L * 1024 * 1024

    /** UTF-8 needs at most 4 bytes per UTF-16 char pair; this bounds a text stream. */
    const val TEXT_MAX_BYTES = TEXT_MAX_CHARS.toLong() * 4

    /**
     * Decoded image size cap (F9): width x height. 64 MP covers long scrolling
     * screenshots and 50 MP camera photos; larger images are refused as
     * `tooLarge` before anything is stored. The OCR side still decodes with a
     * sample size (T-161).
     */
    const val IMAGE_MAX_PIXELS = 64_000_000L

    /**
     * Images are probed for their bounds on this many leading bytes (held in
     * memory). Most phone images fit entirely; image headers always sit near
     * the start. An image whose bounds cannot be read from it is refused.
     */
    const val IMAGE_PROBE_BYTES = 4 * 1024 * 1024

    /** Pending-share caps (F2): count and total bytes on disk. Over either, a new share is refused as `tooLarge`. */
    const val MAX_PENDING_SHARES = 10
    const val MAX_PENDING_BYTES = 100L * 1024 * 1024

    /** Whole-intake deadline (F3), counted from when the share arrived. Then the read is aborted. */
    const val INTAKE_TIMEOUT_MS = 20_000L

    /** Extra time after [INTAKE_TIMEOUT_MS] before the share activity gives up on the worker. */
    const val INTAKE_GRACE_MS = 3_000L

    /** A share that Dart has not picked up after this long is deleted. */
    const val STALE_AFTER_MS = 24L * 60 * 60 * 1000

    fun maxBytes(kind: ShareKind): Long = when (kind) {
        ShareKind.TEXT -> TEXT_MAX_BYTES
        ShareKind.IMAGE -> IMAGE_MAX_BYTES
        ShareKind.PDF -> PDF_MAX_BYTES
        ShareKind.CSV -> CSV_MAX_BYTES
    }
}
