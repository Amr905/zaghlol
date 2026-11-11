package app.zaghlol.platform.ingest

import android.content.Context
import android.os.Handler
import app.zaghlol.platform.capture.AndroidCaptureHost
import app.zaghlol.platform.capture.AndroidCaptureHostApi
import app.zaghlol.platform.keys.SecretStoreRegistration
import com.github.dart_lang.jni.JniPlugin
import com.github.dart_lang.jni_flutter.JniFlutterPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger

/**
 * Starts the headless ingestion engine (T-041 design note section 5): one
 * process-wide [FlutterEngineGroup], entrypoint `ingestionMain`,
 * `automaticallyRegisterPlugins = false` and this allowlist only:
 * - `JniPlugin` + `JniFlutterPlugin`: path_provider_android 2.3 is JNI-based,
 *   so both engines resolve the same database directory (FU-065 S-7);
 * - `SecretStoreRegistration`: the database key (platform-channels.md 5);
 * - an [AndroidCaptureHost] from [newHost] (headless: no inbox reader, no
 *   Guard writer, FU-088);
 * - the ingestion Pigeon APIs (`HeadlessIngestionApi`, `HeadlessIngestionHostApi`).
 * [ALLOWED_PLUGINS] lists the plugin classes (checked by the instrumented test).
 */
class FlutterHeadlessStarter(
    private val app: Context,
    private val main: Handler,
    private val newHost: () -> AndroidCaptureHost,
    private val trace: () -> IngestTrace,
) : HeadlessStarter {
    private var group: FlutterEngineGroup? = null

    override fun start(onReady: (Boolean) -> Unit): HeadlessHandle {
        val handle = Handle(onReady)
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) loader.startInitialization(app)
            loader.ensureInitializationCompleteAsync(app, null, main) {
                if (handle.destroyed) return@ensureInitializationCompleteAsync
                try {
                    handle.create(loader.findAppBundlePath())
                } catch (_: Exception) {
                    onReady(false)
                }
            }
        } catch (_: Exception) {
            main.post { onReady(false) }
        }
        return handle
    }

    /** Main thread only. */
    private inner class Handle(private val onReady: (Boolean) -> Unit) : HeadlessHandle {
        var destroyed = false
            private set
        private var engine: FlutterEngine? = null
        private var host: AndroidCaptureHost? = null
        private var api: HeadlessIngestionApi? = null
        private var messenger: BinaryMessenger? = null

        fun create(bundlePath: String) {
            val g = group ?: FlutterEngineGroup(app).also { group = it }
            val e = g.createAndRunEngine(
                FlutterEngineGroup.Options(app)
                    .setDartEntrypoint(DartExecutor.DartEntrypoint(bundlePath, HeadlessEngine.ENTRYPOINT))
                    .setAutomaticallyRegisterPlugins(false),
            )
            engine = e
            val m = e.dartExecutor.binaryMessenger
            messenger = m
            // Handlers are installed on the main thread before any Dart message is processed.
            e.plugins.add(JniPlugin())
            e.plugins.add(JniFlutterPlugin())
            SecretStoreRegistration.register(m, app)
            val h = newHost()
            host = h
            AndroidCaptureHostApi.setUp(m, h)
            api = HeadlessIngestionApi(m)
            HeadlessIngestionHostApi.setUp(
                m,
                object : HeadlessIngestionHostApi {
                    override fun ready() = onReady(true)
                },
            )
            trace().safely { engineAttached(m) }
        }

        override fun drain(onReply: (CycleReport) -> Unit) {
            val a = api
            if (a == null) {
                onReply(CycleReport(CycleOutcome.RETRY))
                return
            }
            a.drain { result -> onReply(CycleReport.of(result.getOrNull())) }
        }

        override fun close(onReply: () -> Unit) {
            val a = api
            if (a == null) {
                onReply() // Dart never started: nothing is open
                return
            }
            a.close { onReply() }
        }

        override fun destroy() {
            if (destroyed) return
            destroyed = true
            host?.detach() // the claim goes first (entries stay for the next drain)
            host = null
            api = null
            messenger?.let { m -> trace().safely { engineDetached(m) } }
            messenger = null
            val e = engine
            engine = null
            e?.destroy()
        }
    }

    companion object {
        /** The only plugin classes a headless engine registers (besides the Pigeon hosts above). */
        val ALLOWED_PLUGINS: List<Class<*>> = listOf(JniPlugin::class.java, JniFlutterPlugin::class.java)
    }
}
