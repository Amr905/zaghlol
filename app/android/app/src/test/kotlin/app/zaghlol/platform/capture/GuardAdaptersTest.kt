package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.CaptureGuard
import app.zaghlol.platform.guard.GuardConfigMode
import app.zaghlol.platform.guard.GuardFixtures
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardSnapshot
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.GuardUserState
import app.zaghlol.platform.guard.SoftwareGuardUserCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** FU-104 code #3 (T-040 design note section 6): the Guard writer and state adapters. */
class GuardAdaptersTest {
    private val guardDir = tempDir()
    private var base: () -> ByteArray = { GuardFixtures.t1Base }

    private fun runtime(store: GuardUserConfigStore = GuardUserConfigStore(guardDir, SoftwareGuardUserCipher())) =
        GuardRuntime({ base() }, store, { 0L })

    private fun host(rt: GuardRuntime?) = AndroidCaptureHost(
        engineId = 1,
        store = storeIn(tempDir()),
        claim = SpoolClaim(),
        status = statusIn(tempDir()),
        scheduler = null,
        guardWriter = rt?.let { GuardAdapters.writerFor(it) },
        guardState = rt?.let { GuardAdapters.stateFor(it) },
        device = null,
    )

    @Test
    fun stateTableOverEveryModeAndUserState() {
        val expected = mapOf(
            (GuardConfigMode.INVALID to GuardUserState.ABSENT) to GuardConfigState.BASE_INVALID,
            (GuardConfigMode.INVALID to GuardUserState.OK) to GuardConfigState.BASE_INVALID,
            (GuardConfigMode.INVALID to GuardUserState.UNREADABLE) to GuardConfigState.BASE_INVALID,
            (GuardConfigMode.INVALID to GuardUserState.RETRY) to GuardConfigState.BASE_INVALID,
            (GuardConfigMode.FULL to GuardUserState.OK) to GuardConfigState.FULL,
            (GuardConfigMode.FULL to GuardUserState.ABSENT) to GuardConfigState.UNKNOWN,
            (GuardConfigMode.FULL to GuardUserState.UNREADABLE) to GuardConfigState.UNKNOWN,
            (GuardConfigMode.FULL to GuardUserState.RETRY) to GuardConfigState.UNKNOWN,
            (GuardConfigMode.BASE_ONLY to GuardUserState.ABSENT) to GuardConfigState.BASE_ONLY,
            (GuardConfigMode.BASE_ONLY to GuardUserState.UNREADABLE) to GuardConfigState.USER_UNREADABLE,
            (GuardConfigMode.BASE_ONLY to GuardUserState.RETRY) to GuardConfigState.UNKNOWN,
            (GuardConfigMode.BASE_ONLY to GuardUserState.OK) to GuardConfigState.UNKNOWN,
        )
        assertEquals(GuardConfigMode.entries.size * GuardUserState.entries.size, expected.size)
        for ((pair, state) in expected) {
            assertEquals("$pair", state, GuardAdapters.stateOf(GuardSnapshot(CaptureGuard(null), pair.first, pair.second)))
        }
    }

    @Test
    fun theRealRuntimeReportsBaseOnlyThenFullThroughTheHost() {
        val rt = runtime()
        val h = host(rt)
        assertEquals(GuardConfigState.BASE_ONLY, h.getSpoolStatus().guardState)
        h.writeGuardConfig(GuardFixtures.t1User)
        assertEquals(GuardConfigState.FULL, h.getSpoolStatus().guardState)
    }

    @Test
    fun aMissingBaseIsBaseInvalid() {
        base = { throw java.io.FileNotFoundException("asset") }
        assertEquals(GuardConfigState.BASE_INVALID, host(runtime()).getSpoolStatus().guardState)
    }

    @Test
    fun configInvalidIsCodeOnlyAndTheInputIsZeroed() {
        val h = host(runtime())
        val bad = """{"v":1,"baseRegistryVersion":3,"ignore":[],"userSenders":[],"ZG_CANARY_7731":1}""".toByteArray()
        try {
            h.writeGuardConfig(bad)
            fail("accepted an unknown key")
        } catch (e: CaptureApiError) {
            assertEquals("CONFIG_INVALID", e.code)
            assertNull(e.message)
            assertNull(e.details)
            assertNull(e.cause)
        }
        assertTrue(bad.all { it == 0.toByte() })
    }

