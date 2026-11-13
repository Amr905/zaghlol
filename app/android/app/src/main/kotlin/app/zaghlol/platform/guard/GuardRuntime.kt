package app.zaghlol.platform.guard

import android.content.Context
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.util.concurrent.atomic.AtomicReference

/** State of the user part as the runtime last saw it (surfaced to Dart via T-039 `getSpoolStatus().guardState`). */
enum class GuardUserState {
    /** No user file (fresh install). */
    ABSENT,

    /** Decrypted and parsed. */
    OK,

    /** Proven unusable (authentication failure, malformed, unknown version); kept until the next successful write. */
    UNREADABLE,

    /** I/O or Keystore error this time; retried on the next message. */
    RETRY,
}

/** The rules one message is decided with. Immutable; `toString` prints mode and state only. */
class GuardSnapshot(val guard: CaptureGuard, val mode: GuardConfigMode, val userState: GuardUserState) {
    override fun toString(): String = "GuardSnapshot(${mode.wire}, $userState)"
}

/**
 * The process-wide Guard (T-038 design note sections 4 to 6): lazily loads
 * the bundled base part and the encrypted user part, decides messages with
 * the per-process [SenderRateLimiter], and replaces the user part.
 *
 * Concurrency: readers take the immutable [GuardSnapshot] reference once per
 * message (no lock on the hot path); the first load and [writeUser] are
 * serialized by one lock, and a write publishes a new snapshot atomically, so
 * a message decided during a write uses the old or the new rules, never a mix.
 * All capture components run in the app's default process (as for SpoolKey).
 *
 * Caching (section 4): a valid base with an absent, valid or proven-unreadable
 * user part is cached; an invalid base (build defect, or a transient
 * `AssetManager` error) and a transient user-file error are not, so the next
 * message retries.
 */
