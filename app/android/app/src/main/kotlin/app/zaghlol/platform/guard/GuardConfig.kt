package app.zaghlol.platform.guard

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.util.regex.PatternSyntaxException

/**
 * What went wrong reading a config part. Names are Dart's
 * `GuardConfigErrorCode` names verbatim (lower camel case on purpose), so a
 * diag code means the same on both sides.
 */
@Suppress("EnumEntryName", "ktlint:standard:enum-entry-name-case")
enum class GuardConfigErrorCode {
    tooLarge,
    invalidUtf8,
    invalidJson,
    wrongType,
    unknownKey,
    missingKey,
    badValue,
    badVersion,
    badRegex,
    tooMany,
}

/**
 * A config error: [code] and a JSON [path] built from fixed key names and
 * indexes only, never a value (the user part holds institution + last-4
 * pairs, which are financial data).
 */
class GuardConfigError(val code: GuardConfigErrorCode, val path: String) {
    override fun toString(): String = "GuardConfigError($code at $path)"
}

/** Thrown where a config error must leave the reader (writer validation). Message = `"$code at $path"`. */
class GuardConfigException(val code: GuardConfigErrorCode, val path: String) : RuntimeException("$code at $path") {
    override fun fillInStackTrace(): Throwable = this
}

/** Which parts of the config the Guard runs with. [wire] equals Dart's `GuardConfigMode.name`. */
enum class GuardConfigMode(val wire: String) {
    /** Base and user parts. */
    FULL("full"),

    /** Base only: user part absent (fresh install) or unusable (PO Q1). */
    BASE_ONLY("baseOnly"),

    /** Base part unusable: every message is dropped `config_invalid`. */
    INVALID("invalid"),
}

/** One ignore rule `(inst, last4|null, ch)`. `toString` prints no value. */
class GuardIgnoreKey(val inst: String, val last4: String?, val ch: GuardIgnoreChannel) {
    override fun equals(other: Any?): Boolean =
        other is GuardIgnoreKey && other.inst == inst && other.last4 == last4 && other.ch == ch

    override fun hashCode(): Int = (inst.hashCode() * 31 + (last4?.hashCode() ?: 0)) * 31 + ch.hashCode()

    override fun toString(): String = "GuardIgnoreKey"
}

/** A user sender `(channel wire, source key)`. `toString` prints no value. */
class GuardUserSender(val channel: String, val key: String) {
    override fun equals(other: Any?): Boolean = other is GuardUserSender && other.channel == channel && other.key == key

    override fun hashCode(): Int = channel.hashCode() * 31 + key.hashCode()

    override fun toString(): String = "GuardUserSender"
}

/**
 * A parsed, compiled Guard config; immutable. Kotlin port of
 * `packages/zaghlol_parsing/lib/guard/guard_config.dart`: same schema, caps,
 * error codes and modes (T-038 design note section 3). Patterns are compiled
 * with `Regex(p)`, no options (portable subset, platform-channels section 1.1).
 */
