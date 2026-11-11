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
 * directory, as Gradle unit tests are). T-040: the spike has no receiver and
 * no Guard of its own any more; the production `SmsReceiver` (src/sms) is
 * the only SMS_RECEIVED receiver of devSms.
 */
class SpikeSourceTest {
    private val src = File("src")
    private val spikeDir = File(src, "devSms/kotlin/app/zaghlol/spike")

    private fun sources() = spikeDir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    @Test
    fun devSmsManifestDeclaresNoReceiver() {
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            .newDocumentBuilder().parse(File(src, "devSms/AndroidManifest.xml"))
        assertEquals(0, doc.getElementsByTagName("receiver").length)
        val meta = doc.getElementsByTagName("meta-data").item(0) as Element
        assertEquals("app.zaghlol.spike.sms.SpikeInitializer", meta.getAttributeNS("http://schemas.android.com/apk/res/android", "name"))
    }

    @Test
    fun spikeSourcesNeverAbortLogContentOrMakeKeys() {
        val files = sources()
        // T-040 keeps only the metrics, the log and the initializer (latency recorder).
        assertEquals(setOf("SpikeInitializer.kt", "SpikeLog.kt", "SpikeMetrics.kt"), files.map { it.name }.toSet())
        for (f in files) {
            val text = f.readText()
            assertFalse("${f.name}: abortBroadcast", text.contains("abortBroadcast"))
            assertFalse("${f.name}: KeyGenerator", text.contains("KeyGenerator"))
            assertFalse("${f.name}: println", Regex("\\bprintln\\(|printStackTrace|System\\.(out|err)").containsMatchIn(text))
            assertFalse("${f.name}: a receiver", text.contains("BroadcastReceiver"))
            if (f.name != "SpikeLog.kt") {
                assertFalse("${f.name}: Log call", Regex("\\bLog\\.[a-z]+\\(").containsMatchIn(text))
            }
        }
    }

    @Test
    fun spikeGuardAndTesterSenderAreGone() {
        assertFalse(File(spikeDir, "sms/SpikeGuard.kt").exists())
        assertFalse(File(spikeDir, "sms/SpikeSmsReceiver.kt").exists())
        assertFalse(File(src, "devSms/res/values/spike_strings.xml").exists())
        assertTrue(File(src, "devSms/assets/guard/spike_guard_base.json").isFile)
    }

    @Test
    fun spikeCodeLivesOnlyInTheDevSmsSourceSet() {
        for (other in listOf("main", "sms", "noSms", "dev", "staging", "prod", "stagingSms", "prodSms")) {
            assertFalse(other, File(src, "$other/kotlin/app/zaghlol/spike").exists())
            assertFalse("$other has the spike Guard base", File(src, "$other/assets/guard/spike_guard_base.json").exists())
        }
    }
}
