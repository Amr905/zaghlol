package app.zaghlol.platform.capture

import app.zaghlol.platform.ingest.FakeMain
import app.zaghlol.platform.ingest.FakeStarter
import app.zaghlol.platform.ingest.IngestWorkQueue
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** T-044: SMS permission request, notification-access link and permission-change events (JVM). */
class PermissionFlowsTest {
    private class Dev(var caps: CaptureCapabilities) : CaptureDevice {
        override fun capabilities() = caps
        override fun isIgnoringBatteryOptimizations() = false
        override fun openBatteryOptimizationSettings() = Unit
    }

    private fun caps(sms: Boolean = false, flavor: Boolean = true, notif: Boolean = false) =
        CaptureCapabilities(sms, flavor, notif, true, 34)

    private class Launches {
        val calls = ArrayList<List<String>>()
        var fail = false
        fun launch(p: Array<String>, code: Int) {
            if (fail) throw IllegalStateException("ZG_CANARY_7731")
            assertEquals(ActivityPermissions.REQUEST_CODE, code)
            calls += p.toList()
        }
    }

    private fun perms(dev: Dev, l: Launches, settings: IntArray = IntArray(1), after: () -> Unit = {}) =
        ActivityPermissions(dev, l::launch, { settings[0]++ }, after)

    private fun request(p: ActivityPermissions): () -> Result<Boolean>? {
        var r: Result<Boolean>? = null
        p.requestSms { r = it }
        return { r }
    }

    private fun code(r: Result<Boolean>?) = (r!!.exceptionOrNull() as CaptureApiError).code

    private val both = ActivityPermissions.SMS_PERMISSIONS

    @Test
    fun noSmsBuildNeverRequestsSms() {
        val l = Launches()
        val r = request(perms(Dev(caps(flavor = false)), l))
        assertEquals("NOT_AVAILABLE", code(r()))
        assertTrue(l.calls.isEmpty())
    }

    @Test
    fun alreadyGrantedAnswersTrueWithoutAPrompt() {
        val l = Launches()
        assertEquals(true, request(perms(Dev(caps(sms = true)), l))()!!.getOrNull())
        assertTrue(l.calls.isEmpty())
    }

    @Test
    fun oneSystemPromptForBothPermissionsAndEveryCallerGetsTheAnswer() {
        val l = Launches()
        var changed = 0
        val p = perms(Dev(caps()), l, after = { changed++ })
        val a = request(p)
        val b = request(p)
        assertEquals(listOf(both.toList()), l.calls)
        assertNull(a())
        assertTrue(p.onResult(ActivityPermissions.REQUEST_CODE, both, intArrayOf(0, 0)))
        assertEquals(true, a()!!.getOrNull())
        assertEquals(true, b()!!.getOrNull())
        assertEquals(1, changed)
    }

    @Test
    fun grantedOnlyWhenBothPermissionsAreGranted() {
        for (results in listOf(intArrayOf(0, -1), intArrayOf(-1, 0), intArrayOf(-1, -1), IntArray(0))) {
            val p = perms(Dev(caps()), Launches())
            val r = request(p)
            p.onResult(ActivityPermissions.REQUEST_CODE, if (results.isEmpty()) emptyArray() else both, results)
            assertEquals(false, r()!!.getOrNull())
        }
    }

    @Test
    fun anotherRequestCodeIsNotOurs() {
        val p = perms(Dev(caps()), Launches())
        val r = request(p)
        assertFalse(p.onResult(1, both, intArrayOf(0, 0)))
        assertNull(r())
    }

    @Test
    fun aFailedLaunchIsACodeOnlyIoErrorAndAllowsANewRequest() {
        val l = Launches().apply { fail = true }
        val p = perms(Dev(caps()), l)
        val r = request(p)
        assertEquals("IO_ERROR", code(r()))
        assertNull(r()!!.exceptionOrNull()!!.message)
        l.fail = false
        request(p)
        assertEquals(1, l.calls.size)
    }

    private val status = statusIn(tempDir())
    private val store = storeIn(tempDir(), status = status)
    private val claim = SpoolClaim(clock = { 0 })

    // ---- the host --------------------------------------------------------

    private fun host(ui: UiPermissions?) = AndroidCaptureHost(
        1, store, claim, status, null, null, null, null, ui = ui,
    )