class GuardConfig internal constructor(
    val registryVersion: Int,
    /** Folded sender id to institution code. */
    internal val exactSenders: Map<String, String>,
    internal val senderRegexes: List<Pair<Regex, String>>,
    /** Trimmed (Dart set) package name to institution code. */
    internal val packages: Map<String, String>,
    /** Folded wallet card name and institution code, in file order. */
    internal val wallet: List<Pair<String, String>>,
    internal val globalDrop: List<Regex>,
    internal val dropByInst: Map<String, List<Regex>>,
    internal val last4ByInst: Map<String, List<Regex>>,
    internal val last4Any: List<Regex>,
    internal val senderHints: List<Regex>,
    internal val bodyHints: List<Regex>,
    internal val alwaysCapture: Set<String>,
    internal val shortcutKeywords: List<String>,
    val perSenderPerMin: Int,
    internal val ignore: Set<GuardIgnoreKey>,
    internal val userSenders: Set<GuardUserSender>,
) {
    internal fun withUser(user: UserPart): GuardConfig = GuardConfig(
        registryVersion, exactSenders, senderRegexes, packages, wallet, globalDrop, dropByInst,
        last4ByInst, last4Any, senderHints, bodyHints, alwaysCapture, shortcutKeywords, perSenderPerMin,
        user.ignore, user.senders,
    )

    override fun toString(): String = "GuardConfig"

    internal class UserPart(val ignore: Set<GuardIgnoreKey>, val senders: Set<GuardUserSender>)

    companion object {
        /** Base schema version (Dart `guardConfigVersion`). */
        const val BASE_VERSION = 4

        /** User schema version (Dart `guardUserConfigVersion`). */
        const val USER_VERSION = 1

        const val MAX_BASE_BYTES = 200 * 1024
        const val MAX_USER_BYTES = 64 * 1024
        const val MAX_IGNORE_RULES = 1000
        const val MAX_USER_SENDERS = 200
        const val MAX_BASE_LIST_LENGTH = 5000
        const val MAX_PATTERN_LENGTH = 600
        const val MAX_VALUE_LENGTH = 256

        /** Channels a user sender may name (Dart `guardUserSenderChannels`). */
        private val USER_SENDER_CHANNELS = setOf(
            GuardChannel.SMS, GuardChannel.NOTIFICATION, GuardChannel.SHORTCUT_MESSAGE, GuardChannel.APPLE_PAY,
        )

        /**
         * Parses the base part and the optional user part (raw bytes as read /
         * decrypted). Never throws (except a fatal VM error such as OOM).
         *
         * - base unusable -> [GuardConfigMode.INVALID];
         * - [user] null and not [userUnreadable] -> [GuardConfigMode.BASE_ONLY];
         * - user unusable ([userUnreadable]: the file failed authentication;
         *   or the bytes do not parse) -> per [GuardPolicy.USER_CONFIG_FAILURE]
         *   (PO Q1): `BASE_ONLY` with [GuardConfigLoad.userFailed], or `INVALID`.
         */
        fun parse(base: ByteArray, user: ByteArray?, userUnreadable: Boolean = false): GuardConfigLoad {
            val baseConfig: GuardConfig = try {
                parseBase(base)
            } catch (f: ConfigFailure) {
                return GuardConfigLoad(GuardConfigMode.INVALID, null, baseError = f.error)
            } catch (t: Throwable) {
                rethrowIfFatal(t)
                return GuardConfigLoad(GuardConfigMode.INVALID, null, baseError = GuardConfigError(GuardConfigErrorCode.badValue, "$"))
            }
            if (user == null && !userUnreadable) return GuardConfigLoad(GuardConfigMode.BASE_ONLY, baseConfig)
            var userError: GuardConfigError? = null
            if (user != null && !userUnreadable) {
                try {
                    return GuardConfigLoad(GuardConfigMode.FULL, baseConfig.withUser(parseUser(user)))
                } catch (f: ConfigFailure) {
                    userError = f.error
                } catch (t: Throwable) {
                    rethrowIfFatal(t)
                    userError = GuardConfigError(GuardConfigErrorCode.badValue, "$")
                }
            }
            return when (GuardPolicy.USER_CONFIG_FAILURE) {
                GuardUserConfigFailure.KEEP_WITH_BASE ->
                    GuardConfigLoad(GuardConfigMode.BASE_ONLY, baseConfig, userError = userError, userUnreadable = userUnreadable)
                GuardUserConfigFailure.DROP_ALL ->
                    GuardConfigLoad(GuardConfigMode.INVALID, null, userError = userError, userUnreadable = userUnreadable)
            }
        }

        /** Validates a user part on its own (the writer's check before anything is written). Null when valid. */
        fun validateUser(user: ByteArray): GuardConfigError? = try {
            parseUser(user)
            null
        } catch (f: ConfigFailure) {
            f.error
        } catch (t: Throwable) {
            rethrowIfFatal(t)
            GuardConfigError(GuardConfigErrorCode.badValue, "$")
        }

        /** The source key the Guard compares on [channel] (Dart `guardSourceKey`). */
        internal fun sourceKey(channel: GuardChannel, source: String): String =
            if (channel == GuardChannel.NOTIFICATION) TextFold.dartTrim(source) else TextFold.foldKey(source)

        private fun fail(code: GuardConfigErrorCode, path: String): Nothing = throw ConfigFailure(GuardConfigError(code, path))

        private fun decode(bytes: ByteArray, maxBytes: Int): Map<String, Any?> {
            if (bytes.size > maxBytes) fail(GuardConfigErrorCode.tooLarge, "$")
            var text: String = try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes))
                    .toString()
            } catch (e: CharacterCodingException) {
                fail(GuardConfigErrorCode.invalidUtf8, "$")
            }
            // Dart's Utf8Decoder drops one leading byte-order mark; Java's does not.
            if (text.isNotEmpty() && text[0] == '\uFEFF') text = text.substring(1)
            val json = try {
                StrictJson.parse(text)
            } catch (e: StrictJsonException) {
                fail(GuardConfigErrorCode.invalidJson, "$")
            }
            if (json !is Map<*, *>) fail(GuardConfigErrorCode.wrongType, "$")
            @Suppress("UNCHECKED_CAST")
            return json as Map<String, Any?>
        }

        private fun compile(text: String, path: String): Regex = try {
            Regex(text)
        } catch (e: PatternSyntaxException) {
            fail(GuardConfigErrorCode.badRegex, path)
        } catch (e: IllegalArgumentException) {
            fail(GuardConfigErrorCode.badRegex, path)
        }

        /** `^[a-z][a-z0-9_]{1,31}$` as a loop (no regex `$` semantics to worry about). */
        private fun isInstShape(v: String): Boolean {
            if (v.length < 2 || v.length > 32 || v[0] !in 'a'..'z') return false
            for (i in 1 until v.length) {
                val c = v[i]
                if (c !in 'a'..'z' && c !in '0'..'9' && c != '_') return false
            }
            return true
        }

        private fun isLast4Shape(v: String): Boolean = v.length == 4 && v.all { it in '0'..'9' }

        private fun inst(o: Obj, key: String): String {
            val v = o.string(key)
            if (!isInstShape(v)) fail(GuardConfigErrorCode.badValue, "${o.path}.$key")
            return v
        }

        private fun stringAt(v: Any?, path: String, maxLength: Int): String {
            if (v !is String) fail(GuardConfigErrorCode.wrongType, path)
            if (v.isEmpty() || v.length > maxLength) fail(GuardConfigErrorCode.badValue, path)
            return v
        }

        private fun objAt(v: Any?, path: String): Obj {
            if (v !is Map<*, *>) fail(GuardConfigErrorCode.wrongType, path)
            @Suppress("UNCHECKED_CAST")
            return Obj(path, v as Map<String, Any?>)
        }

        /** Strict object reader: every key must be read, unknown keys fail (Dart `_Obj`). */
        private class Obj(val path: String, val map: Map<String, Any?>) {
            private val read = HashSet<String>()

            fun get(key: String): Any? {
                read.add(key)
                if (!map.containsKey(key)) fail(GuardConfigErrorCode.missingKey, "$path.$key")
                return map[key]
            }

            fun integer(key: String, min: Long = 0, max: Long = 1L shl 30): Int {
                val v = get(key)
                if (v !is Long) fail(GuardConfigErrorCode.wrongType, "$path.$key")
                if (v < min || v > max) fail(GuardConfigErrorCode.badValue, "$path.$key")
                return v.toInt()
            }

            fun string(key: String, maxLength: Int = MAX_VALUE_LENGTH): String {
                val v = get(key)
                if (v !is String) fail(GuardConfigErrorCode.wrongType, "$path.$key")
                if (v.isEmpty() || v.length > maxLength) fail(GuardConfigErrorCode.badValue, "$path.$key")
                return v
            }

            fun nullableString(key: String): String? {
                val v = get(key) ?: return null
                if (v !is String) fail(GuardConfigErrorCode.wrongType, "$path.$key")
                return v
            }

            fun list(key: String, maxLength: Int): List<Any?> {
                val v = get(key)
                if (v !is List<*>) fail(GuardConfigErrorCode.wrongType, "$path.$key")
                if (v.size > maxLength) fail(GuardConfigErrorCode.tooMany, "$path.$key")
                return v
            }

            fun obj(key: String): Obj {
                val v = get(key)
                if (v !is Map<*, *>) fail(GuardConfigErrorCode.wrongType, "$path.$key")
                @Suppress("UNCHECKED_CAST")
                return Obj("$path.$key", v as Map<String, Any?>)
            }

            fun strings(key: String, maxLength: Int = MAX_VALUE_LENGTH): List<String> {
                val raw = list(key, MAX_BASE_LIST_LENGTH)
                return raw.mapIndexed { i, v -> stringAt(v, "$path.$key[$i]", maxLength) }
            }

            fun patterns(key: String): List<Regex> {
                val texts = strings(key, MAX_PATTERN_LENGTH)
                return texts.mapIndexed { i, t -> compile(t, "$path.$key[$i]") }
            }

            fun finish() {
                for (key in map.keys) {
                    // The key name itself is not echoed: it may be anything.
                    if (key !in read) fail(GuardConfigErrorCode.unknownKey, path)
                }
            }
        }

        private fun parseBase(bytes: ByteArray): GuardConfig {
            val r = Obj("$", decode(bytes, MAX_BASE_BYTES))
            if (r.integer("v") != BASE_VERSION) fail(GuardConfigErrorCode.badVersion, "$.v")
            val registryVersion = r.integer("registryVersion")

            val exact = LinkedHashMap<String, String>()
            val regexes = ArrayList<Pair<Regex, String>>()
            val senders = r.list("senders", MAX_BASE_LIST_LENGTH)
            for (i in senders.indices) {
                val o = objAt(senders[i], "$.senders[$i]")
                val match = o.string("match")
                val inst = inst(o, "inst")
                when (match) {
                    "exact" -> {
                        val key = TextFold.foldKey(o.string("value"))
                        if (key.isEmpty()) fail(GuardConfigErrorCode.badValue, "${o.path}.value")
                        exact.putIfAbsent(key, inst)
                    }
                    "regex" -> {
                        val text = o.string("value", MAX_PATTERN_LENGTH)
                        regexes.add(compile(text, "${o.path}.value") to inst)
                    }
                    else -> fail(GuardConfigErrorCode.badValue, "${o.path}.match")
                }
                o.finish()
            }

            val packages = LinkedHashMap<String, String>()
            val pkgs = r.list("packages", MAX_BASE_LIST_LENGTH)
            for (i in pkgs.indices) {
                val o = objAt(pkgs[i], "$.packages[$i]")
                val key = TextFold.dartTrim(o.string("value"))
                // Dart `putIfAbsent(key, () => _inst(o, 'inst'))`: for a duplicate
                // package `inst` is never read, so `finish()` fails with
                // `unknownKey` and the whole base is invalid. Mirrored for parity.
                if (!packages.containsKey(key)) packages[key] = inst(o, "inst")
                o.finish()
            }

            val wallet = ArrayList<Pair<String, String>>()
            val cards = r.list("wallet", MAX_BASE_LIST_LENGTH)
            for (i in cards.indices) {
                val o = objAt(cards[i], "$.wallet[$i]")
                val name = TextFold.foldKey(o.string("name"))
                if (name.isEmpty()) fail(GuardConfigErrorCode.badValue, "${o.path}.name")
                wallet.add(name to inst(o, "inst"))
                o.finish()
            }

            val drop = r.obj("drop")
            val globalDrop = drop.patterns("global")
            val byInstObj = drop.obj("byInst")
            val dropByInst = LinkedHashMap<String, List<Regex>>()
            for (key in byInstObj.map.keys.toList()) {
                if (!isInstShape(key)) fail(GuardConfigErrorCode.badValue, byInstObj.path)
                dropByInst[key] = byInstObj.patterns(key)
            }
            byInstObj.finish()
            drop.finish()

            val last4Obj = r.obj("last4")
            val last4ByInst = LinkedHashMap<String, List<Regex>>()
            var last4Any: List<Regex> = emptyList()
            for (key in last4Obj.map.keys.toList()) {
                when {
                    key == "*" -> last4Any = last4Obj.patterns(key)
                    isInstShape(key) -> last4ByInst[key] = last4Obj.patterns(key)
                    else -> fail(GuardConfigErrorCode.badValue, last4Obj.path)
                }
            }
            last4Obj.finish()

            val generic = r.obj("generic")
            val senderHints = generic.patterns("senderHints")
            val bodyHints = generic.patterns("bodyHints")
            val always = LinkedHashSet<String>()
            for (a in generic.strings("alwaysCapture")) always.add(TextFold.foldKey(a))
            always.remove("")
            generic.finish()

            val keywords = r.strings("shortcutKeywords")
            val rate = r.obj("rate")
            val perMin = rate.integer("perSenderPerMin", min = 1, max = 10000)
            rate.finish()
            r.finish()

            return GuardConfig(
                registryVersion = registryVersion,
                exactSenders = exact,
                senderRegexes = regexes,
                packages = packages,
                wallet = wallet,
                globalDrop = globalDrop,
                dropByInst = dropByInst,
                last4ByInst = last4ByInst,
                last4Any = last4Any,
                senderHints = senderHints,
                bodyHints = bodyHints,
                alwaysCapture = always,
                shortcutKeywords = keywords,
                perSenderPerMin = perMin,
                ignore = emptySet(),
                userSenders = emptySet(),
            )
        }

        private fun parseUser(bytes: ByteArray): UserPart {
            val r = Obj("$", decode(bytes, MAX_USER_BYTES))
            if (r.integer("v") != USER_VERSION) fail(GuardConfigErrorCode.badVersion, "$.v")
            r.integer("baseRegistryVersion")
            val ignore = LinkedHashSet<GuardIgnoreKey>()
            val rules = r.list("ignore", MAX_IGNORE_RULES)
            for (i in rules.indices) {
                val o = objAt(rules[i], "$.ignore[$i]")
                val inst = inst(o, "inst")
                val last4 = o.nullableString("last4")
                if (last4 != null && !isLast4Shape(last4)) fail(GuardConfigErrorCode.badValue, "${o.path}.last4")
                val ch = GuardIgnoreChannel.fromWire(o.string("ch")) ?: fail(GuardConfigErrorCode.badValue, "${o.path}.ch")
                o.finish()
                ignore.add(GuardIgnoreKey(inst, last4, ch))
            }
            val senders = LinkedHashSet<GuardUserSender>()
            val list = r.list("userSenders", MAX_USER_SENDERS)
            for (i in list.indices) {
                val o = objAt(list[i], "$.userSenders[$i]")
                val value = o.string("value")
                val ch = GuardChannel.fromWire(o.string("ch"))
                if (ch == null || ch !in USER_SENDER_CHANNELS) fail(GuardConfigErrorCode.badValue, "${o.path}.ch")
                o.finish()
                val key = sourceKey(ch, value)
                if (key.isEmpty()) fail(GuardConfigErrorCode.badValue, "${o.path}.value")
                senders.add(GuardUserSender(ch.wire, key))
            }
            r.finish()
            return UserPart(ignore, senders)
        }
    }
}

