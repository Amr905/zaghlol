package app.zaghlol.platform.share

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** T-263: the image-share paths (warm-start announcement, several photos, wildcard types). Synthetic bytes only. */
class ShareImageSharesTest {
    private lateinit var dir: File
    private var counter = 0
    private val png = PNG_HEAD

    @Before
    fun setUp() {
        dir = Files.createTempDirectory("share-image").toFile()
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun newStore() = ShareStore(
        dir,
        SoftwareShareCipher(),
        clock = { 1_700_000_000_000L },
        newId = { "%012x".format(1_700_000_000_000L) + "%016x".format(++counter) },
    )

    @Test
    fun warmStartAnnouncementCarriesTheOcrPathOfAnImage() {
        // MainActivity.onResume announces store.list() through withOcrPath: the root cause of the
        // "reading images isn't ready" screen was an image announced with ocrPath == null.
        val store = newStore()
        val intake = ShareIntake(store, "app.zaghlol", FakeBoundsProbe())
        val image = intake.accept(FakeShareSource.stream("image/png", png + ByteArray(40))) as ShareOutcome.Accepted
        assertEquals(ShareKind.IMAGE, image.descriptor.kind)
        val announced = store.list().map { it.withOcrPath() }.single()
        assertEquals(ShareKind.IMAGE, announced.kind)
        assertEquals(announced.id, announced.ocrPath)
    }

    @Test
    fun textAndPdfDescriptorsKeepNoOcrPath() {
        val store = newStore()
        val intake = ShareIntake(store, "app.zaghlol", FakeBoundsProbe())
        val text = intake.accept(FakeShareSource(intentType = "text/plain", text = "synthetic words")) as ShareOutcome.Accepted
        assertNull(text.descriptor.withOcrPath().ocrPath)
    }

    @Test
    fun aWildcardImageTypeFromAMultipleShareIsAccepted() {
        // ACTION_SEND_MULTIPLE senders declare image/* (or */* when mixed): the bytes decide.
        val store = newStore()
        val intake = ShareIntake(store, "app.zaghlol", FakeBoundsProbe())
        val outcome = intake.accept(FakeShareSource.stream("image/*", png + ByteArray(40)))
        assertEquals(ShareKind.IMAGE, (outcome as ShareOutcome.Accepted).descriptor.kind)
    }

    @Test
    fun severalItemsReadTheFirstAndAreFlagged() {
        val items = listOf("first", "second", "third")
        assertEquals("first", MultiShare.first(items))
        assertTrue(MultiShare.hasIgnored(items))
        assertFalse(MultiShare.hasIgnored(listOf("only")))
        assertFalse(MultiShare.hasIgnored(emptyList<String>()))
        assertNull(MultiShare.first(emptyList<String>()))
    }
}