    @Test
    fun theHostPassesTheRequestAndTheSettingsLinkToTheUiPermissions() {
        val settings = IntArray(1)
        val p = perms(Dev(caps(sms = true)), Launches(), settings)
        var r: Result<Boolean>? = null
        host(p).requestSmsPermission { r = it }
        assertEquals(true, r!!.getOrNull())
        host(p).openNotificationAccessSettings()
        assertEquals(1, settings[0])
    }

    @Test
    fun withoutAnActivityTheHostAnswersNotAvailableAndErrorsAreCodeOnly() {
        var r: Result<Boolean>? = null
        host(null).requestSmsPermission { r = it }
        assertEquals("NOT_AVAILABLE", code(r))
        try {
            host(null).openNotificationAccessSettings()
            fail()
        } catch (e: CaptureApiError) {
            assertEquals("NOT_AVAILABLE", e.code)
        }
        val boom = object : UiPermissions {
            override fun requestSms(callback: (Result<Boolean>) -> Unit) = throw IllegalStateException("ZG_CANARY_7731")
            override fun openNotificationAccessSettings() = throw IllegalStateException("ZG_CANARY_7731")
            override fun detach() = Unit
        }
        host(boom).requestSmsPermission { r = it }
        assertEquals("IO_ERROR", code(r))
        try {
            host(boom).openNotificationAccessSettings()
            fail()
        } catch (e: CaptureApiError) {
            assertEquals("IO_ERROR", e.code)
            assertNull(e.message)
        }
    }

    // ---- permission-change events (EC-13) ---------------------------------

    private class Names : BinaryMessenger {
        val sent = ArrayList<Pair<String, ByteBuffer?>>()
        override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            sent += channel to message
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?, taskQueue: BinaryMessenger.TaskQueue?) = Unit
        override fun makeBackgroundTaskQueue(options: BinaryMessenger.TaskQueueOptions): BinaryMessenger.TaskQueue =
            object : BinaryMessenger.TaskQueue {}

        fun permissionEvents(): List<CaptureCapabilities> = sent
            .filter { it.first.endsWith("CaptureEventsApi.onPermissionChanged") }
            .map {
                val m = it.second!!.also { b -> b.rewind() }
                (CaptureEventsApi.codec.decodeMessage(m) as List<*>)[0] as CaptureCapabilities
            }
    }

    private val main = FakeMain()
    private val dir = tempDir()

    @After
    fun stop() = main.shutdown()

    private fun runtime(dev: Dev) = CaptureRuntime.create(
        CaptureSeams(
            noBackupDir = dir, appVersion = { 1 }, main = main, queue = object : IngestWorkQueue {
                override fun enqueue() = Unit
                override fun enqueueRetry(attempt: Int, fromRetryRun: Boolean) = Unit
                override fun cancelRetry() = Unit
            },
            device = dev, guard = { throw IllegalStateException("not in JVM tests") },
            headlessStarter = { FakeStarter(main) }, cipher = SoftwareSpoolCipher(), keyCreatedAtMs = { null },
        ),
    )

    @Test
    fun revokingSmsTellsDartOnceAndAnUnchangedStateTellsNothing() {
        val dev = Dev(caps(sms = true, notif = true))
        val rt = runtime(dev)
        val m = Names()
        main.onMain { rt.attachUi(Any(), m) }
        rt.checkPermissions() // the baseline: no event
        assertTrue(m.permissionEvents().isEmpty())
        dev.caps = caps(sms = false, notif = true) // revoked in system settings
        rt.checkPermissions()
        rt.checkPermissions() // still the same: once only
        val events = m.permissionEvents()
        assertEquals(1, events.size)
        assertFalse(events[0].smsGranted)
        assertTrue(events[0].notificationAccess)
        dev.caps = caps(sms = false, notif = false) // notification access switched off
        rt.checkPermissions()
        assertEquals(2, m.permissionEvents().size)
    }

    @Test
    fun noUiEngineNoPermissionEventAndTheHeadlessHostHasNoSettingsLink() {
        val dev = Dev(caps(sms = true))
        val rt = runtime(dev)
        rt.checkPermissions()
        val perms = perms(dev, Launches())
        main.onMain { rt.attachUi(Any(), Names(), perms) }
        try {
            rt.newHost(headless = true).openNotificationAccessSettings()
            fail()
        } catch (e: CaptureApiError) {
            assertEquals("NOT_AVAILABLE", e.code)
        }
        rt.newHost(headless = false).openNotificationAccessSettings() // wired for the UI host only
    }
}