class GuardRuntime(
    private val loadBase: () -> ByteArray,
    private val store: GuardUserConfigStore,
    private val clockMs: () -> Long,
    /** [GuardConfig.parse]; a seam so a test can count parses (T-038 security L-2). */
    private val parse: (base: ByteArray, user: ByteArray?, userUnreadable: Boolean) -> GuardConfigLoad =
        { base, user, unreadable -> GuardConfig.parse(base, user, userUnreadable = unreadable) },
) {
    private val lock = Any()
    private val snapshot = AtomicReference<GuardSnapshot?>(null)

    /** Bytes of the last base that parsed (public registry data). Guarded by [lock]. */
    private var validBase: ByteArray? = null

    /**
     * The compiled base-only rules of [validBase] (T-038 security L-2, T-040
     * design note section 5): a transient user-file error is not cached as a
     * snapshot (the next message retries the file), but it reuses these
     * instead of parsing and compiling the base again per message. Guarded
     * by [lock].
     */
    private var baseOnly: GuardConfigLoad? = null

    @Volatile
    private var limiter: SenderRateLimiter? = null

    /** The rules to use now. Never throws (except a fatal VM error). */
    fun current(): GuardSnapshot {
        snapshot.get()?.let { return it }
        synchronized(lock) {
            snapshot.get()?.let { return it }
            return try {
                load()
            } catch (t: Throwable) {
                rethrowIfFatal(t)
                INVALID_SNAPSHOT
            }
        }
    }

    /** Mode and user state now (loads on first use). */
    fun state(): GuardSnapshot = current()

    /**
     * Guard decision plus the per-process rate limit (applied to keeps only).
     * Never throws. Typed (FU-101 L-1): only the Android capture channels
     * reach the native Guard.
     */
    fun decide(channel: AndroidGuardChannel, source: String, body: String): GuardDecision {
        val snap = current()
        val decision = snap.guard.decide(channel.wire, source, body)
        val cfg = snap.guard.config ?: return decision
        return limiterFor(cfg.perSenderPerMin).apply(decision, channel.wire, source, clockMs())
    }

    /**
     * T-043 (FR-ING-A-03): may the listener read the extras of a notification
     * posted by [packageName]? Only a registry package or a user sender on the
     * `notification` channel; an invalid base admits nothing. A package that
     * would only pass the generic sender-hint path is **not** admitted
     * (notifications never take it, package names are trivially chosen).
     * Never throws; reads no notification content.
     */
    fun admitsNotificationPackage(packageName: String): Boolean {
        val kind = current().guard.senderKind(AndroidGuardChannel.NOTIFICATION.wire, packageName)
        return kind == GuardKeepKind.REGISTRY || kind == GuardKeepKind.USER
    }

    /**
     * Replaces the user part (host `writeGuardConfig`, wired by T-040). Under
     * the runtime lock: size and full reader validation **before** anything
     * is written; then encrypt + tmp + fsync + rename; then the new snapshot
     * is published. On any failure the previous file and snapshot stay in
     * force. [json] is zeroed before returning, in every case.
     *
     * @throws GuardConfigWriteException `CONFIG_INVALID` or `IO_ERROR`.
     */
    fun writeUser(json: ByteArray) {
        try {
            synchronized(lock) {
                if (json.size > GuardConfig.MAX_USER_BYTES) {
                    throw GuardConfigWriteException(
                        GuardWriteError.CONFIG_INVALID,
                        GuardConfigError(GuardConfigErrorCode.tooLarge, "$"),
                    )
                }
                GuardConfig.validateUser(json)?.let { throw GuardConfigWriteException(GuardWriteError.CONFIG_INVALID, it) }
                store.write(json)
                val base = validBase
                if (base == null) {
                    // Base not loaded yet (or invalid): the next message loads both parts.
                    snapshot.set(null)
                } else {
                    snapshot.set(snapshotOf(parse(base, json, false), GuardUserState.OK))
                }
            }
        } finally {
            json.fill(0)
        }
    }

    private fun load(): GuardSnapshot {
        val base = validBase ?: try {
            loadBase()
        } catch (t: Throwable) {
            rethrowIfFatal(t)
            return INVALID_SNAPSHOT
        }
        val read = store.read()
        val load: GuardConfigLoad
        val userState: GuardUserState
        when (read) {
            is GuardUserConfigStore.Read.Absent -> {
                load = baseOnlyOf(base)
                userState = GuardUserState.ABSENT
            }
            is GuardUserConfigStore.Read.Plain -> {
                try {
                    load = parse(base, read.bytes, false)
                } finally {
                    read.bytes.fill(0)
                }
                userState = if (load.userFailed) GuardUserState.UNREADABLE else GuardUserState.OK
            }
            is GuardUserConfigStore.Read.Unreadable -> {
                load = parse(base, null, true)
                userState = GuardUserState.UNREADABLE
            }
            is GuardUserConfigStore.Read.Transient -> {
                // Not cached as a snapshot (the next message retries the file),
                // but the compiled base-only rules are reused (security L-2).
                load = baseOnlyOf(base)
                userState = GuardUserState.RETRY
            }
        }
        val snap = snapshotOf(load, userState)
        if (load.baseError == null) {
            validBase = base
            if (read !is GuardUserConfigStore.Read.Transient) snapshot.set(snap)
        }
        return snap
    }

    /** The base-only rules of [base], parsed once per valid base (under [lock]). */
    private fun baseOnlyOf(base: ByteArray): GuardConfigLoad {
        baseOnly?.takeIf { validBase === base }?.let { return it }
        val load = parse(base, null, false)
        if (load.baseError == null) baseOnly = load
        return load
    }

    private fun limiterFor(perMin: Int): SenderRateLimiter {
        limiter?.takeIf { it.perSenderPerMin == perMin }?.let { return it }
        synchronized(lock) {
            limiter?.takeIf { it.perSenderPerMin == perMin }?.let { return it }
            return SenderRateLimiter(perMin).also { limiter = it }
        }
    }

    override fun toString(): String = "GuardRuntime"

    companion object {
        private val INVALID_SNAPSHOT = GuardSnapshot(CaptureGuard(null), GuardConfigMode.INVALID, GuardUserState.RETRY)

        private fun snapshotOf(load: GuardConfigLoad, userState: GuardUserState): GuardSnapshot =
            GuardSnapshot(CaptureGuard(load.config), load.mode, userState)

        @Volatile
        private var instance: GuardRuntime? = null

        /** The one runtime of this process (default process only). */
        fun get(context: Context): GuardRuntime =
            instance ?: synchronized(this) { instance ?: create(context.applicationContext).also { instance = it } }

        private fun create(context: Context): GuardRuntime = GuardRuntime(
            loadBase = { BaseConfigSource.readForBuild(context.assets) },
            store = GuardUserConfigStore(
                GuardUserConfigStore.dirUnder(context.noBackupFilesDir),
                KeystoreGuardUserCipher(),
                DefaultGuardFileOps(dirSync = ::osSyncDir),
            ),
            clockMs = SystemClock::elapsedRealtime,
        )

        private fun osSyncDir(dir: File) {
            val fd = Os.open(dir.path, OsConstants.O_RDONLY, 0)
            try {
                Os.fsync(fd)
            } finally {
                Os.close(fd)
            }
        }
    }
}
