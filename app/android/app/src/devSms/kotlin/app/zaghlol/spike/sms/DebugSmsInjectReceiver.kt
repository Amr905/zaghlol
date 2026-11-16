package app.zaghlol.spike.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import app.zaghlol.platform.capture.SmsCapture
import app.zaghlol.platform.capture.SmsPart

/**
 * devSms only (SMS-device): hands a synthetic SMS with an **alphanumeric**
 * sender (HSBC, CIB, NBE...) to the production intake, because the emulator
 * console (`adb emu sms send`) only accepts numeric sender ids. It enters at
 * the same place the real receiver does after it has read the PDUs:
 * `SmsCapture.dispatch` -> `SmsIntake.process` -> multipart assembly ->
 * Guard -> spool -> enqueue. Everything from there on is the production code.
 *
 * Reachable only by the shell and the system: the receiver requires the
 * `DUMP` permission (held by `adb shell`, not grantable to apps). It exists
 * in the devSms build only (src/devSms; the placement check keeps it out of
 * every other flavour). Nothing is logged.
 *
 * `adb shell am broadcast -a app.zaghlol.dev.INJECT_SMS --es sender HSBC --es body '...'`
 */
class DebugSmsInjectReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val sender = intent.getStringExtra("sender") ?: return
        val body = intent.getStringExtra("body") ?: return
        val wallMs = System.currentTimeMillis()
        val rxElapsedNs = SystemClock.elapsedRealtimeNanos()
        val app = context.applicationContext
        val pending = goAsync()
        SmsCapture.dispatch.run(
            work = { SmsCapture.intake(app).process(listOf(SmsPart(sender, body, wallMs)), wallMs, rxElapsedNs, null) },
            finish = { pending.finish() },
        )
    }

    companion object {
        const val ACTION = "app.zaghlol.dev.INJECT_SMS"
    }
}
