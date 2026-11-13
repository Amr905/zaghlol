package app.zaghlol.platform.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Static guarantees of the capture sources and the flavour manifests (T-040
 * design note sections 1 and 9; run from the module directory, as Gradle
 * unit tests are, in every variant).
 */
class CaptureSourceScanTest {
    private val src = File("src")
    private val android = "http://schemas.android.com/apk/res/android"
    private val captureMain = File(src, "main/kotlin/app/zaghlol/platform/capture")
    private val smsGlue = File(src, "sms/kotlin")

    private fun kt(dir: File) = dir.walkTopDown().filter { it.isFile && it.extension == "kt" && !it.name.endsWith(".g.kt") }.toList()

    private val captureSources by lazy { kt(captureMain) + kt(smsGlue) }

    @Test
    fun theScanSeesTheCaptureSources() {
        val names = captureSources.map { it.name }.toSet()
        for (n in listOf("CaptureIntake.kt", "SmsAssembler.kt", "BoundedDispatch.kt", "GuardAdapters.kt", "SmsCapture.kt", "SimSlot.kt", "SmsReceiver.kt", "BankNotificationListener.kt", "NotificationExtractor.kt", "NotificationCapture.kt", "NotificationIntake.kt", "RecentNotifications.kt")) {
            assertTrue(n, n in names)
        }
    }

    @Test
    fun captureCodeNeverLogs() {
        val logging = Regex("\\bLog\\.[a-z]+\\(|\\bprintln\\(|\\bprint\\(|printStackTrace|System\\.(out|err)|\\bTimber\\b|Logger\\(")
        for (f in captureSources) {
            val hit = logging.find(f.readText())
            assertEquals("${f.path}: ${hit?.value}", null, hit)
        }
    }

    @Test
    fun theReceiverOnlyObserves() {
        val forbidden = Regex("abortBroadcast|setResultCode|setResultData|setResultExtras|SEND_SMS|SmsManager|RoleManager|permission\\.READ_PHONE_STATE")
        for (f in captureSources) {
            val hit = forbidden.find(f.readText())
            assertEquals("${f.path}: ${hit?.value}", null, hit)
        }
    }

    /** I-5: a generated `SpoolEntry.toString()` and a record carry the body; never interpolate them. */
    @Test
    fun noSpoolEntryOrRecordIsStringified() {
        val stringify = Regex(
            "\"[^\"]*\\$\\{?(entry|entries|record|rec|spoolEntry|message|msg|m|part|parts|messages|posted|sbn|extras|fields|item)\\b|" +
                "\\b(entry|entries|record|rec|spoolEntry|message|msg|part|parts|messages|posted|sbn|extras|fields|item)\\.toString\\(\\)",
        )
        for (f in captureSources) {
            val text = f.readText()
            val hit = stringify.find(text)
            assertEquals("${f.path}: ${hit?.value}", null, hit)
        }
    }

    /** FU-101 L-1: the only Guard entry point outside platform/guard is the typed `GuardRuntime.decide`. */
    @Test
    fun noCaptureGuardDecideOutsideTheGuardPackage() {
        val direct = Regex("CaptureGuard\\([^)]*\\)\\s*\\.\\s*decide\\(|\\.guard\\s*\\.\\s*decide\\(|decide\\(\\s*\"")
        val dirs = listOf(File(src, "main/kotlin"), File(src, "sms/kotlin"), File(src, "noSms/kotlin"), File(src, "devSms/kotlin"))
        val files = dirs.flatMap { kt(it) }.filterNot { it.path.contains("platform/guard/".replace('/', File.separatorChar)) }
        assertTrue(files.size > 20)
        for (f in files) {
            val hit = direct.find(f.readText())
            assertEquals("${f.path}: ${hit?.value}", null, hit)
        }
    }

    @Test
    fun theReceiverReadsTheInboxAccessors() {
        val text = File(smsGlue, "app/zaghlol/platform/capture/SmsReceiver.kt").readText()
        assertTrue(text.contains("displayOriginatingAddress"))
        assertTrue(text.contains("displayMessageBody"))
        assertTrue(text.contains("goAsync()"))
        assertTrue(text.contains("SmsCapture.dispatch.run("))
    }

    @Test
    fun theReceiverClassLivesOnlyInTheSmsSourceSet() {
        val holders = src.walkTopDown().filter { it.isFile && it.name == "SmsReceiver.kt" }.map { it.relativeTo(src).path }.toList()
        assertEquals(listOf("sms/kotlin/app/zaghlol/platform/capture/SmsReceiver.kt".replace('/', File.separatorChar)), holders)
    }

