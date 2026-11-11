package app.zaghlol.platform.spool

import app.zaghlol.platform.keys.KeyErrorClassifier
import app.zaghlol.platform.keys.KeystoreErrorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.AEADBadTagException

class SpoolKeyManagerTest {
    /** Fake Keystore: [loads] scripts each load (a Throwable is thrown, otherwise returned). */
    private class FakeOps(var key: Any?, val loads: ArrayDeque<Any?> = ArrayDeque()) : KeystoreOps<Any> {
        val creates = AtomicInteger()
        var deletes = 0
        var created: Long? = 1_000L
        val log = ArrayList<String>()

        override fun load(): Any? {
            log += "load"
            if (loads.isNotEmpty()) {
                val next = loads.removeFirst()
                if (next is Throwable) throw next
                return next
            }
            return key
        }

        override fun create(): Any {
            log += "create"
            creates.incrementAndGet()
            Thread.sleep(5)
            return Any().also { key = it }
        }

        override fun delete() {
            log += "delete"
            deletes++
            key = null
        }

        override fun creationDateMs(): Long? = created ?: throw IllegalStateException("ks")
    }

    private val classifier = KeyErrorClassifier { null } // API < 33: only typed evidence counts

    private fun manager(ops: FakeOps, sleep: RecordingSleep = RecordingSleep()) = SpoolKeyManager(ops, classifier, sleep.fn)

    @Test
    fun anExistingKeyIsReturnedAndNeverRecreated() {
        val k = Any()
        val ops = FakeOps(k)
        assertSame(k, manager(ops).get())
        assertEquals(0, ops.creates.get())
    }

    @Test
    fun aMissingKeyIsCreatedOnce() {
        val ops = FakeOps(null)
        val m = manager(ops)
        val first = m.get()
        assertSame(first, m.get())
        assertEquals(1, ops.creates.get())
        assertEquals(0, ops.deletes)
    }

    @Test
    fun unusableFourTimesDeletesOnceAndCreates() {
        val bad = AEADBadTagException("blob")
        val ops = FakeOps(Any(), ArrayDeque(listOf(bad, bad, bad, bad)))
        val sleep = RecordingSleep()
        manager(ops, sleep).get()
        assertEquals(listOf(100L, 300L, 900L), sleep.calls)
        assertEquals(1, ops.deletes)
        assertEquals(1, ops.creates.get())
        assertEquals(listOf("load", "load", "load", "load", "delete", "create"), ops.log)
    }

    @Test
    fun anUnusableKeyThatRecoversIsKept() {
        val k = Any()
        val bad = AEADBadTagException("blob")
        val ops = FakeOps(k, ArrayDeque(listOf(bad, bad)))
        assertSame(k, manager(ops).get())
        assertEquals(0, ops.deletes)
    }

    @Test
    fun anyUnavailableAnswerThrowsAndDeletesNothing() {
        val bad = AEADBadTagException("blob")
        for (mix in listOf(listOf(IOException("busy")), listOf(bad, bad, bad, IllegalStateException("?")), listOf(bad, RuntimeException("x")))) {
            val ops = FakeOps(Any(), ArrayDeque(mix))
            try {
                manager(ops).get()
                fail("no error for $mix")
            } catch (e: SpoolKeyUnavailableException) {
                assertEquals("SPOOL_KEY_UNAVAILABLE", e.message)
            }
            assertEquals(0, ops.deletes)
            assertEquals(0, ops.creates.get())
        }
    }

    @Test
    fun api33KeystoreErrorsAreClassified() {
        class Ks(val missing: Boolean, val transient: Boolean) : Exception()
        val api33 = KeyErrorClassifier { e -> (e as? Ks)?.let { KeystoreErrorInfo(it.missing, it.transient) } }
        val ops = FakeOps(Any(), ArrayDeque(List(4) { Ks(missing = true, transient = false) }))
        SpoolKeyManager(ops, api33, RecordingSleep().fn).get()
        assertEquals(1, ops.deletes)
        val transientOps = FakeOps(Any(), ArrayDeque(List(4) { Ks(missing = true, transient = true) }))
        try {
            SpoolKeyManager(transientOps, api33, RecordingSleep().fn).get()
            fail("no error")
        } catch (_: SpoolKeyUnavailableException) {
        }
        assertEquals(0, transientOps.deletes)
    }

