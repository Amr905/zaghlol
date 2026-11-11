package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.GuardConfigMode
import app.zaghlol.platform.guard.GuardConfigWriteException
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardSnapshot
import app.zaghlol.platform.guard.GuardUserState
import app.zaghlol.platform.guard.GuardWriteError

/**
 * T-038's `GuardRuntime` as seen by the capture host (FU-104 code #3, T-040
 * design note section 6). Both run on the Pigeon background queue
 * (`writeGuardConfig` and `getSpoolStatus` are `@TaskQueue`), where the
 * first Guard load may happen.
 */
object GuardAdapters {
    /**
     * `writeGuardConfig` → `GuardRuntime.writeUser`. Codes only:
     * `GuardConfigWriteException(CONFIG_INVALID)` → `CONFIG_INVALID`,
     * `(IO_ERROR)` → `IO_ERROR`, anything else → `IO_ERROR`; the reply never
     * carries a message, a cause or a detail (the reader's error path names
     * a JSON path, which is not sent either). The input is zeroed in every
     * case (the runtime zeroes it too).
     */
    fun writerFor(rt: GuardRuntime): (ByteArray) -> Unit = writerOf(rt::writeUser)

    /** [writerFor] over any `writeUser`-shaped function (the seam the JVM tests use for "anything else"). */
    internal fun writerOf(writeUser: (ByteArray) -> Unit): (ByteArray) -> Unit = { json ->
        try {
            writeUser(json)
        } catch (e: GuardConfigWriteException) {
            throw CaptureApiError(codeOf(e.error), null, null)
        } catch (_: Exception) {
            throw CaptureApiError(AndroidCaptureHost.IO_ERROR, null, null)
        } finally {
            json.fill(0)
        }
    }

    /** `getSpoolStatus().guardState` from the runtime's current rules. */
    fun stateFor(rt: GuardRuntime): () -> GuardConfigState = { stateOf(rt.state()) }

    internal fun codeOf(error: GuardWriteError): String = when (error) {
        GuardWriteError.CONFIG_INVALID -> AndroidCaptureHost.CONFIG_INVALID
        GuardWriteError.IO_ERROR -> AndroidCaptureHost.IO_ERROR
    }

    /**
     * Mode × user state → Pigeon state:
     * - mode `INVALID` → `BASE_INVALID`, whatever the user state;
     * - `FULL` + `OK` → `FULL`;
     * - `BASE_ONLY` + `ABSENT` → `BASE_ONLY` (fresh install);
     * - `BASE_ONLY` + `UNREADABLE` → `USER_UNREADABLE` (Dart rewrites at once);
     * - `BASE_ONLY` + `RETRY` → `UNKNOWN` (a transient file error: nothing to rewrite);
     * - any other pair → `UNKNOWN` (never claim a state we can't prove).
     */
    fun stateOf(snapshot: GuardSnapshot): GuardConfigState = when (snapshot.mode) {
        GuardConfigMode.INVALID -> GuardConfigState.BASE_INVALID
        GuardConfigMode.FULL -> if (snapshot.userState == GuardUserState.OK) GuardConfigState.FULL else GuardConfigState.UNKNOWN
        GuardConfigMode.BASE_ONLY -> when (snapshot.userState) {
            GuardUserState.ABSENT -> GuardConfigState.BASE_ONLY
            GuardUserState.UNREADABLE -> GuardConfigState.USER_UNREADABLE
            GuardUserState.RETRY, GuardUserState.OK -> GuardConfigState.UNKNOWN
        }
    }
}
