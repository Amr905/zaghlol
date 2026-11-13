package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.GuardFixtures
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.SoftwareGuardUserCipher
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * FR-ING-A-03 (AC2): a package that is not in the registry (or the user's
 * `notification` senders) is not read at all, and leaves no file.
 */
class NotificationAdmissionTest {
    private val root = tempDir()
    private val status = CaptureStatusStore(File(root, "capture/status.bin"), SoftwareSpoolCipher())
    private val store = storeIn(File(root, "spool"), status = status)
    private var enqueues = 0

    private fun guard(base: () -> ByteArray = { GuardFixtures.t1Base }, user: ByteArray? = GuardFixtures.t1User) =
        GuardRuntime(base, GuardUserConfigStore(tempDir(), SoftwareGuardUserCipher()), { 0L })
            .also { g -> if (user != null) g.writeUser(user) }

    private fun intake(g: GuardRuntime = guard()) = NotificationIntake(
        admits = g::admitsNotificationPackage,
        intake = CaptureIntake(
            channel = app.zaghlol.platform.guard.AndroidGuardChannel.NOTIFICATION,
            decide = g::decide,
            store = store,
            status = status,
            afterWrite = { enqueues++ },
        ),
        recent = RecentNotifications({ 0L }),
    )

    private fun tree() = root.walkTopDown().associate { it.relativeTo(root).path to (if (it.isFile) it.readBytes().toList() else emptyList()) }

    @Test
    fun anUnknownPackageIsNeverReadAndLeavesTheRootIdentical() {
        val before = tree()
        val p = FakePosted("com.example.messenger", FakeFields(title = "Mom", text = "see you at 7"))
        assertNull(intake().process(p, 1L, 2L))
        assertEquals("not a single extras read", 0, p.fields.reads)
        assertEquals(before, tree())
        assertEquals(0, enqueues)
    }

    @Test
    fun aRegistryPackageIsReadAndStored() {
        val p = FakePosted("com.example.nbe", FakeFields(title = "NBE", bigText = "Purchase EGP 10.00 card **1234"))
        val r = intake().process(p, 1L, 2L)
        assertNotNull(r)
        assertEquals(1, r!!.written.size)
        assertEquals(1, enqueues)
        val rec = (store.read(r.written[0]) as app.zaghlol.platform.spool.SpoolStore.ReadResult.Ok).record
        assertEquals("notification", rec.channel)
        assertEquals("com.example.nbe", rec.source)
        assertEquals("NBE\nPurchase EGP 10.00 card **1234", rec.body)
        assertNull(rec.simSlot)
    }

    @Test
    fun aUserNotificationSenderIsAdmitted() {
        val p = FakePosted("com.example.wallet", FakeFields(text = "Points used: EGP 5.00"))
        assertEquals(1, intake().process(p, 1L, 2L)!!.written.size)
    }

    @Test
    fun theSameValueAsAnSmsUserSenderIsNotAdmitted() {
        val p = FakePosted("club-7", FakeFields(text = "Points used: EGP 5.00"))
        assertNull(intake().process(p, 1L, 2L))
        assertEquals(0, p.fields.reads)
    }

    @Test
    fun aHintOnlyPackageIsNotAdmittedEvenWithAnAmount() {
        // "bank" is a generic sender hint and the body has an amount: the SMS path would keep it.
        val p = FakePosted("com.example.bank", FakeFields(title = "Alert", text = "EGP 5.00 spent"))
        assertNull(intake().process(p, 1L, 2L))
        assertEquals(0, p.fields.reads)
        assertFalse(File(root, "spool").exists())
    }

    @Test
    fun anInvalidBaseAdmitsNothing() {
        val g = guard(base = { "not json".toByteArray() }, user = null)
        val p = FakePosted("com.example.nbe")
        assertNull(intake(g).process(p, 1L, 2L))
        assertEquals(0, p.fields.reads)
        assertFalse(g.admitsNotificationPackage("com.example.nbe"))
    }

    @Test
    fun aRegistryOtpIsDroppedAndLeavesNoFile() {
        val before = tree()
        val p = FakePosted("com.example.nbe", FakeFields(title = "NBE", text = "Your OTP is 123456"))
        val r = intake().process(p, 1L, 2L)!!
        assertEquals(1, r.dropped)
        assertEquals(before, tree())
        assertTrue(r.written.isEmpty())
    }
}
