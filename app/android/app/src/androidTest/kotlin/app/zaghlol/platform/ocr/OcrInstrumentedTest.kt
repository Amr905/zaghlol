package app.zaghlol.platform.ocr

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.zaghlol.platform.share.ShareKind
import app.zaghlol.platform.share.ShareStores
import java.io.ByteArrayOutputStream
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs on a device or emulator (`./gradlew connectedDevNoSmsDebugAndroidTest`)
 * with the real ML Kit and Tesseract engines and the real Keystore-backed share
 * store. Synthetic images only. This is a smoke test with a loose accuracy bar;
 * the SPK-02 accuracy table (T-010) is not reproduced by it.
 */
@RunWith(AndroidJUnit4::class)
class OcrInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = ShareStores.create(context)
    private val executor = OcrHosts.create(context, store)

    @After
    fun cleanUp() {
        store.list().forEach { store.discard(it.id) }
        executor.second.shutdownNow()
    }

    private fun synthetic(): ByteArray {
        val bmp = Bitmap.createBitmap(1080, 600, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.WHITE)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 64f
            typeface = Typeface.DEFAULT
        }
        c.drawText("EGP 1250.00", 60f, 160f, p)
        c.drawText("Ref 98127465", 60f, 280f, p)
        p.textAlign = Paint.Align.RIGHT
        c.drawText("تم التحويل بنجاح", 1020f, 440f, p)
        return ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun share(bytes: ByteArray): String {
        val w = store.newWriter(ShareKind.IMAGE, "image/png")
        w.write(bytes, 0, bytes.size)
        return w.commit().id
    }

    private object ShareStoreDir {
        fun of(c: android.content.Context) = ShareStores.dir(c)
    }

    private fun filesUnder(vararg roots: File): Set<String> =
        roots.flatMap { it.walkTopDown().filter { f -> f.isFile }.map { f -> f.absolutePath }.toList() }.toSet()

    @Test
    fun supportedLanguagesIncludeArabicWithTheBundledModel() {
        assertEquals(listOf("ar", "en"), executor.first.supportedLanguages())
    }

    @Test
    fun readsLatinDigitsAndArabicLettersAndPersistsNoImage() {
        val id = share(synthetic())
        // Warm up the model copy first, so it is not counted as a new file below.
        assertTrue(executor.first.recognizeBlocking(id, listOf("ar", "en")).lines.isNotEmpty())
        // ML Kit may keep its own bookkeeping under cache/; images and temp files are what must not appear.
        val roots = arrayOf(context.filesDir, OcrHosts.dir(context), ShareStoreDir.of(context))
        val before = filesUnder(*roots)

        val result = executor.first.recognizeBlocking(id, listOf("ar", "en"))
        val all = result.lines.joinToString("\n") { OcrMerger.normalizeDigits(it.text) }
        assertTrue("amount digits missing", all.contains("1250"))
        assertTrue("reference digits missing", all.contains("98127465"))
        assertTrue("no Arabic letters", result.lines.any { OcrMerger.hasArabicLetter(it.text) })
        result.lines.forEach { l ->
            assertEquals(4, l.box.size)
            assertTrue(l.confidence in 0.0..1.0)
            assertTrue(l.box.all { it in 0.0..1.0 })
        }

        assertEquals("no file may be created or changed by a recognition", before, filesUnder(*roots))
        val cacheImages = context.cacheDir.walkTopDown().filter { it.isFile && it.extension in setOf("png", "jpg", "jpeg", "webp", "bmp", "tmp") }.toList()
        assertTrue("no image or temp file in cache", cacheImages.isEmpty())
        // The host never discards the share; Dart does (FU-067).
        assertTrue(store.list().any { it.id == id })
    }

    @Test
    fun theModelCopyIsTheOnlyFileOcrWrites() {
        executor.first.recognizeBlocking(share(synthetic()), listOf("ar"))
        val files = OcrHosts.dir(context).walkTopDown().filter { it.isFile }.map { it.name }.toList()
        assertEquals(listOf("ara.traineddata"), files)
        assertFalse(files.any { it.endsWith(".tmp") })
    }

    @Test
    fun unknownAndNonImageSharesAreRefusedWithCodes() {
        val e = try {
            executor.first.recognizeBlocking("0".repeat(28), listOf("en"))
            null
        } catch (e: OcrFailure) {
            e
        }
        assertEquals("IO_ERROR", e?.code)

        val w = store.newWriter(ShareKind.TEXT, "text/plain")
        w.write("x".toByteArray(), 0, 1)
        val textId = w.commit().id
        val e2 = try {
            executor.first.recognizeBlocking(textId, listOf("en"))
            null
        } catch (e: OcrFailure) {
            e
        }
        assertEquals("OCR_FAILED", e2?.code)
    }
}
