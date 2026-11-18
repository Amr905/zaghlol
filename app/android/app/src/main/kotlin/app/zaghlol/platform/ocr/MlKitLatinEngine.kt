package app.zaghlol.platform.ocr

import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * ML Kit Text Recognition v2, Latin script, **bundled** model (no Play Services
 * download, runs offline). Must run off the main thread (it blocks on the task).
 */
class MlKitLatinEngine(private val clock: () -> Long = { System.nanoTime() / 1_000_000 }) : OcrEngine {
    override fun recognize(image: DecodedImage, deadlineAtMs: Long): List<RawLine> {
        val bitmap = (image as? BitmapImage)?.bitmap ?: throw OcrFailure(OcrFailure.OCR_FAILED, "unsupported image")
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            val remaining = (deadlineAtMs - clock()).coerceAtLeast(1)
            val text = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)), remaining, TimeUnit.MILLISECONDS)
            val out = ArrayList<RawLine>()
            for (block in text.textBlocks) {
                for (line in block.lines) {
                    val box = line.boundingBox ?: continue
                    out.add(RawLine(line.text, line.confidence.toDouble(), box.left, box.top, box.right, box.bottom))
                }
            }
            return out
        } catch (_: TimeoutException) {
            throw OcrFailure(OcrFailure.OCR_FAILED, "recognition timed out")
        } catch (_: ExecutionException) {
            throw OcrFailure(OcrFailure.OCR_FAILED, "recognition failed")
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            throw OcrFailure(OcrFailure.OCR_FAILED, "recognition interrupted")
        } finally {
            recognizer.close()
        }
    }
}
