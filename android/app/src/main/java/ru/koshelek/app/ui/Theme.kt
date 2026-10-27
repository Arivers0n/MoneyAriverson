package ru.koshelek.app.ui

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.animation.core.*
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import ru.koshelek.app.core.Calc
import ru.koshelek.app.core.Fmt
import ru.koshelek.app.core.hexColor
import ru.koshelek.app.data.Settings

data class Accent(val id: String, val name: String, val light: String, val dark: String)

/** Оформление — те же варианты, что на iPhone. */
object Look {
    val accents = listOf(
        Accent("blue", "Синий", "2B47C9", "7C93FF"), Accent("green", "Изумруд", "17805A", "4CC995"),
        Accent("mint", "Мята", "0F8F86", "5FD6C8"), Accent("sky", "Небо", "1A7FC0", "64B5F6"),
        Accent("violet", "Лаванда", "7B4FD0", "B39BFF"), Accent("pink", "Фуксия", "C2307A", "F57FB8"),
        Accent("red", "Коралл", "C9402E", "FF8A75"), Accent("orange", "Апельсин", "C2621F", "FFA35C"),
        Accent("gold", "Золото", "A57A12", "E8C25A"), Accent("indigo", "Индиго", "4B44C8", "8E8CFF"),
        Accent("lime", "Лайм", "4E7F0E", "A8D65A"), Accent("graphite", "Графит", "2F3A36", "D8DED9"),
    )
    val backgrounds = listOf("grouped" to "Классика", "depth" to "Глубина", "aurora" to "Аврора", "midnight" to "Полночь", "tint" to "Свечение", "pure" to "OLED")

    data class Preset(val name: String, val scheme: String, val accent: String, val background: String, val cards: String, val font: String)
    val presets = listOf(
        Preset("Классика", "system", "blue", "grouped", "filled", "default"),
        Preset("Глубина", "dark", "blue", "depth", "glass", "rounded"),
        Preset("Полночь", "dark", "indigo", "midnight", "glass", "rounded"),
        Preset("Аврора", "dark", "violet", "aurora", "glass", "rounded"),
        Preset("Лес", "dark", "green", "depth", "filled", "default"),
        Preset("OLED", "dark", "sky", "pure", "outline", "default"),
        Preset("Закат", "light", "orange", "tint", "glass", "rounded"),
        Preset("Бумага", "light", "graphite", "pure", "outline", "serif"),
    )

    private fun s(k: String, d: String) = mutableStateOf(Settings.str(k, d))
    private fun b(k: String, d: Boolean) = mutableStateOf(Settings.bool(k, d))

    var scheme by s("ap.scheme", "system")
    var accent by s("ap.accent", "blue")
    var background by s("ap.bg", "grouped")
    var cards by s("ap.cards", "filled")
    var font by s("ap.font", "default")
    var bigNumber by s("ap.big", "net")
    var compact by b("ap.compact", false)
    var hideAmounts by b("ap.hide", false)
    var haptics by b("ap.haptics", true)
    var sounds by b("ap.sounds", true)
    var motion by s("ap.motion", "full")
    var showKopecks by b("ap.kop", false)
    var debtInTotals by b("ap.debt", true)
    var alwaysIncome by b("ap.inc", true)

    fun save() {
        Settings.setStr("ap.scheme", scheme); Settings.setStr("ap.accent", accent); Settings.setStr("ap.bg", background)
        Settings.setStr("ap.cards", cards); Settings.setStr("ap.font", font); Settings.setStr("ap.big", bigNumber)
        Settings.setBool("ap.compact", compact); Settings.setBool("ap.hide", hideAmounts); Settings.setBool("ap.haptics", haptics); Settings.setBool("ap.sounds", sounds)
        Settings.setStr("ap.motion", motion); Settings.setBool("ap.kop", showKopecks); Settings.setBool("ap.debt", debtInTotals)
        Settings.setBool("ap.inc", alwaysIncome)
        Fmt.showKopecks = showKopecks; Calc.debtInTotals = debtInTotals
    }
    fun apply(p: Preset) { scheme = p.scheme; accent = p.accent; background = p.background; cards = p.cards; font = p.font; save() }
    fun isCurrent(p: Preset) = p.scheme == scheme && p.accent == accent && p.background == background && p.cards == cards && p.font == font