    @Test
    fun theListenerIsDeclaredOnceInTheMainManifestWithTheBindPermission() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File(src, "main/AndroidManifest.xml"))
        val list = doc.getElementsByTagName("service")
        val services = (0 until list.length).map { list.item(it) as Element }
            .filter { it.getAttributeNS(android, "name").endsWith("BankNotificationListener") }
        assertEquals(1, services.size)
        val s = services[0]
        assertEquals(".platform.capture.BankNotificationListener", s.getAttributeNS(android, "name"))
        assertEquals("android.permission.BIND_NOTIFICATION_LISTENER_SERVICE", s.getAttributeNS(android, "permission"))
        assertEquals("true", s.getAttributeNS(android, "exported"))
        assertEquals("false", s.getAttributeNS(android, "directBootAware"))
        assertEquals("", s.getAttributeNS(android, "label"))
        val actions = s.getElementsByTagName("action")
        assertEquals(1, actions.length)
        assertEquals("android.service.notification.NotificationListenerService", (actions.item(0) as Element).getAttributeNS(android, "name"))
        // The app declares no permission for notification access (the user grants it in settings).
        // The only main-manifest permission is INTERNET (T-141, backend calls).
        val perms = Regex("""<uses-permission[^>]*android:name="([^"]+)"""").findAll(File(src, "main/AndroidManifest.xml").readText()).map { it.groupValues[1] }.toList()
        assertEquals(listOf("android.permission.INTERNET"), perms)
    }

    @Test
    fun theListenerDoesNoIoAndReadsNoExtrasOnTheMainThread() {
        val text = File(captureMain, "BankNotificationListener.kt").readText()
        val posted = text.substringAfter("override fun onNotificationPosted").substringBefore("private class SbnPosted")
        assertTrue(posted.contains("NotificationFilter.accepts("))
        assertFalse(posted.contains("extras"))
        assertFalse(posted.contains("fields()"))
        assertFalse(text.contains("getActiveNotifications"))
        assertFalse(text.contains("requestRebind"))
    }

    private fun receivers(manifest: String): List<Element> {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File(src, manifest))
        val list = doc.getElementsByTagName("receiver")
        return (0 until list.length).map { list.item(it) as Element }
    }

    @Test
    fun theSmsManifestDeclaresTheProtectedReceiverWithoutPriority() {
        val rs = receivers("sms/AndroidManifest.xml")
        assertEquals(1, rs.size)
        val r = rs[0]
        assertEquals("app.zaghlol.platform.capture.SmsReceiver", r.getAttributeNS(android, "name"))
        assertEquals("android.permission.BROADCAST_SMS", r.getAttributeNS(android, "permission"))
        assertEquals("true", r.getAttributeNS(android, "exported"))
        assertEquals("false", r.getAttributeNS(android, "directBootAware"))
        val filters = r.getElementsByTagName("intent-filter")
        assertEquals(1, filters.length)
        assertEquals("", (filters.item(0) as Element).getAttributeNS(android, "priority"))
        val actions = r.getElementsByTagName("action")
        assertEquals(1, actions.length)
        assertEquals("android.provider.Telephony.SMS_RECEIVED", (actions.item(0) as Element).getAttributeNS(android, "name"))
        // No new permission: the Sms manifest still declares exactly READ_SMS and RECEIVE_SMS.
        val text = File(src, "sms/AndroidManifest.xml").readText()
        val perms = Regex("uses-permission[^>]*android:name=\"([^\"]+)\"").findAll(text).map { it.groupValues[1] }.toList()
        assertEquals(listOf("android.permission.READ_SMS", "android.permission.RECEIVE_SMS"), perms)
    }

    @Test
    fun noSmsRemovesTheReceiverAndOtherManifestsHaveNone() {
        val removed = receivers("noSms/AndroidManifest.xml")
        assertEquals(1, removed.size)
        assertEquals("app.zaghlol.platform.capture.SmsReceiver", removed[0].getAttributeNS(android, "name"))
        assertEquals("remove", removed[0].getAttributeNS("http://schemas.android.com/tools", "node"))
        for (m in listOf("main/AndroidManifest.xml", "devSms/AndroidManifest.xml", "debug/AndroidManifest.xml", "profile/AndroidManifest.xml")) {
            if (!File(src, m).exists()) continue
            assertFalse(m, File(src, m).readText().contains("SMS_RECEIVED"))
        }
    }
}
