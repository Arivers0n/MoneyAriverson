package ru.koshelek.app.core

import kotlinx.serialization.Serializable
import java.util.UUID

// Конструктор виджетов: модель дизайна. Те же поля, границы и пресеты, что в Koshelek/Widgets/Shared/WidgetConfig.swift.
// Названия значений перечислений совпадают с iOS (budgetRing, leadingFeature…), поэтому JSON одинаковый.
// Дизайны лежат на устройстве и в синхронизацию не попадают. Размеры экрана блокировки есть только на iPhone.

enum class WidgetFamilyKind(val title: String, val maxBlocks: Int, val previewW: Float, val previewH: Float) {
    small("Малый", 4, 170f, 170f),
    medium("Средний", 6, 364f, 170f),
    large("Большой", 9, 364f, 382f),
    lockCircular("Круг", 1, 76f, 76f),
    lockRectangular("Прямоугольник", 3, 172f, 76f),
    lockInline("Строка", 1, 234f, 26f);

    val isLockScreen get() = ordinal >= 3

    companion object { val desktop = listOf(small, medium, large) }
}

enum class WidgetBlockKind(val title: String, val usesAccent: Boolean = false) {
    budgetRing("Кольцо бюджета", true),
    percentText("Процент лимита"),
    todaySpend("Сегодня потрачено"),
    dailyLeft("Можно в день"),
    monthExpense("Расходы за месяц"),
    monthIncome("Доходы за месяц"),
    balance("Баланс"),
    savings("Накоплено"),
    goalBar("Копилка", true),
    nextPayment("Ближайший платёж"),
    topCategories("Топ категорий"),
    level("Уровень напарника", true),
    phrase("Фраза напарника"),
    weekDots("Неделя", true),
    date("Дата"),
    greeting("Приветствие"),
    petImage("Питомец"),
    customText("Свой текст");

    val allowedOnLockScreen get() = this != petImage
}

enum class WidgetFontDesign(val title: String) {
    standard("Обычный"), rounded("Округлый"), serif("С засечками"), monospaced("Моноширинный")
}

enum class WidgetAlign(val title: String) { leading("Слева"), center("По центру"), trailing("Справа") }

enum class WidgetBackgroundKind(val title: String) { solid("Однотонный"), gradient("Градиент") }

enum class WidgetLayoutKind(val title: String) {
    stack("Столбиком"), leadingFeature("Главный слева"), topFeature("Главный сверху")
}

object HexColor {
    /** «#34d399», «34D399» или «fff» → «34D399». Некорректное → fallback. */
    fun normalize(hex: String, fallback: String): String {
        var s = hex.trim().uppercase()
        if (s.startsWith("#")) s = s.drop(1)
        if (s.length == 3) s = s.map { "$it$it" }.joinToString("")
        val ok = s.length == 6 && s.all { it in '0'..'9' || it in 'A'..'F' }
        return if (ok) s else fallback
    }

    /** Цвет ARGB; opacity 0…1. */
    fun argb(hex: String, opacity: Double = 1.0): Int {
        val v = normalize(hex, "FFFFFF").toInt(16)
        val a = (opacity.coerceIn(0.0, 1.0) * 255).toInt()
        return (a shl 24) or v
    }
}

fun Double.clampedTo(lo: Double, hi: Double): Double = if (!isFinite()) lo else minOf(hi, maxOf(lo, this))

@Serializable
data class WidgetTextStyle(
    val size: Double = 16.0,
    val weight: Int = 5,
    val design: WidgetFontDesign = WidgetFontDesign.rounded,
    val colorHex: String = "FFFFFF",
    val opacity: Double = 1.0,
    val alignment: WidgetAlign = WidgetAlign.leading,
    val uppercase: Boolean = false,
    val tracking: Double = 0.0,
    val lineLimit: Int = 2,
) {
    fun clamped() = copy(
        size = size.clampedTo(sizeMin, sizeMax), weight = weight.coerceIn(0, 8),
        colorHex = HexColor.normalize(colorHex, "FFFFFF"), opacity = opacity.clampedTo(0.1, 1.0),
        tracking = tracking.clampedTo(-2.0, 10.0), lineLimit = lineLimit.coerceIn(1, 6),
    )
    companion object { const val sizeMin = 8.0; const val sizeMax = 90.0 }
}

