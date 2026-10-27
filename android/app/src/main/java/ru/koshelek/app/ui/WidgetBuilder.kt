package ru.koshelek.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import ru.koshelek.app.core.*
import ru.koshelek.app.data.Store
import ru.koshelek.app.widget.WidgetAssets
import ru.koshelek.app.widget.WidgetRender
import ru.koshelek.app.widget.WidgetStore
import ru.koshelek.app.widget.WidgetUpdater

/**
 * Конструктор виджетов: слот → размер → живой предпросмотр → фон, раскладка и блоки.
 * Предпросмотр рисуется тем же кодом, что и виджет на рабочем столе (WidgetRender).
 * На iPhone есть ещё размеры для экрана блокировки — на Android их нет.
 */
@Composable
fun WidgetBuilderScreen() {
    val p = LocalPal.current
    val ctx = LocalContext.current
    var slot by remember { mutableIntStateOf(1) }
    var family by remember { mutableStateOf(WidgetFamilyKind.small) }
    var design by remember(slot, family) { mutableStateOf(WidgetStore.design(slot, family)) }
    var sample by remember { mutableStateOf(false) }
    var editing by remember(slot, family) { mutableStateOf<String?>(null) }
    var renaming by remember { mutableStateOf(false) }
    val data by Store.snapshot.collectAsState()

    LaunchedEffect(design) {
        delay(400)
        if (design.validated() != WidgetStore.design(slot, family)) {
            WidgetStore.update(design, slot)
            WidgetUpdater.updateAll(ctx)
        }
    }

    fun change(f: (WidgetDesign) -> WidgetDesign) { design = f(design) }

    SheetScaffold("Виджеты", Icons.Rounded.Widgets) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // Выбор виджета и размера
            Group(footer = "Добавьте виджет «Мой виджет» на рабочий стол и выберите здесь созданный дизайн. Для каждого размера дизайн свой. На Android есть три размера; виджеты для экрана блокировки — только на iPhone.") {
                Text("Виджет", color = p.secondary, fontSize = 13.sp, modifier = Modifier.padding(start = 16.dp, top = 12.dp))
                Chips { WidgetStore.configs.slots.forEach { s -> Chip(s.name, s.id == slot) { slot = s.id } } }
                Divider1()
                Row(Modifier.fillMaxWidth().pressable({ renaming = true }, 0.99f).padding(horizontal = 16.dp, vertical = 12.dp)) {
                    Text("Переименовать", color = p.accent, fontSize = 16.sp)
                }
                Divider1()
                Segmented(WidgetFamilyKind.desktop.map { it.title }, WidgetFamilyKind.desktop.indexOf(family), onSel = { family = WidgetFamilyKind.desktop[it] })
            }

            // Предпросмотр
            Group("Так выглядит") {
                val bmp = remember(design, data, sample) {
                    val snap = if (sample) WidgetSnapshot.sample() else WidgetSnapshot.build(data)
                    val pet = if (design.blocks.any { it.kind == WidgetBlockKind.petImage }) WidgetAssets.pet(ctx, snap.petId) else null
                    WidgetRender.render(design, snap, pet, (family.previewW * 3).toInt(), (family.previewH * 3).toInt())
                }
                Box(Modifier.fillMaxWidth().padding(14.dp).clip(RoundedCornerShape(18.dp))
                    .background(Brush.linearGradient(listOf(Color(0xFF5B6B7F), Color(0xFF2D3A4B)))).padding(20.dp), contentAlignment = Alignment.Center) {
                    Image(bmp.asImageBitmap(), null, Modifier.fillMaxWidth().widthIn(max = family.previewW.dp).aspectRatio(family.previewW / family.previewH))
                }
                Divider1()
                SwitchRow("Показать пример данных", sample) { sample = it }
            }

            // Пресеты
            Group("Пресеты") {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    WidgetPreset.entries.forEach { pr -> Chip(pr.title, false) { design = WidgetPresets.make(pr, family) } }
                }
            }

            // Фон
            Group("Фон") {
                Segmented(WidgetBackgroundKind.entries.map { it.title }, design.background.kind.ordinal, onSel = { i ->
                    change { it.copy(background = it.background.copy(kind = WidgetBackgroundKind.entries[i])) }
                })
                HexRow("Цвет", design.background.colorA) { h -> change { it.copy(background = it.background.copy(colorA = h)) } }
                if (design.background.kind == WidgetBackgroundKind.gradient) {
                    HexRow("Второй цвет", design.background.colorB) { h -> change { it.copy(background = it.background.copy(colorB = h)) } }
                    SliderRow("Угол", design.background.angle, 0.0, 360.0, 5.0, "%.0f°") { v -> change { it.copy(background = it.background.copy(angle = v)) } }
                }
                SliderRow("Непрозрачность", design.background.opacity, 0.0, 1.0, 0.05, "%.2f") { v -> change { it.copy(background = it.background.copy(opacity = v)) } }
            }

            // Раскладка
            Group("Раскладка") {
                Segmented(WidgetLayoutKind.entries.map { it.title }, design.layout.ordinal, onSel = { i -> change { it.copy(layout = WidgetLayoutKind.entries[i]) } })
                SliderRow("Отступ от краёв", design.padding, 0.0, 32.0, 1.0, "%.0f") { v -> change { it.copy(padding = v) } }
                SliderRow("Между колонками", design.spacing, 0.0, 32.0, 1.0, "%.0f") { v -> change { it.copy(spacing = v) } }
            }

            // Блоки
            Group("Блоки (${design.blocks.size} из ${family.maxBlocks})",
                "Стрелками меняйте порядок. Нажмите на блок, чтобы настроить шрифт, цвет, размер и подписи.") {
                design.blocks.forEachIndexed { i, b ->
                    if (i > 0) Divider1()
                    BlockRow(b, i, design.blocks.size, editing == b.id,
                        onOpen = { editing = if (editing == b.id) null else b.id },
                        onUp = { change { d -> d.copy(blocks = d.blocks.toMutableList().also { l -> l.add(i - 1, l.removeAt(i)) }) } },
                        onDown = { change { d -> d.copy(blocks = d.blocks.toMutableList().also { l -> l.add(i + 1, l.removeAt(i)) }) } },
                        onDelete = { change { d -> d.copy(blocks = d.blocks.filterNot { it.id == b.id }) } })
                    if (editing == b.id) BlockEditor(b) { nb -> change { d -> d.copy(blocks = d.blocks.map { if (it.id == b.id) nb else it }) } }
                }
                if (design.blocks.size < family.maxBlocks) {
                    if (design.blocks.isNotEmpty()) Divider1()
                    Text("Добавить блок", color = p.secondary, fontSize = 13.sp, modifier = Modifier.padding(start = 16.dp, top = 12.dp))
                    Chips {
                        WidgetBlockKind.entries.forEach { k ->
                            Chip(k.title, false) {
                                val ref = design.blocks.firstOrNull()
                                var nb = WidgetBlock(kind = k)
                                if (ref != null) nb = nb.copy(style = nb.style.copy(colorHex = ref.style.colorHex, design = ref.style.design),
                                    accentHex = ref.accentHex, trackHex = ref.trackHex, trackOpacity = ref.trackOpacity)
                                change { d -> d.copy(blocks = d.blocks + nb) }
                                editing = nb.id
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (renaming) {
        var name by remember { mutableStateOf(WidgetStore.configs.slot(slot)?.name ?: "") }
        AlertDialog({ renaming = false }, title = { Text("Название виджета", fontSize = 18.sp) },
            text = { KTextField(name, { name = it.take(24) }, "Название") },
            confirmButton = { TextButton({ WidgetStore.rename(slot, name); renaming = false }) { Text("Готово") } },
            dismissButton = { TextButton({ renaming = false }) { Text("Отмена") } }, containerColor = p.card)
    }
}

@Composable
private fun BlockRow(b: WidgetBlock, i: Int, n: Int, open: Boolean, onOpen: () -> Unit, onUp: () -> Unit, onDown: () -> Unit, onDelete: () -> Unit) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).pressable(onOpen, 0.99f).padding(vertical = 10.dp)) {
            Text(b.kind.title, color = p.text, fontSize = 16.sp)
            Text(if (b.kind == WidgetBlockKind.customText) b.text.ifEmpty { "Мой текст" } else "${b.style.size.toInt()} пт · ${b.style.design.title}",
                color = p.secondary, fontSize = 12.sp, maxLines = 1)
        }
        IconBtn(Icons.Rounded.KeyboardArrowUp, i > 0, onUp)
        IconBtn(Icons.Rounded.KeyboardArrowDown, i < n - 1, onDown)
        IconBtn(Icons.Rounded.Delete, true, onDelete)
        Icon(if (open) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null, tint = p.tertiary, modifier = Modifier.padding(horizontal = 6.dp))
    }
}

