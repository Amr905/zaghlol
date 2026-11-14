package app.zaghlol.platform.widget

import android.content.Context
import app.zaghlol.platform.spool.KeystoreSpoolCipher
import io.flutter.plugin.common.BinaryMessenger
import java.io.File

/**
 * T-118: the Pigeon `WidgetBridgeHostApi` (platform-channels section 5). Keeps
 * the redacted snapshot (see [WidgetSnapshotStore]) and asks the widgets to
 * redraw. No financial logic, no logging; errors are code-only.
 */
class WidgetBridgeHost(
    private val store: WidgetSnapshotStore,
    private val refresh: () -> Unit,
) : WidgetBridgeHostApi {
    override fun updateSnapshot(snapshot: WidgetSnapshot) {
        try {
            store.write(
                WidgetView(
                    state = snapshot.state.raw,
                    primaryText = snapshot.primaryText,
                    secondaryText = snapshot.secondaryText,
                    currency = snapshot.currency,
                    updatedAtMs = snapshot.updatedAtMs,
                    daysToPayday = snapshot.daysToPayday?.toInt(),
                ),
            )
        } catch (_: Exception) {
            throw WidgetBridgeApiError(IO_ERROR, null, null)
        }
        refresh()
    }

    override fun clear() {
        try {
            store.clear()
        } catch (_: Exception) {
            throw WidgetBridgeApiError(IO_ERROR, null, null)
        }
        refresh()
    }

    companion object {
        const val IO_ERROR = "IO_ERROR"
    }
}

object WidgetStores {
    /** `noBackupFilesDir/widget/`: excluded from every backup path (T-165). */
    fun dir(context: Context): File = File(context.noBackupFilesDir, "widget")

    fun create(context: Context): WidgetSnapshotStore =
        WidgetSnapshotStore(File(dir(context), "snapshot.bin"), KeystoreSpoolCipher())
}

/** Registers the bridge on the UI engine (the app writes; the widget only reads). */
object WidgetBridgeRegistration {
    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        WidgetBridgeHostApi.setUp(
            messenger,
            WidgetBridgeHost(WidgetStores.create(app)) { SafeToSpendWidgetReceiver.refreshAll(app) },
        )
    }

    fun unregister(messenger: BinaryMessenger) {
        WidgetBridgeHostApi.setUp(messenger, null)
    }
}
