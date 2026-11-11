package app.zaghlol.platform.ingest

import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.zaghlol.platform.capture.AndroidCaptureHost
import app.zaghlol.platform.capture.CaptureRuntime
import app.zaghlol.platform.spool.SpoolClaim
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T-041 design note section 5 on a device or emulator (sms-spike workflow,
 * devSms debug): the real headless engine starts at `ingestionMain`, its Dart
 * side calls `ready()` over the Pigeon HeadlessIngestionHostApi, and the
 * engine has exactly the allowlisted plugins: every plugin the app's
 * GeneratedPluginRegistrant would add, other than JNI, is absent. No spool
 * entry is touched (the engine is closed without a drain).
 */
@RunWith(AndroidJUnit4::class)
class HeadlessPluginAllowlistTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val app = instrumentation.targetContext.applicationContext

    /** Plugins GeneratedPluginRegistrant registers on the UI engine (debug build); missing classes are skipped. */
    private val registrantPlugins = listOf(
        "dev.dint.cryptography_flutter.CryptographyFlutterPlugin",
        "dev.flutter.plugins.integration_test.IntegrationTestPlugin",
    )

    @Test
    fun headlessEngineStartsAtIngestionMainWithOnlyTheAllowlistedPlugins() {
        val rt = CaptureRuntime.get(app)
        val starter = FlutterHeadlessStarter(
            app,
            Handler(Looper.getMainLooper()),
            newHost = { AndroidCaptureHost(9_001, rt.store, SpoolClaim(), rt.status, null, null, null, null) },
            trace = { IngestTrace.NONE },
        )
        val ready = CountDownLatch(1)
        var ok = false
        lateinit var handle: HeadlessHandle
        instrumentation.runOnMainSync {
            handle = starter.start { r ->
                ok = r
                ready.countDown()
            }
        }
        assertTrue("ingestionMain did not call ready() within 60 s", ready.await(60, TimeUnit.SECONDS))
        assertTrue("the headless engine could not start", ok)

        @Suppress("UNCHECKED_CAST")
        val others = registrantPlugins.mapNotNull {
            try {
                Class.forName(it) as Class<out FlutterPlugin>
            } catch (_: ClassNotFoundException) {
                null
            }
        }
        assertTrue("no non-allowlisted plugin class found to check against", others.isNotEmpty())
        var registeredAllowed = emptyList<Class<out FlutterPlugin>>()
        var registeredOthers = emptyList<Class<out FlutterPlugin>>()
        instrumentation.runOnMainSync {
            registeredAllowed = starter.registeredAmong(handle, FlutterHeadlessStarter.ALLOWED_PLUGINS)
            registeredOthers = starter.registeredAmong(handle, others)
        }
        assertEquals(FlutterHeadlessStarter.ALLOWED_PLUGINS, registeredAllowed)
        assertEquals(emptyList<Class<*>>(), registeredOthers)

        // Close (Dart answers, nothing was open), then destroy.
        val closed = CountDownLatch(1)
        instrumentation.runOnMainSync { handle.close { closed.countDown() } }
        assertTrue("close was not answered within 10 s", closed.await(10, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { handle.destroy() }
    }
}
