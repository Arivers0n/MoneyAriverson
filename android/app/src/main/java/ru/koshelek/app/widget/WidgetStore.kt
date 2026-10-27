package ru.koshelek.app.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.os.Bundle
import android.widget.RemoteViews
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import ru.koshelek.app.MainActivity
import ru.koshelek.app.R
import ru.koshelek.app.core.*
import ru.koshelek.app.data.Settings
import ru.koshelek.app.data.Store
import ru.koshelek.app.ui.KopilkaTheme
import ru.koshelek.app.ui.LocalPal
import ru.koshelek.app.ui.pressable
import kotlin.math.sqrt

/** Дизайны виджетов (6 слотов × размеры) на этом устройстве и выбор слота для каждого виджета на рабочем столе. */
object WidgetStore {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private const val KEY = "widgets.configs"

    var configs by mutableStateOf(load())
        private set

    private fun load(): WidgetConfigSet =
        runCatching { json.decodeFromString<WidgetConfigSet>(Settings.str(KEY)).validated() }.getOrNull() ?: WidgetConfigSet.makeDefault()

    fun design(slot: Int, family: WidgetFamilyKind): WidgetDesign =
        configs.slot(slot)?.design(family) ?: WidgetPresets.make(WidgetPreset.kopilka, family)

    fun update(design: WidgetDesign, slot: Int) = store(configs.update(design, slot).validated())

    fun rename(slot: Int, name: String) = store(configs.rename(slot, name))

    private fun store(set: WidgetConfigSet) {
        configs = set
        Settings.setStr(KEY, json.encodeToString(set))
    }

    // Какой слот показывает конкретный виджет на рабочем столе
    fun slotOf(appWidgetId: Int): Int = Settings.int("widget.slot.$appWidgetId", 1).coerceIn(1, WidgetConfigSet.SLOT_COUNT)
    fun setSlot(appWidgetId: Int, slot: Int) = Settings.setInt("widget.slot.$appWidgetId", slot)
    fun forget(appWidgetId: Int) = Settings.sp.edit().remove("widget.slot.$appWidgetId").apply()
}

object WidgetUpdater {
    private val providers = listOf(
        WidgetFamilyKind.small to SmallWidget::class.java,
        WidgetFamilyKind.medium to MediumWidget::class.java,
        WidgetFamilyKind.large to LargeWidget::class.java,
    )

    /** Перерисовать все виджеты Копилки на рабочем столе. */
    fun updateAll(ctx: Context) {
        val mgr = AppWidgetManager.getInstance(ctx)
        val found = providers.map { (f, cls) -> f to mgr.getAppWidgetIds(ComponentName(ctx, cls)) }.filter { it.second.isNotEmpty() }
        if (found.isEmpty()) return
        val snap = WidgetSnapshot.build(Store.snapshot.value)
        for ((family, ids) in found) for (id in ids) update(ctx, mgr, id, family, snap)
    }

    fun update(ctx: Context, mgr: AppWidgetManager, id: Int, family: WidgetFamilyKind,
               snap: WidgetSnapshot = WidgetSnapshot.build(Store.snapshot.value)) {
        val density = ctx.resources.displayMetrics.density
        val opts = mgr.getAppWidgetOptions(id)
        var wDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0).toFloat()
        var hDp = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0).toFloat()
        if (wDp < 40f) wDp = family.previewW
        if (hDp < 40f) hDp = family.previewH
        var wPx = wDp * density; var hPx = hDp * density
        // Картинка для виджета не должна быть слишком большой
        val limit = 1_200_000f
        if (wPx * hPx > limit) { val k = sqrt(limit / (wPx * hPx)); wPx *= k; hPx *= k }

        val design = WidgetStore.design(WidgetStore.slotOf(id), family)
        val pet = if (design.blocks.any { it.kind == WidgetBlockKind.petImage }) WidgetAssets.pet(ctx, snap.petId) else null
        val bmp = WidgetRender.render(design, snap, pet, wPx.toInt(), hPx.toInt())

        val views = RemoteViews(ctx.packageName, R.layout.widget_image)
        views.setImageViewBitmap(R.id.widget_image, bmp)
        val open = PendingIntent.getActivity(ctx, id, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        views.setOnClickPendingIntent(R.id.widget_image, open)
        mgr.updateAppWidget(id, views)
    }
}

abstract class DesignWidgetProvider(private val family: WidgetFamilyKind) : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        val snap = WidgetSnapshot.build(Store.snapshot.value)
        ids.forEach { WidgetUpdater.update(context, mgr, it, family, snap) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, mgr: AppWidgetManager, id: Int, newOptions: Bundle) {
        WidgetUpdater.update(context, mgr, id, family)
    }
    override fun onDeleted(context: Context, ids: IntArray) { ids.forEach { WidgetStore.forget(it) } }
}

class SmallWidget : DesignWidgetProvider(WidgetFamilyKind.small)
class MediumWidget : DesignWidgetProvider(WidgetFamilyKind.medium)
class LargeWidget : DesignWidgetProvider(WidgetFamilyKind.large)

/** Окно выбора дизайна при добавлении виджета на рабочий стол («Виджет 1…6»). */
class WidgetSlotActivity : ComponentActivity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        appWidgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }
        setContent {
            KopilkaTheme {
                val p = LocalPal.current
                Column(Modifier.fillMaxSize().background(p.bg).statusBarsPadding().navigationBarsPadding().padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Какой дизайн показать?", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.text)
                    Text("Дизайны настраиваются в приложении: Настройки → Виджеты.", fontSize = 13.sp, color = p.secondary)
                    Spacer(Modifier.height(6.dp))
                    WidgetStore.configs.slots.forEach { slot ->
                        Text(slot.name, fontSize = 17.sp, color = p.text, fontWeight = FontWeight.Medium,
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(p.card)
                                .pressable({ pick(slot.id) }, 0.98f).padding(16.dp))
                    }
                }
            }
        }
    }

    private fun pick(slot: Int) {
        WidgetStore.setSlot(appWidgetId, slot)
        val mgr = AppWidgetManager.getInstance(this)
        val family = mgr.getAppWidgetInfo(appWidgetId)?.provider?.className?.let {
            when {
                it.endsWith("MediumWidget") -> WidgetFamilyKind.medium
                it.endsWith("LargeWidget") -> WidgetFamilyKind.large
                else -> WidgetFamilyKind.small
            }
        } ?: WidgetFamilyKind.small
        WidgetUpdater.update(this, mgr, appWidgetId, family)
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
        finish()
    }
}