    @Test
    fun theWriterItselfRepliesCodeOnlyForBothWriteErrors() {
        val writer = GuardAdapters.writerFor(runtime())
        val bad = """{"v":1,"baseRegistryVersion":3,"ignore":[],"userSenders":[],"ZG_CANARY_7731":1}""".toByteArray()
        try {
            writer(bad)
            fail()
        } catch (e: CaptureApiError) {
            assertEquals("CONFIG_INVALID", e.code)
            assertNull(e.message)
            assertNull(e.details)
        }
        val notADir = File(tempDir(), "file").apply { writeText("x") }
        val ioWriter = GuardAdapters.writerFor(runtime(GuardUserConfigStore(File(notADir, "guard"), SoftwareGuardUserCipher())))
        try {
            ioWriter(GuardFixtures.t1User)
            fail()
        } catch (e: CaptureApiError) {
            assertEquals("IO_ERROR", e.code)
            assertNull(e.message)
            assertNull(e.details)
        }
    }

    @Test
    fun anIoErrorIsIoErrorCodeOnly() {
        // A user dir that is a file: the write can't create it.
        val notADir = File(tempDir(), "file").apply { writeText("x") }
        val h = host(runtime(GuardUserConfigStore(File(notADir, "guard"), SoftwareGuardUserCipher())))
        val json = GuardFixtures.t1User
        try {
            h.writeGuardConfig(json)
            fail("wrote under a file")
        } catch (e: CaptureApiError) {
            assertEquals("IO_ERROR", e.code)
            assertNull(e.message)
            assertNull(e.details)
        }
        assertTrue(json.all { it == 0.toByte() })
    }

    @Test
    fun anyOtherExceptionIsIoErrorAndNeverForwardsItsMessage() {
        for (thrown in listOf(IllegalStateException("ZG_CANARY_7731"), java.security.ProviderException("ZG_CANARY_7731"))) {
            val writer = GuardAdapters.writerOf { throw thrown }
            val input = byteArrayOf(1, 2, 3)
            try {
                writer(input)
                fail()
            } catch (e: CaptureApiError) {
                assertEquals("IO_ERROR", e.code)
                assertNull(e.message)
                assertNull(e.details)
                assertNull(e.cause)
                assertFalse(e.toString().contains("ZG_CANARY"))
            }
            assertTrue(input.all { it == 0.toByte() })
        }
        // Through the host as well: the reply carries the code only.
        val h = AndroidCaptureHost(
            1, storeIn(tempDir()), SpoolClaim(), statusIn(tempDir()), null,
            GuardAdapters.writerOf { throw IllegalStateException("ZG_CANARY_7731") }, null, null,
        )
        try {
            h.writeGuardConfig(byteArrayOf(1))
            fail()
        } catch (e: CaptureApiError) {
            assertEquals("IO_ERROR", e.code)
            assertNull(e.message)
        }
    }

    @Test
    fun bothWriteErrorCodesMap() {
        assertEquals("CONFIG_INVALID", GuardAdapters.codeOf(app.zaghlol.platform.guard.GuardWriteError.CONFIG_INVALID))
        assertEquals("IO_ERROR", GuardAdapters.codeOf(app.zaghlol.platform.guard.GuardWriteError.IO_ERROR))
    }

    @Test
    fun noRuntimeIsNotAvailableAndUnknown() {
        val h = host(null)
        assertEquals(GuardConfigState.UNKNOWN, h.getSpoolStatus().guardState)
        try {
            h.writeGuardConfig(byteArrayOf(1))
            fail()
        } catch (e: CaptureApiError) {
            assertEquals("NOT_AVAILABLE", e.code)
        }
    }

    @Test
    fun aThrowingStateIsUnknown() {
        val h = AndroidCaptureHost(1, storeIn(tempDir()), SpoolClaim(), statusIn(tempDir()), null, null, { throw IllegalStateException("x") }, null)
        assertEquals(GuardConfigState.UNKNOWN, h.getSpoolStatus().guardState)
    }
}