@Composable
private fun IconBtn(icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, onClick: () -> Unit) {
    val p = LocalPal.current
    Icon(icon, null, tint = if (enabled) p.secondary else p.tertiary.copy(alpha = 0.4f),
        modifier = Modifier.size(40.dp).pressable(onClick, 0.9f, enabled = enabled).padding(8.dp))
}

private val weightNames = listOf("сверхтонкий", "тонкий", "лёгкий", "обычный", "средний", "полужирный", "жирный", "плотный", "чёрный")

/** Подробная настройка одного блока: что показывает, шрифт, цвет, размер, подписи, форма. */
@Composable
private fun BlockEditor(b: WidgetBlock, onChange: (WidgetBlock) -> Unit) {
    val p = LocalPal.current
    fun st(f: (WidgetTextStyle) -> WidgetTextStyle) = onChange(b.copy(style = f(b.style)))
    Column(Modifier.fillMaxWidth().background(p.soft.copy(alpha = 0.5f)).padding(bottom = 8.dp)) {
        Text("Что показывать", color = p.secondary, fontSize = 13.sp, modifier = Modifier.padding(start = 16.dp, top = 10.dp))
        Chips { WidgetBlockKind.entries.forEach { k -> Chip(k.title, k == b.kind) { onChange(b.copy(kind = k)) } } }
        if (b.kind == WidgetBlockKind.customText) KTextField(b.text, { onChange(b.copy(text = it.take(80))) }, "Текст", singleLine = false)

        Text("Шрифт", color = p.secondary, fontSize = 13.sp, modifier = Modifier.padding(start = 16.dp, top = 6.dp))
        Chips { WidgetFontDesign.entries.forEach { d -> Chip(d.title, d == b.style.design) { st { it.copy(design = d) } } } }
        SliderRow("Размер", b.style.size, WidgetTextStyle.sizeMin, WidgetTextStyle.sizeMax, 1.0, "%.0f пт") { v -> st { it.copy(size = v) } }
        SliderRow("Толщина: ${weightNames[b.style.weight.coerceIn(0, 8)]}", b.style.weight.toDouble(), 0.0, 8.0, 1.0, "%.0f") { v -> st { it.copy(weight = v.toInt()) } }
        Segmented(WidgetAlign.entries.map { it.title }, b.style.alignment.ordinal, onSel = { i -> st { it.copy(alignment = WidgetAlign.entries[i]) } })
        SwitchRow("ЗАГЛАВНЫЕ", b.style.uppercase) { v -> st { it.copy(uppercase = v) } }
        SliderRow("Межбуквенный интервал", b.style.tracking, -2.0, 10.0, 0.5, "%.1f") { v -> st { it.copy(tracking = v) } }
        SliderRow("Строк не больше", b.style.lineLimit.toDouble(), 1.0, 6.0, 1.0, "%.0f") { v -> st { it.copy(lineLimit = v.toInt()) } }

        HexRow("Цвет текста", b.style.colorHex) { h -> st { it.copy(colorHex = h) } }
        SliderRow("Непрозрачность", b.style.opacity, 0.1, 1.0, 0.05, "%.2f") { v -> st { it.copy(opacity = v) } }

        if (b.kind.usesAccent) {
            Text("Форма", color = p.secondary, fontSize = 13.sp, modifier = Modifier.padding(start = 16.dp, top = 6.dp))
            HexRow("Цвет заливки", b.accentHex) { h -> onChange(b.copy(accentHex = h)) }
            HexRow("Цвет подложки", b.trackHex) { h -> onChange(b.copy(trackHex = h)) }
            SliderRow("Яркость подложки", b.trackOpacity, 0.0, 1.0, 0.02, "%.2f") { v -> onChange(b.copy(trackOpacity = v)) }
            SliderRow("Толщина", b.thickness, 2.0, 30.0, 1.0, "%.0f") { v -> onChange(b.copy(thickness = v)) }
        }

        SwitchRow("Показывать подпись", b.showCaption) { onChange(b.copy(showCaption = it)) }
        if (b.showCaption) SliderRow("Размер подписи", b.captionScale, 0.4, 1.0, 0.05, "×%.2f") { v -> onChange(b.copy(captionScale = v)) }
        SliderRow("Отступ после блока", b.spaceAfter, 0.0, 40.0, 1.0, "%.0f") { v -> onChange(b.copy(spaceAfter = v)) }
    }
}

