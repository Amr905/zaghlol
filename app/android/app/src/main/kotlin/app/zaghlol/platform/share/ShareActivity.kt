package app.zaghlol.platform.share

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import app.zaghlol.MainActivity
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Exported share target (ACTION_SEND for text/plain, image, PDF, CSV). It has
 * no UI: it encrypts the payload on a worker thread, then opens
 * [MainActivity] with an intent that carries no content, only the per-process
 * hand-off token (F7). It stays alive until the copy is done because the
 * sender's read grant is tied to this activity.
 *
 * Time bound (F3): the read is cancelled [ShareLimits.INTAKE_TIMEOUT_MS] after
 * the share arrived (counted from arrival, so a share queued behind a slow one
 * cannot extend it), and after a further [ShareLimits.INTAKE_GRACE_MS] the
 * share is refused as `unreadable` even if the worker has not returned.
 * Recreation (F3): the job id is kept in the saved state; a recreated
 * instance re-attaches to the running job and never ingests twice.
 *
 * Never logs, and never reads the clipboard.
 */
class ShareActivity : Activity() {
    private var job: ShareJob? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val restoredId = savedInstanceState?.getString(KEY_JOB)
        if (restoredId != null) {
            val existing = ShareJobs.get(restoredId)
            if (existing == null) {
                // The process was restarted, so the worker is gone. Anything it stored is found by polling.
                openApp()
            } else {
                attach(existing)
            }
            return
        }
        val incoming = intent
        if (incoming?.action != Intent.ACTION_SEND) {
            finish()
            return
        }
        start(incoming)
    }

    private fun start(incoming: Intent) {
        val context = applicationContext
        val source = IntentShareSource(context, incoming)
        val newJob = ShareJobs.create { MAIN.post(it) }
        val deadline = SystemClock.elapsedRealtime() + ShareLimits.INTAKE_TIMEOUT_MS
        val cancelRead = WATCHDOG.schedule(Runnable { source.cancel() }, ShareLimits.INTAKE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        val giveUp = WATCHDOG.schedule(
            Runnable { ShareJobs.finish(newJob, ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)) },
            ShareLimits.INTAKE_TIMEOUT_MS + ShareLimits.INTAKE_GRACE_MS,
            TimeUnit.MILLISECONDS,
        )
        EXECUTOR.execute {
            val outcome = try {
                ShareIntake(
                    store = ShareStores.create(context),
                    ownPackage = context.packageName,
                    imageProbe = BitmapBoundsProbe,
                    clock = SystemClock::elapsedRealtime,
                ).accept(source, deadline)
            } catch (_: Exception) {
                ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)
            } catch (_: OutOfMemoryError) {
                ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)
            }
            cancelRead.cancel(false)
            giveUp.cancel(false)
            ShareJobs.finish(newJob, outcome)
        }
        attach(newJob)
    }

    private fun attach(j: ShareJob) {
        job = j
        j.attach {
            ShareJobs.remove(j.id)
            job = null
            openApp()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        job?.let { outState.putString(KEY_JOB, it.id) }
    }

    override fun onDestroy() {
        job?.let {
            it.detach()
            // Finished by the user or the system (not a configuration change): nobody will re-attach.
            if (isFinishing) ShareJobs.remove(it.id)
        }
        super.onDestroy()
    }

    /** Opens the app's own task; the intent carries no content. Dart lists the store itself. */
    private fun openApp() {
        if (!isFinishing && !isDestroyed) {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .setAction(ShareHandOff.ACTION_SHARE_READY)
                    .putExtra(ShareHandOff.EXTRA_TOKEN, ShareHandOff.token.value)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
        }
        finish()
    }

    private companion object {
        const val KEY_JOB = "app.zaghlol.share.job"
        val MAIN = Handler(Looper.getMainLooper())

        /** One worker: shares are ingested in order, each bounded by its own deadline. */
        val EXECUTOR = Executors.newSingleThreadExecutor { r -> Thread(r, "zaghlol-share").apply { isDaemon = true } }
        val WATCHDOG: ScheduledExecutorService =
            Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "zaghlol-share-timeout").apply { isDaemon = true } }
    }
}
