package app.zaghlol.spike.sms

import android.content.Context
import androidx.startup.Initializer
import app.zaghlol.platform.capture.AndroidCaptureHostApi
import app.zaghlol.platform.capture.CaptureEventsApi
import app.zaghlol.platform.capture.EngineHook
import app.zaghlol.platform.capture.EngineHooks
import io.flutter.embedding.engine.FlutterEngine

/**
 * UI-engine side of the spike: the same spool host as the headless engine
 * (drain/ack under the process-wide claim), the event API for
 * `onSpoolChanged`, and the metrics channel. Attaching shuts a lingering
 * headless engine down (review F1): never mid-drain; its pending drain is
 * answered first (bounded), Dart closes the database, then it is destroyed.
 * Until then the claim keeps the UI engine from draining the same entries.
 */
object SpikeEngineHook : EngineHook {
    private var host: SpoolHost? = null

    override fun attach(engine: FlutterEngine, context: Context) {
        val rt = SpikeRuntime.get(context)
        rt.headless.shutdown()
        val messenger = engine.dartExecutor.binaryMessenger
        val h = SpoolHost(rt.engineIds.getAndIncrement(), rt.store, rt.claim, rt.scheduler, rt.device, rt.metrics) {
            rt.uiCycle ?: SpikeMetrics.Cycle(SpikeMetrics.Path.FOREGROUND)
        }
        host = h
        AndroidCaptureHostApi.setUp(messenger, h)
        HeadlessEngine.metricsChannel(messenger, rt.metrics, { rt.uiCycle }) { }
        rt.uiMessenger = messenger
        rt.uiEvents = CaptureEventsApi(messenger)
    }

    override fun detach(engine: FlutterEngine) {
        val rt = SpikeRuntime.peek() ?: return
        rt.uiEvents = null
        rt.uiMessenger = null
        rt.uiCycle = null
        host?.detach()
        host = null
        AndroidCaptureHostApi.setUp(engine.dartExecutor.binaryMessenger, null)
    }
}

/** androidx.startup entry (declared in src/devSms/AndroidManifest.xml only). */
class SpikeInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        EngineHooks.register(SpikeEngineHook)
    }

    override fun dependencies(): List<Class<out Initializer<*>>> = emptyList()
}
