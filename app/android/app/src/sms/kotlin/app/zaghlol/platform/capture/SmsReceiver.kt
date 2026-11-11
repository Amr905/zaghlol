package app.zaghlol.platform.capture

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.provider.Telephony

/**
 * `SMS_RECEIVED` observer (T-040; every `*Sms` variant, `src/sms`, so no
 * `*NoSms` dex has this class). Declared with
 * `android:permission="android.permission.BROADCAST_SMS"`, which only the
 * telephony stack holds, so no app and no `adb shell am broadcast` can
 * deliver a fake SMS here. It only observes: the broadcast is never aborted
 * and its result is never set.
 *
 * On the main thread (no I/O): action check, receive stamps, PDUs, SIM slot,
 * `goAsync()`. Then, on the SMS intake thread with a 5 s budget
 * ([SmsCapture.dispatch], `finish()` exactly once): multipart assembly,
 * Guard → spool → enqueue ([SmsIntake], [CaptureIntake]). A personal SMS is
 * decided in memory and leaves no file. Nothing is logged.
 *
 * Accessors: `displayOriginatingAddress` / `displayMessageBody`, which
 * reproduce the system inbox row (they differ from `originatingAddress` /
 * `messageBody` only for email-gateway SMS), so the live and the inbox
 * catch-up `body_hash` match (FU-085/FU-088; checked against the inbox by
 * `SmsReceiverEmulatorTest`).
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val wallMs = System.currentTimeMillis()
        val rxElapsedNs = SystemClock.elapsedRealtimeNanos()
        val parts = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
                ?.filterNotNull()
                ?.map { SmsPart(it.displayOriginatingAddress, it.displayMessageBody, it.timestampMillis) }
                .orEmpty()
        } catch (_: Exception) {
            emptyList() // malformed PDUs: nothing to decide
        }
        val simSlot = SimSlot.fromExtras({ name -> if (intent.hasExtra(name)) intent.getIntExtra(name, -1) else null })
        val app = context.applicationContext
        val pending = goAsync()
        SmsCapture.dispatch.run(
            work = { SmsCapture.intake(app).process(parts, wallMs, rxElapsedNs, simSlot) },
            finish = { pending.finish() },
        )
    }
}
