package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** The config reader (T-038 design note section 3): one test per error code, caps, modes, fuzz (AC2). */
class GuardConfigReaderTest {
    private val base get() = GuardFixtures.t1Base
    private val user get() = GuardFixtures.t1User

    private fun baseError(bytes: ByteArray): GuardConfigError {
        val load = GuardConfig.parse(bytes, null)
        assertEquals(GuardConfigMode.INVALID, load.mode)
        assertNull(load.config)
        return load.baseError ?: throw AssertionError("no base error")
    }

    private fun userError(bytes: ByteArray): GuardConfigError {
        val load = GuardConfig.parse(base, bytes)
        // PO Q1 (provisional): an unusable user part keeps the base rules.
        assertEquals(GuardConfigMode.BASE_ONLY, load.mode)
        assertNotNull(load.config)
        assertTrue(load.userFailed)
        return load.userError ?: throw AssertionError("no user error")
    }

    private fun baseWith(edit: MutableMap<String, Any?>.() -> Unit): ByteArray = jsonOf(base).apply(edit).bytes()
    private fun userWith(edit: MutableMap<String, Any?>.() -> Unit): ByteArray = jsonOf(user).apply(edit).bytes()

    @Test
    fun validPartsLoadFullAndBaseAloneIsBaseOnly() {
        assertEquals(GuardConfigMode.FULL, GuardConfig.parse(base, user).mode)
        val alone = GuardConfig.parse(base, null)
        assertEquals(GuardConfigMode.BASE_ONLY, alone.mode)
        assertFalse(alone.userFailed)
        assertEquals(20, alone.config!!.perSenderPerMin)
    }

    @Test
    fun tooLargeIsCheckedBeforeDecoding() {
        val big = ByteArray(GuardConfig.MAX_BASE_BYTES + 1) { 0xFF.toByte() }
        assertEquals(GuardConfigErrorCode.tooLarge, baseError(big).code)
        assertEquals(GuardConfigErrorCode.tooLarge, userError(ByteArray(GuardConfig.MAX_USER_BYTES + 1) { 0xFF.toByte() }).code)
    }

    @Test
    fun invalidUtf8() {
        listOf(byteArrayOf(0x7B, 0xC3.toByte(), 0x7D), byteArrayOf(0xC0.toByte(), 0xAF.toByte()), byteArrayOf(0xED.toByte(), 0xA0.toByte(), 0x80.toByte()))
            .forEach { assertEquals(GuardConfigErrorCode.invalidUtf8, baseError(it).code) }
        assertEquals(GuardConfigErrorCode.invalidUtf8, baseError(GuardFixtures.bytes("configs/base_not_utf8.json")).code)
    }

    @Test
    fun oneLeadingByteOrderMarkIsDroppedLikeDart() {
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        assertEquals(GuardConfigMode.FULL, GuardConfig.parse(base, bom + user).mode)
        assertEquals(GuardConfigErrorCode.invalidJson, userError(bom + bom + user).code)
    }

    @Test
    fun invalidJsonAndWrongTopLevelType() {
        assertEquals(GuardConfigErrorCode.invalidJson, baseError("{\"v\":4,}".toByteArray()).code)
        assertEquals(GuardConfigErrorCode.wrongType, baseError("[]".toByteArray()).code)
    }

    @Test
    fun wrongType() {
        assertEquals(GuardConfigErrorCode.wrongType, baseError(baseWith { put("v", 4.0) }).code)
        assertEquals(GuardConfigErrorCode.wrongType, baseError(baseWith { put("senders", mapOf<String, Any?>()) }).code)
        assertEquals(GuardConfigErrorCode.wrongType, userError(userWith { put("v", "1") }).code)
    }

    @Test
    fun unknownKeyNeverEchoesTheKey() {
        val e = baseError(baseWith { put("ZG_CANARY_KEY", 1) })
        assertEquals(GuardConfigErrorCode.unknownKey, e.code)
        assertEquals("$", e.path)
        assertEquals(GuardConfigErrorCode.unknownKey, userError(GuardFixtures.bytes("configs/user_unknown_key.json")).code)
    }

    @Test
    fun missingKey() {
        assertEquals(GuardConfigErrorCode.missingKey, baseError(GuardFixtures.bytes("configs/base_missing_rate.json")).code)
        val e = userError(userWith { arr("ignore").let { (it[0] as MutableMap<String, Any?>).remove("inst") } })
        assertEquals(GuardConfigErrorCode.missingKey, e.code)
        assertEquals("$.ignore[0].inst", e.path)
    }

    @Test
    fun badValue() {
        assertEquals(GuardConfigErrorCode.badValue, baseError(baseWith { obj("rate")["perSenderPerMin"] = 0L }).code)
        // Empty and over-long strings, and a bad institution shape.
        assertEquals(GuardConfigErrorCode.badValue, baseError(baseWith { arr("shortcutKeywords").add("") }).code)
        assertEquals(GuardConfigErrorCode.badValue, baseError(baseWith { arr("shortcutKeywords").add("x".repeat(257)) }).code)
        assertEquals(GuardConfigErrorCode.badValue, userError(GuardFixtures.bytes("configs/user_indic_last4.json")).code)
        assertEquals(GuardConfigErrorCode.badValue, userError(userWith { (arr("ignore")[0] as MutableMap<String, Any?>)["inst"] = "NBE" }).code)
        assertEquals(GuardConfigErrorCode.badValue, userError(userWith { (arr("userSenders")[0] as MutableMap<String, Any?>)["ch"] = "share" }).code)
        // A pattern over 600 UTF-16 units.
        assertEquals(GuardConfigErrorCode.badValue, baseError(baseWith { obj("drop").arr("global").add("a".repeat(601)) }).code)
        GuardConfig.parse(baseWith { obj("drop").arr("global").add("a".repeat(600)) }, null).also { assertEquals(GuardConfigMode.BASE_ONLY, it.mode) }
    }

