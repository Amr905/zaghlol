package app.zaghlol.platform.guard

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.crypto.AEADBadTagException

/** The encrypted user file (AC3, AC4; L-1, L-2): format, AAD, atomic replace, failure handling. */
class GuardUserConfigStoreTest {
    private val dir = File(tempDir(), "guard")
    private val cipher = SoftwareGuardUserCipher()

    @Test
    fun roundTripAndFormat() {
        val store = GuardUserConfigStore(dir, cipher)
        assertTrue(store.read() === GuardUserConfigStore.Read.Absent)
        store.write(GuardFixtures.t1User)
        val onDisk = store.file.readBytes()
        assertEquals(GuardFixtures.t1User.size + 12 + 16, onDisk.size)
        val read = store.read() as GuardUserConfigStore.Read.Plain
        assertArrayEquals(GuardFixtures.t1User, read.bytes)
        assertEquals("guard.user.enc", store.file.name)
        assertFalse(File(dir, "guard.user.enc.tmp").exists())
    }

    @Test
    fun aadBindsTheFileToItsRole() {
        val store = GuardUserConfigStore(dir, cipher)
        store.write(GuardFixtures.t1User)
        val data = store.file.readBytes()
        assertArrayEquals(GuardFixtures.t1User, cipher.decrypt(data, "zaghlol.guard.v1|user".toByteArray()))
        try {
            cipher.decrypt(data, "zaghlol.guard.v1|base".toByteArray())
            throw AssertionError("AAD swap decrypted")
        } catch (e: AEADBadTagException) {
            // expected
        }
    }

    /** AC4: on disk only as ciphertext; the canary institution, last-4 and key names never appear. */
    @Test
    fun ciphertextOnDiskHasNoCanary() {
        val canary = mapOf(
            "v" to 1, "baseRegistryVersion" to 3,
            "ignore" to listOf(mapOf("inst" to "zgcanaryinst", "last4" to "7731", "ch" to "sms")),
            "userSenders" to listOf(mapOf("value" to "ZG_CANARY_SRC", "ch" to "sms")),
        ).bytes()
        val store = GuardUserConfigStore(dir, cipher)
        store.write(canary.copyOf())
        val disk = store.file.readBytes()
        for (needle in listOf("zgcanaryinst", "7731", "ignore", "ZG_CANARY_SRC", "userSenders")) {
            assertFalse(needle, disk.containsSubsequence(needle.toByteArray(Charsets.UTF_8)))
            assertFalse(needle, disk.containsSubsequence(needle.toByteArray(Charsets.UTF_16LE)))
            assertFalse(needle, disk.containsSubsequence(needle.toByteArray(Charsets.UTF_16BE)))
        }
        // Nothing else was written in the directory.
        assertEquals(listOf("guard.user.enc"), dir.list()!!.toList())
    }

    @Test
    fun tamperedFileIsUnreadableAndKept() {
        val store = GuardUserConfigStore(dir, cipher)
        store.write(GuardFixtures.t1User)
        val data = store.file.readBytes()
        data[data.size - 1] = (data[data.size - 1].toInt() xor 1).toByte()
        store.file.writeBytes(data)
        assertTrue(store.read() === GuardUserConfigStore.Read.Unreadable)
        assertArrayEquals(data, store.file.readBytes())
        // Truncated and over-size files are proof too.
        store.file.writeBytes(ByteArray(10))
        assertTrue(store.read() === GuardUserConfigStore.Read.Unreadable)
        store.file.writeBytes(ByteArray(GuardUserConfigStore.MAX_FILE_BYTES + 1))
        assertTrue(store.read() === GuardUserConfigStore.Read.Unreadable)
        assertTrue(store.file.exists())
    }

    @Test
    fun ioAndKeystoreErrorsAreTransientNotProof() {
        val ops = FaultyFileOps()
        val flaky = FlakyGuardUserCipher()
        val store = GuardUserConfigStore(dir, flaky, ops)
        store.write(GuardFixtures.t1User)
        ops.failRead = true
        assertTrue(store.read() === GuardUserConfigStore.Read.Transient)
        ops.failRead = false
        flaky.failDecrypt = true
        assertTrue(store.read() === GuardUserConfigStore.Read.Transient)
        flaky.failDecrypt = false
        assertTrue(store.read() is GuardUserConfigStore.Read.Plain)
    }

    /** A failure at any write step leaves the old file byte-for-byte, and no tmp. */
    @Test
    fun failedWriteKeepsTheOldFile() {
        val ops = FaultyFileOps()
        val flaky = FlakyGuardUserCipher()
        val store = GuardUserConfigStore(dir, flaky, ops)
        store.write(GuardFixtures.t1User)
        val before = store.file.readBytes()
        val newer = GuardFixtures.bytes("configs/user_old_registry.json")
        val faults = listOf<Pair<String, () -> Unit>>(
            "encrypt" to { flaky.failEncrypt = true },
            "tmp write" to { ops.failWrite = true },
            "fsync" to { ops.failSyncOnly = true },
            "rename" to { ops.failRename = true },
        )
        for ((name, arm) in faults) {
            arm()
            try {
                store.write(newer)
                throw AssertionError("$name: write succeeded")
            } catch (e: GuardConfigWriteException) {
                assertEquals(GuardWriteError.IO_ERROR, e.error)
                assertEquals("IO_ERROR", e.message)
            }
            assertArrayEquals(name, before, store.file.readBytes())
            assertFalse(name, File(dir, "guard.user.enc.tmp").exists())
            flaky.failEncrypt = false
            ops.failWrite = false
            ops.failSyncOnly = false
            ops.failRename = false
        }
        store.write(newer)
        assertEquals(listOf("write", "rename", "syncDir"), ops.calls.takeLast(3))
        assertArrayEquals(newer, (store.read() as GuardUserConfigStore.Read.Plain).bytes)
    }

    @Test
    fun leftOverTmpIsIgnoredAndOverwritten() {
        val store = GuardUserConfigStore(dir, cipher)
        dir.mkdirs()
        File(dir, "guard.user.enc.tmp").writeBytes(ByteArray(100) { 7 })
        assertTrue(store.read() === GuardUserConfigStore.Read.Absent)
        store.write(GuardFixtures.t1User)
        assertFalse(File(dir, "guard.user.enc.tmp").exists())
        assertTrue(store.read() is GuardUserConfigStore.Read.Plain)
    }

    /** L-1: the user part lives under the no-backup directory (the device test checks the real Context dirs). */
    @Test
    fun pathIsUnderNoBackupDir() {
        val noBackup = File("/data/user/0/app.zaghlol/no_backup")
        val store = GuardUserConfigStore(GuardUserConfigStore.dirUnder(noBackup), cipher)
        assertEquals("/data/user/0/app.zaghlol/no_backup/guard/guard.user.enc", store.file.path)
    }
}
