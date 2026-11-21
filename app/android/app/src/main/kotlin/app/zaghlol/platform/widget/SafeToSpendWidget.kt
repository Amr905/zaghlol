package app.zaghlol.platform.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * T-118 / W-01 (FR-WID-01): safe-to-spend and days to payday. It only draws
 * the redacted strings the app stored ([WidgetSnapshotStore]); an absent or
 * unreadable snapshot draws nothing sensitive and a hint to open the app
 * (the app also sends the hint text, so no copy lives here). Tap opens
 * `zaghlol://home`, which the app routes through the lock screen if locked.
 * Colors are the Mint Fresh / Jade Night tokens; text follows the system
 * layout direction (RTL-first).
 */
class SafeToSpendWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val view = withContext(Dispatchers.IO) { WidgetStores.create(context).readOrNull() }
        val tap = Intent(Intent.ACTION_VIEW, Uri.parse("zaghlol://home")).setPackage(context.packageName)
        val secondary = view?.secondaryAt(System.currentTimeMillis()) ?: ""
        provideContent { WidgetContent(view, secondary, tap) }
    }
}

private val Surface = ColorProvider(day = Color(0xFFF3FBF7), night = Color(0xFF08130F))
private val Ink = ColorProvider(day = Color(0xFF0F2A20), night = Color(0xFFE6F5EE))
private val Muted = ColorProvider(day = Color(0xFF4D695C), night = Color(0xFF9DB8AB))

@Composable
private fun WidgetContent(view: WidgetView?, secondary: String, tap: Intent) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(Surface)
            .padding(12.dp)
            .clickable(actionStartActivity(tap)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (view != null) {
            Text(
                text = view.primaryText,
                style = TextStyle(color = Ink, fontSize = 18.sp, fontWeight = FontWeight.Bold),
                maxLines = 2,
            )
            if (secondary.isNotEmpty()) {
                Text(text = secondary, style = TextStyle(color = Muted, fontSize = 12.sp), maxLines = 2)
            }
        }
    }
}

class SafeToSpendWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SafeToSpendWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetMidnightWorker.schedule(context)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetMidnightWorker.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetMidnightWorker.cancel(context)
    }

    companion object {
        /** Called from the channel's background thread after the snapshot changed. */
        fun refreshAll(context: Context) {
            runBlocking { SafeToSpendWidget().updateAll(context) }
            WidgetMidnightWorker.schedule(context)
        }
    }
}
