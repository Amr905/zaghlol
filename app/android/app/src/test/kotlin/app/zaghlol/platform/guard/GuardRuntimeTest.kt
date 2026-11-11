package app.zaghlol.platform.guard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Modes and failure handling (design note section 4), writer (section 5, AC3) and concurrency (section 6). */
class GuardRuntimeTest {
    private val dir = File(tempDir(), "guard")
    private val ops = FaultyFileOps()
    private val cipher = FlakyGuardUserCipher()
    private val store = GuardUserConfigStore(dir, cipher, ops)
    private var baseLoads = 0
    private var baseBytes: ByteArray? = GuardFixtures.t1Base
    private var now = 0L

    private fun runtime() = GuardRuntime(
        loadBase = {
            baseLoads++
            baseBytes ?: throw FileNotFoundException("asset")
        },
        store = store,
        clockMs = { now },
    )

    // NBE card 4567 is ignored on SMS by t1_user; BM is ignored as an institution.
    private val ignoredCard = Triple("sms", "NBE", "Purchase EGP 10.00 card **4567")

    private fun GuardRuntime.decideIgnored() = decision(decide(ignoredCard.first, ignoredCard.second, ignoredCard.third))

    @Test
    fun freshInstallIsBaseOnlyAndCached() {
        val rt = runtime()
        val s = rt.current()
        assertEquals(GuardConfigMode.BASE_ONLY, s.mode)
        assertEquals(GuardUserState.ABSENT, s.userState)
        assertTrue(rt.current() === s)
        assertEquals(1, baseLoads)
        assertEquals("keep", rt.decideIgnored()["decision"])
    }

    @Test
    fun missingBaseIsInvalidAndRetried() {
        baseBytes = null
        val rt = runtime()
        assertEquals(GuardConfigMode.INVALID, rt.current().mode)
        assertEquals(mapOf("decision" to "drop", "reason" to "config_invalid"), rt.decideIgnored())
        baseBytes = GuardFixtures.t1Base
        assertEquals(GuardConfigMode.BASE_ONLY, rt.current().mode)
        assertTrue(baseLoads >= 2)
    }

    @Test
    fun invalidBaseIsInvalidEvenWithAValidUserPart() {
        store.write(GuardFixtures.t1User)
        baseBytes = GuardFixtures.bytes("configs/base_v3.json")
        assertEquals(GuardConfigMode.INVALID, runtime().current().mode)
    }

    @Test
    fun writeThenFullRulesApply() {
        val rt = runtime()
        assertEquals("keep", rt.decideIgnored()["decision"])
        val json = GuardFixtures.t1User
        rt.writeUser(json)
        assertTrue("buffer zeroed", json.all { it == 0.toByte() })
        assertEquals(GuardConfigMode.FULL, rt.current().mode)
        assertEquals(GuardUserState.OK, rt.current().userState)
        assertEquals("ignored_card", rt.decideIgnored()["reason"])
        // A new process reads the file back.
        assertEquals("ignored_card", runtime().decideIgnored()["reason"])
    }

    /** AC3 (L-2): invalid input is rejected before anything is written; the previous file and rules stay. */
    @Test
    fun invalidWriteChangesNothing() {
        val rt = runtime()
        rt.writeUser(GuardFixtures.t1User)
        val before = store.file.readBytes()
        val snapshot = rt.current()
        val writesBefore = ops.calls.count { it == "write" }
        for (bad in listOf("configs/bad_user.json", "configs/user_v2.json", "configs/user_last4_only.json", "configs/user_unknown_key.json", "configs/user_indic_last4.json")) {
            val json = GuardFixtures.bytes(bad)
            try {
                rt.writeUser(json)
                throw AssertionError("$bad accepted")
            } catch (e: GuardConfigWriteException) {
                assertEquals(GuardWriteError.CONFIG_INVALID, e.error)
            }
            assertTrue("buffer zeroed", json.all { it == 0.toByte() })
        }
        val big = ByteArray(GuardConfig.MAX_USER_BYTES + 1) { ' '.code.toByte() }
        try {
            rt.writeUser(big)
            throw AssertionError("over 64 KB accepted")
        } catch (e: GuardConfigWriteException) {
            assertEquals(GuardConfigErrorCode.tooLarge, e.detail!!.code)
        }
        assertEquals(writesBefore, ops.calls.count { it == "write" })
        assertArrayEquals(before, store.file.readBytes())
        assertTrue(rt.current() === snapshot)
    }

    @Test
    fun failedIoWriteKeepsOldFileAndSnapshot() {
        val rt = runtime()
        rt.writeUser(GuardFixtures.t1User)
        val snapshot = rt.current()
        ops.failRename = true
        try {
            rt.writeUser(GuardFixtures.bytes("configs/user_old_registry.json"))
            throw AssertionError("write succeeded")
        } catch (e: GuardConfigWriteException) {
            assertEquals(GuardWriteError.IO_ERROR, e.error)
        }
        assertTrue(rt.current() === snapshot)
        assertEquals("ignored_card", runtime().decideIgnored()["reason"])
    }