@Serializable
data class WidgetBlock(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val kind: WidgetBlockKind,
    val text: String = "",
    val style: WidgetTextStyle = WidgetTextStyle(),
    val accentHex: String = "5FD6C8",
    val trackHex: String = "FFFFFF",
    val trackOpacity: Double = 0.18,
    val thickness: Double = 10.0,
    val showCaption: Boolean = true,
    val captionScale: Double = 0.6,
    val spaceAfter: Double = 4.0,
) {
    fun clamped() = copy(
        text = text.take(80), style = style.clamped(),
        accentHex = HexColor.normalize(accentHex, "5FD6C8"), trackHex = HexColor.normalize(trackHex, "FFFFFF"),
        trackOpacity = trackOpacity.clampedTo(0.0, 1.0), thickness = thickness.clampedTo(2.0, 30.0),
        captionScale = captionScale.clampedTo(0.4, 1.0), spaceAfter = spaceAfter.clampedTo(0.0, 40.0),
    )
}

@Serializable
data class WidgetBackground(
    val kind: WidgetBackgroundKind = WidgetBackgroundKind.gradient,
    val colorA: String = "14213D",
    val colorB: String = "2B47C9",
    val angle: Double = 90.0,
    val opacity: Double = 1.0,
) {
    fun clamped(): WidgetBackground {
        var a = if (angle.isFinite()) angle % 360 else 90.0
        if (a < 0) a += 360
        return copy(colorA = HexColor.normalize(colorA, "14213D"), colorB = HexColor.normalize(colorB, "2B47C9"),
            angle = a, opacity = opacity.clampedTo(0.0, 1.0))
    }
}

@Serializable
data class WidgetDesign(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val name: String,
    val family: WidgetFamilyKind,
    val background: WidgetBackground = WidgetBackground(),
    val layout: WidgetLayoutKind = WidgetLayoutKind.stack,
    val align: WidgetAlign = WidgetAlign.leading,
    val padding: Double = 14.0,
    val spacing: Double = 8.0,
    val blocks: List<WidgetBlock> = emptyList(),
) {
    /** Приводит значения к допустимым границам; лишние и неподходящие блоки убирает. */
    fun validated(): WidgetDesign {
        var list = blocks.map { it.clamped() }
        if (family.isLockScreen) list = list.filter { it.kind.allowedOnLockScreen }
        return copy(name = name.trim().take(30), background = background.clamped(),
            padding = padding.clampedTo(0.0, 32.0), spacing = spacing.clampedTo(0.0, 32.0), blocks = list.take(family.maxBlocks))
    }
}

@Serializable
data class WidgetSlot(val id: Int, val name: String, val designs: Map<String, WidgetDesign> = emptyMap()) {
    fun design(f: WidgetFamilyKind): WidgetDesign? = designs[f.name]
    fun with(d: WidgetDesign) = copy(designs = designs + (d.family.name to d.validated()))
}

@Serializable
data class WidgetConfigSet(val version: Int = 1, val slots: List<WidgetSlot>) {
    fun slot(id: Int) = slots.firstOrNull { it.id == id }

    fun update(d: WidgetDesign, slotId: Int) = copy(slots = slots.map { if (it.id == slotId) it.with(d) else it })

    fun rename(slotId: Int, name: String) = copy(slots = slots.map { if (it.id == slotId) it.copy(name = name) else it }).validated()

    /** Ровно шесть слотов 1…6, все дизайны в допустимых границах; недостающее заполняется пресетами. */
    fun validated(): WidgetConfigSet {
        val fallback = makeDefault()
        val out = (1..SLOT_COUNT).map { i ->
            val src = slots.firstOrNull { it.id == i } ?: fallback.slots[i - 1]
            val name = src.name.trim().take(24).ifEmpty { "Виджет $i" }
            val fixed = WidgetFamilyKind.entries.associate { f ->
                val d = src.designs[f.name]?.copy(family = f)?.validated() ?: fallback.slots[i - 1].designs.getValue(f.name)
                f.name to d
            }
            WidgetSlot(i, name, fixed)
        }
        return WidgetConfigSet(1, out)
    }

    companion object {
        const val SLOT_COUNT = 6
        fun makeDefault(): WidgetConfigSet {
            val presets = WidgetPreset.entries
            val slots = (1..SLOT_COUNT).map { i ->
                val preset = presets[(i - 1) % presets.size]
                var slot = WidgetSlot(i, "Виджет $i")
                for (f in WidgetFamilyKind.entries) slot = slot.with(WidgetPresets.make(preset, f))
                slot
            }
            return WidgetConfigSet(1, slots)
        }
    }
}