    @Test
    fun badVersion() {
        assertEquals(GuardConfigErrorCode.badVersion, baseError(GuardFixtures.bytes("configs/base_v3.json")).code)
        assertEquals(GuardConfigErrorCode.badVersion, userError(GuardFixtures.bytes("configs/user_v2.json")).code)
    }

    @Test
    fun badRegex() {
        assertEquals(GuardConfigErrorCode.badRegex, baseError(GuardFixtures.bytes("configs/base_bad_regex.json")).code)
        assertEquals(GuardConfigErrorCode.badRegex, baseError(baseWith { obj("generic").arr("bodyHints").add("([0-9]") }).code)
    }

    @Test
    fun tooManyAtEachCap() {
        val rule = mapOf("inst" to "nbe", "last4" to null, "ch" to "sms")
        assertEquals(GuardConfigErrorCode.tooMany, userError(userWith { put("ignore", List(1001) { rule }) }).code)
        assertEquals(GuardConfigMode.FULL, GuardConfig.parse(base, userWith { put("ignore", List(1000) { rule }) }).mode)
        val sender = mapOf("value" to "abc", "ch" to "sms")
        assertEquals(GuardConfigErrorCode.tooMany, userError(userWith { put("userSenders", List(201) { sender }) }).code)
        assertEquals(GuardConfigErrorCode.tooMany, baseError(baseWith { put("shortcutKeywords", List(5001) { "k" }) }).code)
    }

    @Test
    fun ruleWithoutInstitutionIsRejected() {
        // EC-59: last-4 alone can never be a rule.
        val e = userError(GuardFixtures.bytes("configs/user_last4_only.json"))
        assertTrue(e.code == GuardConfigErrorCode.missingKey || e.code == GuardConfigErrorCode.wrongType)
    }

    /** Dart parity for a quirk of `putIfAbsent`: a duplicate package leaves `inst` unread, so the base is invalid. */
    @Test
    fun duplicatePackageMakesTheBaseInvalidLikeDart() {
        val e = baseError(baseWith { arr("packages").add(mapOf("value" to "com.example.nbe", "inst" to "cib")) })
        assertEquals(GuardConfigErrorCode.unknownKey, e.code)
        assertEquals("$.packages[3]", e.path)
        // A duplicate exact sender is fine: the first wins.
        val dup = GuardConfig.parse(baseWith { arr("senders").add(mapOf("match" to "exact", "value" to "NBE", "inst" to "cib")) }, null)
        assertEquals(GuardConfigMode.BASE_ONLY, dup.mode)
        assertEquals("nbe", dup.config!!.exactSenders["nbe"])
    }

    @Test
    fun unreadableUserFileIsBaseOnlyWithTheFailureFlag() {
        val load = GuardConfig.parse(base, null, userUnreadable = true)
        assertEquals(GuardConfigMode.BASE_ONLY, load.mode)
        assertTrue(load.userFailed)
        assertNull(load.userError)
        // Registry senders still kept (AC2).
        val keep = CaptureGuard(load.config).decide("sms", "NBE", "Purchase EGP 10.00 card **4567")
        assertEquals("keep", decision(keep)["decision"])
    }

    @Test
    fun validateUserMatchesParse() {
        assertNull(GuardConfig.validateUser(user))
        assertEquals(GuardConfigErrorCode.badVersion, GuardConfig.validateUser(GuardFixtures.bytes("configs/user_v2.json"))!!.code)
    }

    /** AC2: 2,000 seeded user mutations and 300 truncated or random bases never throw, and a bad user part never yields `invalid`. */
    @Test
    fun mutationFuzzNeverThrowsAndABadUserPartNeverYieldsInvalid() {
        val rnd = Random(20261111)
        val userBytes = user
        repeat(2000) {
            val m = userBytes.copyOf()
            repeat(rnd.nextInt(1, 6)) {
                when (rnd.nextInt(4)) {
                    0 -> m[rnd.nextInt(m.size)] = rnd.nextInt(256).toByte()
                    1 -> m[rnd.nextInt(m.size)] = "{}[]\",:0n\\".random(rnd).code.toByte()
                    else -> m[rnd.nextInt(m.size)] = (m[rnd.nextInt(m.size)])
                }
            }
            val cut = if (rnd.nextInt(5) == 0) m.copyOf(rnd.nextInt(m.size)) else m
            val load = GuardConfig.parse(base, cut)
            assertTrue(load.mode != GuardConfigMode.INVALID)
            assertNotNull(load.config)
            if (load.mode == GuardConfigMode.BASE_ONLY) assertTrue(load.userFailed)
        }
        val baseBytes = base
        repeat(300) { i ->
            val b = if (i % 3 == 0) ByteArray(rnd.nextInt(1, 4096)) { rnd.nextInt(256).toByte() } else baseBytes.copyOf(rnd.nextInt(baseBytes.size - 1))
            val load = GuardConfig.parse(b, userBytes)
            assertEquals(GuardConfigMode.INVALID, load.mode)
            assertEquals(mapOf("decision" to "drop", "reason" to "config_invalid"), decision(CaptureGuard(load.config).decide("sms", "NBE", "Purchase EGP 10.00")))
        }
    }
}
