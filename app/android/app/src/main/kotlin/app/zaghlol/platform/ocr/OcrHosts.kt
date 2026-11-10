package app.zaghlol.platform.ocr

import android.content.Context
import android.os.Handler
import android.os.Looper
import app.zaghlol.platform.share.ShareStore
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

object OcrHosts {
    /** `noBackupFilesDir/ocr/`: holds only the public model copy (T-165: excluded from every backup path). */
    fun dir(context: Context): File = File(context.noBackupFilesDir, "ocr")

    /** Returns the host and its executor, so the caller can shut it down with the engine. */
    fun create(context: Context, store: ShareStore): Pair<OcrHost, ExecutorService> {
        val installer = TessdataInstaller(dir(context), { context.assets.open(TessdataSpec.ASSET_PATH) })
        // One worker: recognitions are serialised (memory, one Tesseract at a time).
        // 8 MiB stack: Tesseract's layout analysis recurses.
        val executor = Executors.newSingleThreadExecutor { r ->
            Thread(null, r, "zaghlol-ocr", 8L * 1024 * 1024).apply { isDaemon = true }
        }
        val main = Handler(Looper.getMainLooper())
        val host = OcrHost(
            images = ShareStoreImageSource(store),
            decoder = BitmapOcrDecoder,
            latin = MlKitLatinEngine(),
            arabic = TesseractArabicEngine(context.assets, installer),
            executor = executor,
            post = { main.post(it) },
        )
        return host to executor
    }
}
