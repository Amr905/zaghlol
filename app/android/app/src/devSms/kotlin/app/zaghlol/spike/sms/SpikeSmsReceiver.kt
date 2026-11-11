package app.zaghlol.spike.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.provider.Telephony

/**
 * SMS_RECEIVED observer (devSms spike; T-040 productionises it). The manifest
 * entry requires `android.permission.BROADCAST_SMS` from the sender, which
 * only the telephony stack holds, so other apps and `adb shell am broadcast`
 * can't spoof messages. It observes only: the broadcast is never aborted. No engine, parse or
 * DB here: stamp, assemble, then Guard → spool → enqueue on a worker thread
 * under `goAsync()` with a 5 s budget.
 */
class SpikeSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val wallMs = System.currentTimeMillis()
        val elapsedNs = SystemClock.elapsedRealtimeNanos()
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val rt = SpikeRuntime.get(context)
        if (rt.headless.isIdle() && rt.uiEvents == null) rt.processWokenBySms = true
        val parts = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
                ?.filterNotNull()
                ?.map { SmsPart(it.originatingAddress, it.messageBody, it.timestampMillis) }
                .orEmpty()
        } catch (_: Exception) {
            emptyList()
        }
        val stamp = ReceiveStamp(wallMs, elapsedNs, rt.bootCount(), simSlotOf(intent))
        val pending = goAsync()
        rt.dispatch.run(
            work = {
                val ids = rt.intake.process(SmsAssembler.assemble(parts), stamp)
                if (ids.isNotEmpty()) rt.notifyUiIfAttached()
            },
            finish = { pending.finish() },
        )
    }

    private fun simSlotOf(intent: Intent): Int? {
        // EXTRA_SLOT_INDEX (API 30+) or the older "slot" extra; -1 when absent.
        val slot = try {
            val s = intent.getIntExtra(EXTRA_SLOT_INDEX, -1)
            if (s >= 0) s else intent.getIntExtra("slot", -1)
        } catch (_: Exception) {
            -1
        }
        return if (slot >= 0) slot else null
    }

    private companion object {
        const val EXTRA_SLOT_INDEX = "android.telephony.extra.SLOT_INDEX"
    }
}
