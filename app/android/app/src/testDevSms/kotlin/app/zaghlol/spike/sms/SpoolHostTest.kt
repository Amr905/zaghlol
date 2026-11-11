package app.zaghlol.spike.sms

import app.zaghlol.platform.capture.CaptureApiError
import app.zaghlol.platform.capture.FakeDevice
import app.zaghlol.platform.capture.FakeScheduler
import app.zaghlol.platform.capture.InboxQuery
import app.zaghlol.platform.capture.IngestScheduler
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.put
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class SpoolHostTest {
    private val dir = tempDir()
    private val store = storeIn(dir)
    private val claim = SpoolClaim(clock = { 0 })
    private val sched = FakeScheduler()
    private val device = FakeDevice()

    private fun host(engine: Long) = SpoolHost(engine, store, claim, sched, device, null) { null }

    private fun write(body: String) = store.put(body)

    private fun expectCode(code: String, block: () -> Unit) {
        try {
            block()
            fail("no error")
        } catch (e: CaptureApiError) {
            assertEquals(code, e.code)
            assertNull(e.message)
            assertNull(e.details)
        }
    }

    @Test
    fun drainReturnsOldestFirstUpToMax() {
        val ids = (1..3).map { write("m$it") }
        val got = host(1).drainSpool(2)
        assertEquals(ids.take(2), got.map { it.id })
        assertEquals("m1", got[0].body)
        assertEquals("5550100", got[0].source)
        assertEquals("sms", got[0].channel)
        assertEquals(1L, got[0].simSlot)
    }

    @Test
    fun twoEnginesNeverGetTheSameEntries() {
        val ids = (1..2).map { write("m$it") }
        val ui = host(1)
        val headless = host(2)
        assertEquals(ids, ui.drainSpool(10).map { it.id })
        assertEquals(emptyList<String>(), headless.drainSpool(10).map { it.id })
        ui.ackSpool(ids)
        val third = write("m3")
        assertEquals(listOf(third), headless.drainSpool(10).map { it.id })
    }

    @Test
    fun detachReleasesTheClaimWithoutDeleting() {
        val id = write("m")
        val ui = host(1)
        ui.drainSpool(10)
        ui.detach()
        assertEquals(listOf(id), host(2).drainSpool(10).map { it.id })
    }

    @Test
    fun ackDeletesAndIsIdempotent() {
        val id = write("m")
        val h = host(1)
        h.drainSpool(10)
        h.ackSpool(listOf(id))
        h.ackSpool(listOf(id))
        assertEquals(emptyList<String>(), store.pendingIds())
    }

    @Test
    fun noAckMeansRedelivery() {
        val id = write("m")
        val h = host(1)
        h.drainSpool(10)
        assertEquals(listOf(id), h.drainSpool(10).map { it.id })
    }

    @Test
    fun maxIsClamped() {
        repeat(3) { write("m$it") }
        assertEquals(1, host(1).drainSpool(0).size)
        assertEquals(3, host(1).drainSpool(1_000_000).size)
    }

    @Test
    fun corruptEntryIsDeletedAndNotReturned() {
        val bad = write("bad")
        val good = write("good")
        File(dir, "$bad.bin").writeBytes(ByteArray(40))
        assertEquals(listOf(good), host(1).drainSpool(10).map { it.id })
        assertEquals(listOf(good), store.pendingIds())
    }

    @Test
    fun unimplementedMethodsAreNotAvailableWithoutText() {
        val h = host(1)
        expectCode("NOT_AVAILABLE") { h.openNotificationAccessSettings() }
        expectCode("NOT_AVAILABLE") { h.writeGuardConfig(ByteArray(1)) }
        expectCode("NOT_AVAILABLE") { h.queryInbox(InboxQuery(0, listOf("x"), null, 10)) }
        var result: Result<Boolean>? = null
        h.requestSmsPermission { result = it }
        assertEquals("NOT_AVAILABLE", (result!!.exceptionOrNull() as CaptureApiError).code)
    }

    @Test
    fun internalErrorsBecomeCodeOnlyIoError() {
        val broken = SpoolHost(1, storeIn(kotlin.io.path.createTempFile().toFile()), claim, sched, device, null) { null }
        // pendingIds of a file "directory" is empty, so force an error through ack's size cap instead.
        expectCode("IO_ERROR") { broken.ackSpool(List(SpoolHost.MAX_DRAIN + 1) { "x" }) }
        val throwingSched = IngestScheduler { throw IllegalStateException("ZG_CANARY_7731") }
        expectCode("IO_ERROR") { SpoolHost(1, store, claim, throwingSched, device, null) { null }.scheduleIngestionNow() }
    }

    @Test
    fun schedulingBatteryAndCapabilities() {
        val h = host(1)
        h.scheduleIngestionNow()
        assertEquals(1, sched.enqueued)
        h.requestIgnoreBatteryOptimizations()
        assertEquals(1, device.settingsOpened)
        assertEquals(false, h.isIgnoringBatteryOptimizations())
        assertTrue(h.getCapabilities().smsFlavor)
    }
}
