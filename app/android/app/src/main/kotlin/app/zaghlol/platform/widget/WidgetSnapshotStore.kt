package app.zaghlol.platform.widget

import app.zaghlol.platform.spool.SpoolCipher
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * What the widget shows (T-118). Already-formatted, redaction-aware strings
 * from Dart: when amounts are hidden, or the app is locked, the amount is
 * not in here at all, only the mask. Nothing is parsed or computed natively.
 */
data class WidgetView(
    val state: Int,
    val primaryText: String,
    val secondaryText: String,
    val currency: String,
    val updatedAtMs: Long,
    val daysToPayday: Int?,
) {
    companion object {
        const val STATE_OK = 0
        const val STATE_NO_BUDGET = 1
        const val STATE_NO_DATA = 2
        const val MAX_TEXT_CHARS = 120
    }
}

/**
 * `noBackupFilesDir/widget/snapshot.bin` (never backed up, T-165): AES-GCM
 * with the spool key (Android Keystore), AAD `zaghlol.widget.v1|snapshot`,
 * a small binary record v1. The app writes it, the widget (same process
 * and UID) reads it; the file is replaced atomically so a reader never sees
 * half a snapshot.
 *
 * A file that can't be read (lost key, tampering, corruption, I/O) reads as
 * `null`, which the widget shows as "Open Zaghlol"; it is never deleted on a
 * read and nothing is logged.
 */
class WidgetSnapshotStore(
    private val file: File,
    private val cipher: SpoolCipher,
) {
    @Synchronized
    fun write(view: WidgetView) {
        val dir = file.parentFile ?: throw IOException("WIDGET_DIR")
        if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) throw IOException("WIDGET_DIR")
        val sealed = cipher.encrypt(encode(view), AAD)
        val tmp = File(dir, file.name + ".tmp")
        try {
            tmp.outputStream().use { out ->
                out.write(sealed)
                out.fd.sync()
            }
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (e: Exception) {
            tmp.delete()
            throw e
        }
    }

    /** The stored view, or `null` when absent or unreadable for any reason. */
    @Synchronized
    fun readOrNull(): WidgetView? =
        try {
            if (!file.isFile || file.length() > MAX_FILE_BYTES) {
                null
            } else {
                decode(cipher.decrypt(file.readBytes(), AAD))
            }
        } catch (_: Exception) {
            null
        }

    /** Idempotent. */
    @Synchronized
    fun clear() {
        File(file.parentFile, file.name + ".tmp").delete()
        if (file.exists() && !file.delete()) throw IOException("WIDGET_CLEAR")
    }

    companion object {
        const val VERSION = 1
        const val MAX_FILE_BYTES = 4096L
        val AAD: ByteArray get() = "zaghlol.widget.v1|snapshot".toByteArray(Charsets.UTF_8)

        internal fun encode(v: WidgetView): ByteArray {
            val bos = ByteArrayOutputStream()
            DataOutputStream(bos).use { out ->
                out.writeByte(VERSION)
                out.writeByte(v.state)
                out.writeUTF(v.primaryText.take(WidgetView.MAX_TEXT_CHARS))
                out.writeUTF(v.secondaryText.take(WidgetView.MAX_TEXT_CHARS))
                out.writeUTF(v.currency.take(8))
                out.writeLong(v.updatedAtMs)
                out.writeInt(v.daysToPayday ?: -1)
            }
            return bos.toByteArray()
        }

        internal fun decode(b: ByteArray): WidgetView {
            DataInputStream(ByteArrayInputStream(b)).use { input ->
                if (input.readUnsignedByte() != VERSION) throw IOException("WIDGET_FORMAT")
                val state = input.readUnsignedByte()
                if (state > WidgetView.STATE_NO_DATA) throw IOException("WIDGET_FORMAT")
                val primary = input.readUTF()
                val secondary = input.readUTF()
                val currency = input.readUTF()
                val updated = input.readLong()
                val days = input.readInt()
                return WidgetView(state, primary, secondary, currency, updated, if (days < 0) null else days)
            }
        }
    }
}