    @Test
    fun concurrentFirstCallersCreateExactlyOnce() {
        val ops = FakeOps(null)
        val m = SpoolKeyManager(ops, classifier)
        val threads = 16
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(threads)
        val results = (1..threads).map { pool.submit<Any> { start.await(); m.get() } }
        start.countDown()
        val keys = results.map { it.get(5, TimeUnit.SECONDS) }
        pool.shutdown()
        assertEquals(1, ops.creates.get())
        assertTrue(keys.all { it === keys[0] })
    }

    @Test
    fun creationDateErrorsAreUnknown() {
        val ops = FakeOps(Any())
        assertEquals(1_000L, manager(ops).creationDateMs())
        ops.created = null
        assertNull(manager(ops).creationDateMs())
    }

    // FU-104 #9: an alias that holds no SecretKey is an UNUSABLE attempt of the ladder, never a direct create.
    @Test
    fun anAliasWithoutASecretKeyGoesThroughTheLadder() {
        val noKey = UnusableKeyEntryException()
        val ops = FakeOps(Any(), ArrayDeque(listOf(noKey, noKey, noKey, noKey)))
        val sleep = RecordingSleep()
        manager(ops, sleep).get()
        assertEquals(listOf(100L, 300L, 900L), sleep.calls)
        assertEquals(listOf("load", "load", "load", "load", "delete", "create"), ops.log)
    }

    @Test
    fun secretKeyOrNullNeedsProofOfAbsence() {
        val k = javax.crypto.spec.SecretKeySpec(ByteArray(32), "AES")
        assertSame(k, secretKeyOrNull(k) { true })
        assertNull("alias absent", secretKeyOrNull(null) { false })
        for ((entry, contains) in listOf<Pair<java.security.Key?, Boolean>>(null to true, FakePublicKey to true, FakePublicKey to false)) {
            try {
                secretKeyOrNull(entry) { contains }
                fail("no error for $entry/$contains")
            } catch (_: UnusableKeyEntryException) {
            }
        }
        try {
            secretKeyOrNull(null) { throw IOException("busy") }
            fail("no error")
        } catch (_: IOException) {
            // containsAlias failing proves nothing: propagated, classified UNAVAILABLE by the manager.
        }
    }

    // FU-104 #6: a Cipher.init failure is classified like a load failure.
    @Test
    fun anUnusableInitFourTimesRecreatesTheKey() {
        val ops = FakeOps(Any())
        val sleep = RecordingSleep()
        var inits = 0
        val first = ops.key
        val result = manager(ops, sleep).withKey { key ->
            inits++
            if (key === first) throw AEADBadTagException("lost")
            "ok"
        }
        assertEquals("ok", result)
        assertEquals(5, inits)
        assertEquals(listOf(100L, 300L, 900L), sleep.calls)
        assertEquals(listOf("load", "load", "load", "load", "delete", "create"), ops.log)
    }

    @Test
    fun anInitThatRecoversKeepsTheKey() {
        val ops = FakeOps(Any())
        var inits = 0
        val result = manager(ops).withKey {
            if (++inits < 3) throw AEADBadTagException("lost")
            "ok"
        }
        assertEquals("ok", result)
        assertEquals(0, ops.deletes)
    }

    @Test
    fun anUnavailableInitThrowsAndDeletesNothing() {
        val ops = FakeOps(Any())
        try {
            manager(ops).withKey<Unit> { throw java.security.ProviderException("keystore busy") }
            fail("no error")
        } catch (_: SpoolKeyUnavailableException) {
        }
        assertEquals(0, ops.deletes)
        assertEquals(0, ops.creates.get())
    }

    @Test
    fun aFreshKeyThatCannotBeInitialisedIsUnavailable() {
        val ops = FakeOps(null)
        try {
            manager(ops).withKey<Unit> { throw IllegalStateException("x") }
            fail("no error")
        } catch (_: SpoolKeyUnavailableException) {
        }
        assertEquals(1, ops.creates.get())
        assertEquals(0, ops.deletes)
    }

    private object FakePublicKey : java.security.PublicKey {
        override fun getAlgorithm() = "EC"
        override fun getFormat() = "X.509"
        override fun getEncoded() = ByteArray(0)
    }
}
