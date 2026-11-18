package app.zaghlol.platform.ocr

import android.content.res.AssetManager
import com.googlecode.tesseract.android.TessBaseAPI
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Tesseract4Android with the bundled `ara` fast model (LSTM only). A fresh
 * `TessBaseAPI` per call, always recycled in `finally`. A watchdog calls
 * `stop()` at the deadline; the call then fails as timed out.
 */
class TesseractArabicEngine(
    private val assets: AssetManager,
    private val installer: TessdataInstaller,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
) : ArabicOcrEngine {
    @Volatile private var verified = false

    private val watchdog: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "zaghlol-ocr-watchdog").apply { isDaemon = true }
    }

    override fun ensureAvailable(): Boolean {
        if (verified) return true
        return try {
            installer.ensureInstalled()
            verified = true
            true
        } catch (_: IOException) {
            false
        } catch (_: RuntimeException) {
            false
        }
    }

    override fun likelyAvailable(): Boolean = verified || try {
        assets.list("tessdata")?.contains(TessdataSpec.FILE_NAME) == true
    } catch (_: IOException) {
        false
    }

    override fun recognize(image: DecodedImage, deadlineAtMs: Long): List<RawLine> {
        val bitmap = (image as? BitmapImage)?.bitmap ?: throw OcrFailure(OcrFailure.OCR_FAILED, "unsupported image")
        if (!ensureAvailable()) throw OcrFailure(OcrFailure.NOT_AVAILABLE, "Arabic model unavailable")
        val tess = TessBaseAPI()
        val timedOut = AtomicBoolean(false)
        val timer = watchdog.schedule(
            Runnable {
                timedOut.set(true)
                tess.stop()
            },
            (deadlineAtMs - clock()).coerceAtLeast(1),
            TimeUnit.MILLISECONDS,
        )
        try {
            if (!tess.init(installer.dataPath, "ara", TessBaseAPI.OEM_LSTM_ONLY)) {
                throw OcrFailure(OcrFailure.OCR_FAILED, "recognition failed")
            }
            tess.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
            tess.setImage(bitmap)
            tess.getUTF8Text() // runs the recognition
            if (timedOut.get()) throw OcrFailure(OcrFailure.OCR_FAILED, "recognition timed out")
            val out = ArrayList<RawLine>()
            val it = tess.resultIterator ?: return out
            try {
                val level = TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE
                it.begin()
                do {
                    val text = it.getUTF8Text(level)?.trim().orEmpty()
                    val box = it.getBoundingRect(level)
                    if (text.isNotEmpty() && box != null) {
                        out.add(RawLine(text, it.confidence(level) / 100.0, box.left, box.top, box.right, box.bottom))
                    }
                } while (it.next(level))
            } finally {
                it.delete()
            }
            if (timedOut.get()) throw OcrFailure(OcrFailure.OCR_FAILED, "recognition timed out")
            return out
        } finally {
            timer.cancel(false)
            tess.recycle()
        }
    }
}
