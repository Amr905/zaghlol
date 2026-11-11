package app.zaghlol.platform.capture

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Flavour-specific wiring of the UI engine (T-008). `MainActivity` (shared by
 * every flavour) calls [attach]/[detach]; a flavour source set registers a
 * hook at process start (devSms: the SMS spike, through an androidx.startup
 * initializer declared only in `src/devSms/AndroidManifest.xml`). In every
 * other build the list is empty and this does nothing.
 */
interface EngineHook {
    fun attach(engine: FlutterEngine, context: Context)

    fun detach(engine: FlutterEngine)
}

object EngineHooks {
    private val hooks = CopyOnWriteArrayList<EngineHook>()

    fun register(hook: EngineHook) {
        hooks.addIfAbsent(hook)
    }

    fun attach(engine: FlutterEngine, context: Context) = hooks.forEach { it.attach(engine, context) }

    fun detach(engine: FlutterEngine) = hooks.forEach { it.detach(engine) }
}