@Composable
private fun SliderRow(title: String, value: Double, lo: Double, hi: Double, step: Double, format: String, onChange: (Double) -> Unit) {
    val p = LocalPal.current
    val steps = ((hi - lo) / step).toInt() - 1
    Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = p.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
            Text(String.format(RU, format, value), color = p.secondary, fontSize = 14.sp, fontFamily = FontFamily.Monospace)
        }
        Slider(value.coerceIn(lo, hi).toFloat(), { onChange((Math.round(it / step) * step).coerceIn(lo, hi)) }, valueRange = lo.toFloat()..hi.toFloat(),
            steps = steps.coerceAtLeast(0), colors = SliderDefaults.colors(thumbColor = p.accent, activeTrackColor = p.accent, inactiveTrackColor = p.soft))
    }
}

private val quickColors = listOf("FFFFFF", "000000", "7BE0B4", "34D399", "22F5C8", "A78BFA", "F59E0B", "F4B63A", "FF8A75", "7C93FF", "2B47C9", "14213D")

/** Цвет: быстрый выбор из палитры и точный ввод hex. */
@Composable
private fun HexRow(title: String, hex: String, onChange: (String) -> Unit) {
    val p = LocalPal.current
    var text by remember(hex) { mutableStateOf(hex) }
    Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, color = p.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
            Box(Modifier.size(24.dp).clip(RoundedCornerShape(7.dp)).background(Color(HexColor.argb(hex))))
            BasicTextField(text, { s ->
                val v = s.uppercase().filter { it in '0'..'9' || it in 'A'..'F' }.take(6)
                text = v
                if (v.length == 6) onChange(v)
            }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii),
                textStyle = TextStyle(fontSize = 15.sp, color = p.text, fontFamily = FontFamily.Monospace),
                cursorBrush = SolidColor(p.accent),
                modifier = Modifier.width(80.dp).clip(RoundedCornerShape(8.dp)).background(p.soft).padding(horizontal = 10.dp, vertical = 7.dp))
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            quickColors.forEach { c ->
                Box(Modifier.size(26.dp).clip(RoundedCornerShape(50)).background(Color(HexColor.argb(c))).pressable({ Haptic.select(); onChange(c) }, 0.9f))
            }
        }
    }
}