    /** AC2: an undecryptable user file keeps registry senders (`baseOnly`), is cached, and is not deleted. */
    @Test
    fun tamperedUserFileIsBaseOnlyUnreadableCachedAndKept() {
        store.write(GuardFixtures.t1User)
        val data = store.file.readBytes().also { it[20] = (it[20].toInt() xor 0x55).toByte() }
        store.file.writeBytes(data)
        val rt = runtime()
        val s = rt.current()
        assertEquals(GuardConfigMode.BASE_ONLY, s.mode)
        assertEquals(GuardUserState.UNREADABLE, s.userState)
        assertEquals("keep", rt.decideIgnored()["decision"])
        val reads = ops.calls.count { it == "read" }
        rt.current()
        assertEquals("cached until the next write", reads, ops.calls.count { it == "read" })
        assertArrayEquals(data, store.file.readBytes())
        rt.writeUser(GuardFixtures.t1User)
        assertEquals(GuardUserState.OK, rt.current().userState)
    }

    @Test
    fun wrongKeyIsLikeATagFailure() {
        store.write(GuardFixtures.t1User)
        val other = GuardUserConfigStore(dir, SoftwareGuardUserCipher(ByteArray(32) { 9 }), ops)
        val rt = GuardRuntime({ GuardFixtures.t1Base }, other, { 0L })
        assertEquals(GuardUserState.UNREADABLE, rt.current().userState)
        assertEquals(GuardConfigMode.BASE_ONLY, rt.current().mode)
    }

    @Test
    fun decryptedButMalformedUserPartIsUnreadable() {
        store.write(GuardFixtures.bytes("configs/user_v2.json"))
        val s = runtime().current()
        assertEquals(GuardConfigMode.BASE_ONLY, s.mode)
        assertEquals(GuardUserState.UNREADABLE, s.userState)
    }

    @Test
    fun transientReadIsNotCached() {
        store.write(GuardFixtures.t1User)
        val rt = runtime()
        cipher.failDecrypt = true
        val s = rt.current()
        assertEquals(GuardConfigMode.BASE_ONLY, s.mode)
        assertEquals(GuardUserState.RETRY, s.userState)
        cipher.failDecrypt = false
        assertEquals(GuardConfigMode.FULL, rt.current().mode)
        assertEquals(1, baseLoads) // the valid base is reused
    }

    @Test
    fun rateLimitIsAppliedPerProcess() {
        val rt = runtime()
        repeat(20) { assertEquals("keep", decision(rt.decide("sms", "NBE", "Purchase EGP 10.00"))["decision"]) }
        assertEquals("rate_limited", decision(rt.decide("sms", "NBE", "Purchase EGP 10.00"))["reason"])
        now = 60_000
        assertEquals("keep", decision(rt.decide("sms", "NBE", "Purchase EGP 10.00"))["decision"])
    }

    /** Two actors: readers during writes always see a whole snapshot (old or new rules), never a mix or an error. */
    @Test
    fun readersDuringWritesSeeOldOrNewRules() {
        val rt = runtime()
        val pool = Executors.newFixedThreadPool(6)
        val start = CountDownLatch(1)
        val bad = AtomicInteger()
        val userA = GuardFixtures.t1User
        val userB = mapOf("v" to 1, "baseRegistryVersion" to 3, "ignore" to emptyList<Any>(), "userSenders" to emptyList<Any>()).bytes()
        repeat(4) {
            pool.execute {
                start.await()
                repeat(500) {
                    val s = rt.current()
                    val r = decision(s.guard.decide(ignoredCard.first, ignoredCard.second, ignoredCard.third))
                    val ok = when (s.mode) {
                        GuardConfigMode.FULL -> r["reason"] == "ignored_card" || r["decision"] == "keep"
                        GuardConfigMode.BASE_ONLY -> r["decision"] == "keep"
                        GuardConfigMode.INVALID -> false
                    }
                    if (!ok) bad.incrementAndGet()
                }
            }
        }
        repeat(2) { w ->
            pool.execute {
                start.await()
                repeat(30) { i -> rt.writeUser((if ((i + w) % 2 == 0) userA else userB).copyOf()) }
            }
        }
        start.countDown()
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))
        assertEquals(0, bad.get())
        assertTrue(store.read() is GuardUserConfigStore.Read.Plain)
        assertTrue(!File(dir, "guard.user.enc.tmp").exists())
    }

    @Test
    fun snapshotToStringHasModeAndStateOnly() {
        assertEquals("GuardSnapshot(baseOnly, ABSENT)", runtime().current().toString())
    }
}
