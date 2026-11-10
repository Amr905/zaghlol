package app.zaghlol.platform.share

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareJobTest {
    /** Runs posted work when [drain] is called, like a main-thread Handler. */
    private val queue = ArrayDeque<Runnable>()
    private fun drain() {
        while (queue.isNotEmpty()) queue.removeFirst().run()
    }

    private val accepted = ShareOutcome.Accepted(ShareDescriptor("a".repeat(28), ShareKind.TEXT, "text/plain", 1, 1))
    private val timedOut = ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)

    @After
    fun clearState() {
        ShareIntakeState.takeRejection()
    }

    @Test
    fun theFirstOutcomeWinsAndIsDeliveredOnce() {
        val job = ShareJob("j", queue::addLast)
        val got = mutableListOf<ShareOutcome>()
        job.attach { got += it }
        assertTrue(job.complete(accepted))
        assertFalse("the timeout after the worker is ignored", job.complete(timedOut))
        drain()
        drain()
        assertEquals(listOf<ShareOutcome>(accepted), got)
        assertTrue(job.isDelivered)
    }

    @Test
    fun anOutcomeSetWhileDetachedGoesToTheRecreatedActivityOnly() {
        val job = ShareJob("j", queue::addLast)
        val old = mutableListOf<ShareOutcome>()
        val recreated = mutableListOf<ShareOutcome>()
        job.attach { old += it }
        job.detach() // configuration change: old instance destroyed
        job.complete(accepted)
        drain()
        assertTrue(old.isEmpty())
        assertFalse(job.isDelivered)
        job.attach { recreated += it } // new instance re-attaches by id, does not ingest again
        assertEquals(listOf<ShareOutcome>(accepted), recreated)
        drain()
        assertEquals(1, recreated.size)
    }

    @Test
    fun detachingBeforeThePostedDeliveryRunsHandsItToTheNextListener() {
        val job = ShareJob("j", queue::addLast)
        val old = mutableListOf<ShareOutcome>()
        val recreated = mutableListOf<ShareOutcome>()
        job.attach { old += it }
        job.complete(accepted) // posted, not yet run
        job.detach()
        job.attach { recreated += it }
        drain()
        assertTrue(old.isEmpty())
        assertEquals(listOf<ShareOutcome>(accepted), recreated)
    }

    @Test
    fun finishRecordsARefusalOnlyForTheFirstOutcome() {
        val job = ShareJobs.create(queue::addLast)
        assertTrue(ShareJobs.finish(job, accepted))
        assertFalse(ShareJobs.finish(job, timedOut))
        assertNull(ShareIntakeState.takeRejection())

        val slow = ShareJobs.create(queue::addLast)
        assertTrue(ShareJobs.finish(slow, timedOut))
        assertEquals(ShareRejectReason.UNREADABLE, ShareIntakeState.takeRejection())
        ShareJobs.remove(job.id)
        ShareJobs.remove(slow.id)
    }

    @Test
    fun jobIdsAreUniqueAndLookedUpById() {
        val a = ShareJobs.create(queue::addLast)
        val b = ShareJobs.create(queue::addLast)
        assertNotEquals(a.id, b.id)
        assertTrue(ShareJobs.get(a.id) === a)
        ShareJobs.remove(a.id)
        assertNull(ShareJobs.get(a.id))
        assertNull("an id from a previous process never matches", ShareJobs.get("000000000000-1"))
        ShareJobs.remove(b.id)
    }
}
