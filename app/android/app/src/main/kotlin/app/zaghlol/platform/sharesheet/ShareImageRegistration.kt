package app.zaghlol.platform.sharesheet

import android.app.Activity
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * T-117 (S-73): `MethodChannel('zaghlol/share')` `shareImage({path})`.
 *
 * The user-initiated share of one PNG through the system chooser. Dart stages
 * the image in the cache directory and deletes it as soon as this call
 * returns, but the receiving app reads it later, so the file is copied into
 * `cache/shared_images/` (the only folder the FileProvider exposes) and that
 * folder is emptied of older copies on every call and when the activity goes.
 * No permission is requested. The path argument is never logged.
 */
object ShareImageRegistration {
    const val CHANNEL = "zaghlol/share"
    private const val DIR = "shared_images"
    private const val MAX_AGE_MS = 60L * 60L * 1000L

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            handle(activity, call, result)
        }
    }

    fun unregister(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(null)
    }

    private fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "shareImage") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("bad-args", "path is required", null)
            return
        }
        try {
            val cache = activity.cacheDir.canonicalFile
            val source = File(path).canonicalFile
            // Only a file the app staged in its own cache directory.
            if (!source.path.startsWith(cache.path + File.separator) || !source.isFile) {
                result.error("bad-path", "not a staged file", null)
                return
            }
            val dir = File(cache, DIR).apply { mkdirs() }
            sweep(dir, MAX_AGE_MS)
            val copy = File(dir, "share_${System.currentTimeMillis()}.png")
            source.copyTo(copy, overwrite = true)
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.share", copy)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(send, null))
            result.success(null)
        } catch (e: Exception) {
            // The exception text can carry the path: report the class only.
            result.error("share-failed", e.javaClass.simpleName, null)
        }
    }

    /** Deletes copies older than [maxAgeMs] (0 deletes all). */
    fun sweep(dir: File, maxAgeMs: Long) {
        val now = System.currentTimeMillis()
        dir.listFiles()?.forEach {
            if (now - it.lastModified() >= maxAgeMs) it.delete()
        }
    }

    fun sweepAll(activity: Activity) {
        // Not while a chooser may still be open: only on engine teardown of a
        // finishing activity.
        if (activity.isFinishing) sweep(File(activity.cacheDir, DIR), 0L)
    }
}
