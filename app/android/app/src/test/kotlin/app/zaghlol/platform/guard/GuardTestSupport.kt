package app.zaghlol.platform.guard

import java.io.File
import java.io.IOException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * The shared fixture directory, read in place: Gradle passes
 * `-Dzaghlol.guardFixtures=<repo>/packages/zaghlol_parsing/test/fixtures/guard`
 * (build.gradle.kts). Never copied into this module.
 */
internal object GuardFixtures {
    val dir: File by lazy {
        val path = System.getProperty("zaghlol.guardFixtures")
            ?: error("system property zaghlol.guardFixtures is not set (build.gradle.kts)")
        File(path).also { check(File(it, "golden.json").isFile) { "golden.json not found in the fixture dir" } }
    }

    fun bytes(relative: String): ByteArray = File(dir, relative).readBytes()

    val t1Base: ByteArray get() = bytes("configs/t1_base.json")
    val t1User: ByteArray get() = bytes("configs/t1_user.json")

    fun runner(): GuardGoldenRunner = GuardGoldenRunner(::bytes)
}

/** Software AES-256-GCM with the same format as [KeystoreGuardUserCipher]. Test key only. */
internal open class SoftwareGuardUserCipher(keyBytes: ByteArray = ByteArray(32) { it.toByte() }) : GuardUserCipher {
    private val key = SecretKeySpec(keyBytes, "AES")
    private val random = java.security.SecureRandom()

    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        val iv = ByteArray(GuardUserCipher.NONCE_BYTES).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        return iv + cipher.doFinal(plain)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (data.size < GuardUserCipher.NONCE_BYTES + GuardUserCipher.TAG_BYTES) throw AEADBadTagException("truncated")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, data, 0, GuardUserCipher.NONCE_BYTES))
        cipher.updateAAD(aad)
        return cipher.doFinal(data, GuardUserCipher.NONCE_BYTES, data.size - GuardUserCipher.NONCE_BYTES)
    }
}

/** Fails encrypt/decrypt with a Keystore-style (non-authentication) error while [failing] is set. */
internal class FlakyGuardUserCipher : SoftwareGuardUserCipher() {
    var failEncrypt = false
    var failDecrypt = false

    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        if (failEncrypt) throw java.security.ProviderException("keystore busy")
        return super.encrypt(plain, aad)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (failDecrypt) throw java.security.ProviderException("keystore busy")
        return super.decrypt(data, aad)
    }
}

/** [DefaultGuardFileOps] with a fault switch per step. */
internal class FaultyFileOps : GuardFileOps {
    private val real = DefaultGuardFileOps()
    var failRead = false
    var failWrite = false
    var failSyncOnly = false
    var failRename = false
    val calls = ArrayList<String>()

    override fun readBounded(file: File, max: Int): ByteArray? {
        calls.add("read")
        if (failRead) throw IOException("injected read failure")
        return real.readBounded(file, max)
    }

    override fun ensureDir(dir: File) = real.ensureDir(dir)

    override fun writeAndSync(file: File, data: ByteArray) {
        calls.add("write")
        if (failWrite) throw IOException("injected write failure")
        if (failSyncOnly) {
            // Data reaches the tmp, then fsync fails.
            file.writeBytes(data)
            throw IOException("injected fsync failure")
        }
        real.writeAndSync(file, data)
    }

    override fun atomicReplace(from: File, to: File) {
        calls.add("rename")
        if (failRename) throw IOException("injected rename failure")
        real.atomicReplace(from, to)
    }

    override fun syncDir(dir: File) {
        calls.add("syncDir")
        real.syncDir(dir)
    }

    override fun delete(file: File) {
        calls.add("delete")
        real.delete(file)
    }
}

internal fun tempDir(): File = kotlin.io.path.createTempDirectory("guard-test").toFile().apply { deleteOnExit() }

internal fun ByteArray.containsSubsequence(needle: ByteArray): Boolean {
    if (needle.isEmpty()) return true
    outer@ for (i in 0..size - needle.size) {
        for (j in needle.indices) if (this[i + j] != needle[j]) continue@outer
        return true
    }
    return false
}

internal fun decision(d: GuardDecision): Map<String, Any?> = GuardGoldenRunner.describe(d)

/** Minimal JSON writer for test configs (maps, lists, strings, numbers, booleans, null). */
internal fun toJson(v: Any?): String = when (v) {
    null -> "null"
    is String -> buildString {
        append('"')
        for (c in v) {
            when {
                c == '"' -> append("\\\"")
                c == '\\' -> append("\\\\")
                c.code < 0x20 -> append("\\u%04x".format(c.code))
                else -> append(c)
            }
        }
        append('"')
    }
    is Map<*, *> -> v.entries.joinToString(",", "{", "}") { toJson(it.key as String) + ":" + toJson(it.value) }
    is List<*> -> v.joinToString(",", "[", "]") { toJson(it) }
    else -> v.toString()
}

/** A mutable deep copy of a JSON config file, for building variants. */
@Suppress("UNCHECKED_CAST")
internal fun jsonOf(bytes: ByteArray): MutableMap<String, Any?> = deepCopy(StrictJson.parse(String(bytes, Charsets.UTF_8))) as MutableMap<String, Any?>

private fun deepCopy(v: Any?): Any? = when (v) {
    is Map<*, *> -> LinkedHashMap<String, Any?>().apply { v.forEach { (k, x) -> put(k as String, deepCopy(x)) } }
    is List<*> -> ArrayList<Any?>().apply { v.forEach { add(deepCopy(it)) } }
    else -> v
}

@Suppress("UNCHECKED_CAST")
internal fun MutableMap<String, Any?>.obj(key: String): MutableMap<String, Any?> = this[key] as MutableMap<String, Any?>

@Suppress("UNCHECKED_CAST")
internal fun MutableMap<String, Any?>.arr(key: String): MutableList<Any?> = this[key] as MutableList<Any?>

internal fun Map<String, Any?>.bytes(): ByteArray = toJson(this).toByteArray(Charsets.UTF_8)