    val moves get() = motion == "full"
    val animated get() = motion != "off"
}

/** Палитра текущей темы. */
data class Pal(
    val dark: Boolean, val accent: Color, val onAccent: Color, val inc: Color, val exp: Color, val warn: Color,
    val bg: Color, val card: Color, val text: Color, val secondary: Color, val tertiary: Color, val soft: Color, val stroke: Color,
)

val LocalPal = staticCompositionLocalOf { palette(false) }

fun palette(dark: Boolean): Pal {
    val a = Look.accents.firstOrNull { it.id == Look.accent } ?: Look.accents[0]
    fun dyn(l: String, d: String) = hexColor(if (dark) d else l)
    val bg = when (Look.background) {
        "pure" -> if (dark) Color.Black else Color.White
        "depth" -> dyn("EEF1F7", "090B12")
        "aurora" -> dyn("F1F0F8", "06070D")
        "midnight" -> dyn("E9ECF8", "0A1030")
        else -> dyn("F2F2F7", "000000")
    }
    val card = when (Look.background) {
        "pure" -> dyn("F2F2F7", "1C1C1E")
        "depth", "aurora", "midnight" -> dyn("FFFFFF", "171A24")
        else -> dyn("FFFFFF", "1C1C1E")
    }
    return Pal(
        dark = dark, accent = dyn(a.light, a.dark), onAccent = if (dark) hexColor("0B0F0D") else Color.White,
        inc = dyn("17805A", "4CC995"), exp = dyn("B8452A", "F0886B"), warn = dyn("B7791F", "E8B04E"),
        bg = bg, card = card,
        text = if (dark) Color.White else hexColor("111412"),
        secondary = if (dark) Color(0x99EBEBF5) else Color(0x993C3C43),
        tertiary = if (dark) Color(0x4DEBEBF5) else Color(0x4D3C3C43),
        soft = if (dark) Color(0x29767680) else Color(0x1F767680),
        stroke = if (dark) Color(0x1FFFFFFF) else Color(0x14000000),
    )
}

val Pal.fontFamily: FontFamily get() = if (Look.font == "serif") FontFamily.Serif else FontFamily.Default

@Composable
fun KopilkaTheme(content: @Composable () -> Unit) {
    val sys = isSystemInDarkTheme()
    val dark = when (Look.scheme) { "dark" -> true; "light" -> false; else -> sys }
    val pal = palette(dark)
    val cs = if (dark) darkColorScheme(primary = pal.accent, onPrimary = pal.onAccent, background = pal.bg, surface = pal.card, onSurface = pal.text, onBackground = pal.text)
             else lightColorScheme(primary = pal.accent, onPrimary = pal.onAccent, background = pal.bg, surface = pal.card, onSurface = pal.text, onBackground = pal.text)
    CompositionLocalProvider(LocalPal provides pal) {
        MaterialTheme(colorScheme = cs, content = content)
    }
}

// MARK: Движение

object Motion {
    fun <T> spring(): FiniteAnimationSpec<T> = if (Look.animated) spring(dampingRatio = 0.82f, stiffness = 380f) else snap()
    fun <T> snappy(): FiniteAnimationSpec<T> = if (Look.animated) spring(dampingRatio = 0.9f, stiffness = 600f) else snap()
    fun <T> entrance(ms: Int = 450): FiniteAnimationSpec<T> = if (Look.animated) tween(ms, easing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)) else snap()
}

// MARK: Вибрация

object Haptic {
    private var vib: Vibrator? = null
    fun init(ctx: Context) {
        vib = if (Build.VERSION.SDK_INT >= 31) (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
              else @Suppress("DEPRECATION") ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
    }
    private fun fx(id: Int) {
        if (!Look.haptics) return
        runCatching { vib?.vibrate(VibrationEffect.createPredefined(id)) }
    }
    fun tap() = fx(VibrationEffect.EFFECT_TICK)
    fun select() = fx(VibrationEffect.EFFECT_TICK)
    fun press() = fx(VibrationEffect.EFFECT_CLICK)
    fun heavy() = fx(VibrationEffect.EFFECT_HEAVY_CLICK)
    fun success() = fx(VibrationEffect.EFFECT_DOUBLE_CLICK)
    fun warning() = fx(VibrationEffect.EFFECT_HEAVY_CLICK)
}
