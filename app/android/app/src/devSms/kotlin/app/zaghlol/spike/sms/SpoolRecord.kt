package app.zaghlol.spike.sms

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/**
 * The plaintext of one spool entry (platform-channels.md section 1.3 as
 * amended by T-008: a versioned binary record instead of CBOR). Never
 * printed: [toString] is redacted.
 */
class SpoolRecord(
    val channel: String,
    val source: String,
    val body: String,
    val receivedAtMs: Long,
    val simSlot: Int?,
    val guardInst: String?,
    val guardLast4: String?,
    /** Spike only: receive stamp on the monotonic clock (t0). */
    val rxElapsedNs: Long,
    /** Spike only: `Settings.Global.BOOT_COUNT` at receive; -1 unknown. */
    val bootCount: Int,
) {
    override fun toString(): String = "SpoolRecord(<redacted>)"
}

/** The bytes are not a record this code wrote: proof for delete-on-proof. */
class SpoolFormatException : Exception("SPOOL_FORMAT")

/**
 * Layout (big-endian, `DataOutputStream`):
 * `u8 v=1 | str8 channel | str16 source | u32 len + UTF-8 body | i64 receivedAtMs |
 *  i32 simSlot (-1 = none) | opt8 guardInst | opt8 guardLast4 | i64 rxElapsedNs | i32 bootCount`.
 * `strN` = unsigned length of N bits + UTF-8; `opt8` = u8 present flag + str8.
 * Decoding is strict: unknown version, over-long field, invalid UTF-8 or
 * trailing bytes all throw [SpoolFormatException].
 */
object SpoolRecordCodec {
    const val VERSION = 1
    const val MAX_CHANNEL_BYTES = 32
    const val MAX_SOURCE_BYTES = 256
    const val MAX_BODY_CHARS = 4_000 // maxParseBodyLength (T-033)
    const val MAX_BODY_BYTES = 16_000
    const val MAX_SHORT_BYTES = 64

    /** Upper bound of an encoded record; anything larger is not ours. */
    const val MAX_RECORD_BYTES = 1 + 1 + MAX_CHANNEL_BYTES + 2 + MAX_SOURCE_BYTES + 4 + MAX_BODY_BYTES +
        8 + 4 + 2 * (2 + MAX_SHORT_BYTES) + 8 + 4

    fun encode(r: SpoolRecord): ByteArray {
        val bos = ByteArrayOutputStream(64 + r.body.length * 2)
        DataOutputStream(bos).use { out ->
            out.writeByte(VERSION)
            writeStr(out, r.channel, MAX_CHANNEL_BYTES, 8)
            writeStr(out, r.source, MAX_SOURCE_BYTES, 16)
            val body = r.body.toByteArray(Charsets.UTF_8)
            require(r.body.length <= MAX_BODY_CHARS && body.size <= MAX_BODY_BYTES) { "BODY_TOO_LONG" }
            out.writeInt(body.size)
            out.write(body)
            body.fill(0)
            out.writeLong(r.receivedAtMs)
            out.writeInt(r.simSlot ?: -1)
            writeOpt(out, r.guardInst)
            writeOpt(out, r.guardLast4)
            out.writeLong(r.rxElapsedNs)
            out.writeInt(r.bootCount)
        }
        return bos.toByteArray()
    }

    fun decode(bytes: ByteArray): SpoolRecord {
        if (bytes.size > MAX_RECORD_BYTES) throw SpoolFormatException()
        try {
            DataInputStream(ByteArrayInputStream(bytes)).use { input ->
                if (input.readUnsignedByte() != VERSION) throw SpoolFormatException()
                val channel = readStr(input, input.readUnsignedByte(), MAX_CHANNEL_BYTES)
                val source = readStr(input, input.readUnsignedShort(), MAX_SOURCE_BYTES)
                val bodyLen = input.readInt()
                if (bodyLen < 0 || bodyLen > MAX_BODY_BYTES) throw SpoolFormatException()
                val body = readStr(input, bodyLen, MAX_BODY_BYTES)
                if (body.length > MAX_BODY_CHARS) throw SpoolFormatException()
                val receivedAt = input.readLong()
                val slot = input.readInt()
                if (slot < -1) throw SpoolFormatException()
                val inst = readOpt(input)
                val last4 = readOpt(input)
                val rx = input.readLong()
                val boot = input.readInt()
                if (input.read() != -1) throw SpoolFormatException() // trailing bytes
                if (channel.isEmpty() || source.isEmpty()) throw SpoolFormatException()
                return SpoolRecord(channel, source, body, receivedAt, if (slot == -1) null else slot, inst, last4, rx, boot)
            }
        } catch (_: EOFException) {
            throw SpoolFormatException()
        }
    }

    private fun writeStr(out: DataOutputStream, s: String, max: Int, lenBits: Int) {
        val b = s.toByteArray(Charsets.UTF_8)
        require(b.size <= max) { "FIELD_TOO_LONG" }
        if (lenBits == 8) out.writeByte(b.size) else out.writeShort(b.size)
        out.write(b)
    }

    private fun writeOpt(out: DataOutputStream, s: String?) {
        if (s == null) {
            out.writeByte(0)
        } else {
            out.writeByte(1)
            writeStr(out, s, MAX_SHORT_BYTES, 8)
        }
    }

    private fun readOpt(input: DataInputStream): String? =
        when (input.readUnsignedByte()) {
            0 -> null
            1 -> readStr(input, input.readUnsignedByte(), MAX_SHORT_BYTES)
            else -> throw SpoolFormatException()
        }

    private fun readStr(input: DataInputStream, len: Int, max: Int): String {
        if (len > max) throw SpoolFormatException()
        val b = ByteArray(len)
        input.readFully(b)
        try {
            return Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(b))
                .toString()
        } catch (_: CharacterCodingException) {
            throw SpoolFormatException()
        } finally {
            b.fill(0)
        }
    }
}
