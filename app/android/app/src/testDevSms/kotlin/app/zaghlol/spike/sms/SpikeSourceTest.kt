package app.zaghlol.spike.sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Static guarantees of the spike sources and manifests (run from the module
 * directory, as Gradle unit tests are).
 */
class SpikeSourceTest {
    private val src = File("src")
    private val spikeDir = File(src, "devSms/kotlin/app/zaghlol/spike")
    private val android = "http://schemas.android.com/apk/res/android"

    private fun sources() = spikeDir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    @Test
    fun receiverIsProtectedByBroadcastSmsAndHasNoPriority() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File(src, "devSms/AndroidManifest.xml"))
        val receivers = doc.getElementsByTagName("receiver")
        assertEquals(1, receivers.length)
        val r = receivers.item(0) as Element
        assertEquals("app.zaghlol.spike.sms.SpikeSmsReceiver", r.getAttributeNS(android, "name"))
        assertEquals("android.permission.BROADCAST_SMS", r.getAttributeNS(android, "permission"))
        assertEquals("true", r.getAttributeNS(android, "exported"))
        assertEquals("false", r.getAttributeNS(android, "directBootAware"))
        val filters = r.getElementsByTagName("intent-filter")
        assertEquals(1, filters.length)
        assertEquals("", (filters.item(0) as Element).getAttributeNS(android, "priority"))
        val action = r.getElementsByTagName("action").item(0) as Element
        assertEquals("android.provider.Telephony.SMS_RECEIVED", action.getAttributeNS(android, "name"))
    }

    @Test
    fun spikeSourcesNeverAbortLogContentOrMakeKeys() {
        val files = sources()
        assertTrue(files.size >= 10)
        for (f in files) {
            val text = f.readText()
            assertFalse("${f.name}: abortBroadcast", text.contains("abortBroadcast"))
            assertFalse("${f.name}: KeyGenerator", text.contains("KeyGenerator"))
            assertFalse("${f.name}: println", Regex("\\bprintln\\(|printStackTrace|System\\.(out|err)").containsMatchIn(text))
            if (f.name != "SpikeLog.kt") {
                assertFalse("${f.name}: Log call", Regex("\\bLog\\.[a-z]+\\(").containsMatchIn(text))
            }
        }
    }

    @Test
    fun notificationStringsExistInEnglishAndArabic() {
        for (dir in listOf("values", "values-ar")) {
            val text = File(src, "devSms/res/$dir/spike_strings.xml").readText()
            assertTrue(dir, text.contains("name=\"native_android_captureChannelName\""))
            assertTrue(dir, text.contains("name=\"native_android_captureNotifTitle\""))
        }
        val tester = Regex("name=\"spike_tester_sender\"[^>]*>([^<]*)<").find(File(src, "devSms/res/values/spike_strings.xml").readText())
        assertEquals("", tester!!.groupValues[1]) // never commit a real number
    }

    @Test
    fun flavourManifests() {
        val sms = File(src, "sms/AndroidManifest.xml").readText()
        assertTrue(sms.contains("android:name=\"android.hardware.telephony\" android:required=\"false\""))
        val noSms = File(src, "noSms/AndroidManifest.xml").readText()
        for (p in listOf("READ_SMS", "RECEIVE_SMS", "SEND_SMS", "RECEIVE_MMS", "RECEIVE_WAP_PUSH", "READ_CELL_BROADCASTS")) {
            for (tag in listOf("uses-permission", "uses-permission-sdk-23")) {
                assertTrue("$tag $p", noSms.contains("<$tag android:name=\"android.permission.$p\" tools:node=\"remove\" />"))
            }
        }
        // Spike code lives only in the dev x sms source set.
        for (other in listOf("main", "sms", "dev", "staging", "prod", "stagingSms", "prodSms")) {
            assertFalse(other, File(src, "$other/kotlin/app/zaghlol/spike").exists())
        }
    }
}