/** The outcome of [GuardConfig.parse]. `toString` prints the mode and error codes only. */
class GuardConfigLoad(
    val mode: GuardConfigMode,
    /** Null exactly when [mode] is [GuardConfigMode.INVALID]. */
    val config: GuardConfig?,
    val baseError: GuardConfigError? = null,
    /** Set when user bytes were given but did not parse. */
    val userError: GuardConfigError? = null,
    /** The user file failed authentication (caller-reported). */
    val userUnreadable: Boolean = false,
) {
    /** A user part was present but can not be used (diag `CONFIG_INVALID`; Dart `userError != null`). */
    val userFailed: Boolean get() = userError != null || userUnreadable

    override fun toString(): String = "GuardConfigLoad(${mode.wire}, base=${baseError?.code}, user=${userError?.code}, unreadable=$userUnreadable)"
}

/** Internal control flow: an error code and a JSON path, never content. */
private class ConfigFailure(val error: GuardConfigError) : RuntimeException("GUARD_CONFIG_INVALID") {
    override fun fillInStackTrace(): Throwable = this
}

/** Rethrows VM errors a total function must not swallow (OOM and the like); a [StackOverflowError] is not one of them. */
internal fun rethrowIfFatal(t: Throwable) {
    if (t is VirtualMachineError && t !is StackOverflowError) throw t
}