// MARK: Пресеты

enum class WidgetPreset(val title: String, val bgA: String, val bgB: String, val text: String, val accent: String, val track: String, val trackOpacity: Double) {
    kopilka("Копилка", "1B2A6B", "2B47C9", "FFFFFF", "7BE0B4", "FFFFFF", 0.2),
    night("Ночь", "0F172A", "1E3A5F", "FFFFFF", "34D399", "FFFFFF", 0.16),
    glass("Стекло", "2A2F45", "4B3F72", "F5F3FF", "A78BFA", "FFFFFF", 0.22),
    neon("Неон", "05050A", "11061F", "F0FDFF", "22F5C8", "22F5C8", 0.14),
    warm("Тёплый", "7C2D12", "F59E0B", "FFF7ED", "FFF1C2", "FFFFFF", 0.25),
    paper("Бумага", "F8F5EE", "EDE6D6", "2B2A28", "17805A", "2B2A28", 0.1),
}

object WidgetPresets {
    /** Готовый дизайн для размера: ровно то, что видно сразу после добавления виджета. */
    fun make(preset: WidgetPreset, family: WidgetFamilyKind): WidgetDesign {
        val p = preset
        fun style(size: Double, weight: Int = 6, opacity: Double = 1.0, align: WidgetAlign = WidgetAlign.leading, lines: Int = 2) =
            WidgetTextStyle(size, weight, WidgetFontDesign.rounded, p.text, opacity, align, false, 0.0, lines)
        fun block(kind: WidgetBlockKind, s: WidgetTextStyle, thickness: Double = 10.0, after: Double = 4.0) =
            WidgetBlock(kind = kind, style = s, accentHex = p.accent, trackHex = p.track, trackOpacity = p.trackOpacity, thickness = thickness, spaceAfter = after)

        var d = WidgetDesign(name = p.title, family = family,
            background = WidgetBackground(WidgetBackgroundKind.gradient, p.bgA, p.bgB, 120.0, 1.0))
        val c = WidgetAlign.center
        d = when (family) {
            WidgetFamilyKind.small -> d.copy(align = c, blocks = listOf(
                block(WidgetBlockKind.budgetRing, style(24.0, 7, align = c), 11.0, 6.0),
                block(WidgetBlockKind.dailyLeft, style(14.0, 6, 0.95, c, 1)),
            ))
            WidgetFamilyKind.medium -> d.copy(layout = WidgetLayoutKind.leadingFeature, spacing = 14.0, blocks = listOf(
                block(WidgetBlockKind.budgetRing, style(28.0, 7, align = c), 12.0),
                block(WidgetBlockKind.greeting, style(17.0, 7)),
                block(WidgetBlockKind.phrase, style(13.0, 5, 0.85, lines = 3), after = 6.0),
                block(WidgetBlockKind.balance, style(22.0, 7)),
            ))
            WidgetFamilyKind.large -> d.copy(layout = WidgetLayoutKind.topFeature, spacing = 10.0, blocks = listOf(
                block(WidgetBlockKind.greeting, style(22.0, 7), after = 6.0),
                block(WidgetBlockKind.budgetRing, style(34.0, 7, align = c), 14.0, 8.0),
                block(WidgetBlockKind.weekDots, style(12.0, 5), 10.0),
                block(WidgetBlockKind.phrase, style(14.0, 5, 0.85, lines = 3)),
                block(WidgetBlockKind.balance, style(18.0, 7)),
                block(WidgetBlockKind.nextPayment, style(15.0, 6, lines = 2)),
            ))
            WidgetFamilyKind.lockCircular -> d.copy(align = c, padding = 4.0, blocks = listOf(block(WidgetBlockKind.budgetRing, style(16.0, 7, align = c), 6.0)))
            WidgetFamilyKind.lockRectangular -> d.copy(padding = 6.0, spacing = 2.0, blocks = listOf(
                block(WidgetBlockKind.todaySpend, style(15.0, 7, lines = 1), after = 0.0),
                block(WidgetBlockKind.dailyLeft, style(12.0, 5, 0.85, lines = 1), after = 0.0),
            ))
            WidgetFamilyKind.lockInline -> d.copy(padding = 0.0, blocks = listOf(block(WidgetBlockKind.todaySpend, style(14.0, 6, lines = 1), after = 0.0)))
        }
        return d.validated()
    }
}
