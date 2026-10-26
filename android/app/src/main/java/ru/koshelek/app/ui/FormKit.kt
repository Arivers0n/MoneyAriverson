package ru.koshelek.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** Вложенное окно поверх текущего (форма долга, платёж, копилка…). */
@Composable
fun <T> Overlay(value: T?, onClose: () -> Unit, content: @Composable (T) -> Unit) {
    AnimatedVisibility(value != null, enter = if (Look.moves) slideInVertically(Motion.entrance(420)) { it / 3 } + fadeIn(tween(200)) else fadeIn(tween(150)),
        exit = if (Look.moves) slideOutVertically(tween(240)) { it / 4 } + fadeOut(tween(200)) else fadeOut(tween(120))) {
        var last by remember { mutableStateOf(value) }
        if (value != null) last = value
        BackHandler { onClose() }
        last?.let { content(it) }
    }
}

/** Строка формы: подпись слева, поле справа. */
@Composable
fun FieldRow(label: String, value: String, onChange: (String) -> Unit, placeholder: String, numeric: Boolean = true) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = p.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Box(Modifier.widthIn(min = 80.dp, max = 180.dp), contentAlignment = Alignment.CenterEnd) {
            if (value.isEmpty()) Text(placeholder, color = p.tertiary, fontSize = 16.sp, textAlign = TextAlign.End)
            BasicTextField(value, { s -> onChange(if (numeric) s.filter { it.isDigit() || it == ',' || it == '.' || it == ' ' } else s) }, singleLine = true,
                textStyle = TextStyle(fontSize = 16.sp, color = p.text, textAlign = TextAlign.End, fontWeight = FontWeight.Medium),
                keyboardOptions = if (numeric) KeyboardOptions(keyboardType = KeyboardType.Decimal) else KeyboardOptions.Default,
                cursorBrush = SolidColor(p.accent), modifier = Modifier.fillMaxWidth())
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun Chips(content: @Composable FlowRowScope.() -> Unit) {
    FlowRow(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

@Composable
fun Chip(text: String, on: Boolean, color: Color? = null, onClick: () -> Unit) {
    val p = LocalPal.current
    val c = color ?: p.accent
    Text(text, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = if (on) (if (color == null) p.onAccent else Color.White) else p.text,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(if (on) c else p.soft).pressable({ Haptic.select(); onClick() }).padding(horizontal = 14.dp, vertical = 8.dp))
}

/** Сегменты в одну строку (как Picker .segmented). */
@Composable
fun Segmented(options: List<String>, sel: Int, onSel: (Int) -> Unit, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    Row(modifier.fillMaxWidth().padding(12.dp).clip(RoundedCornerShape(12.dp)).background(p.soft).padding(3.dp)) {
        options.forEachIndexed { i, t ->
            val on = i == sel
            val bg by animateColorAsState(if (on) p.card else Color.Transparent, label = "seg")
            Text(t, fontSize = 14.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, color = p.text, textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(9.dp)).background(bg).pressable({ Haptic.select(); onSel(i) }, 0.97f).padding(vertical = 8.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateRow(label: String, date: LocalDate, onChange: (LocalDate) -> Unit) {
    val p = LocalPal.current
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().pressable({ open = true }, 0.99f).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = p.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Text(ru.koshelek.app.core.DF.s(date, "d MMMM yyyy"), color = p.accent, fontSize = 15.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(p.soft).padding(horizontal = 10.dp, vertical = 6.dp))
    }
    if (open) {
        val st = rememberDatePickerState(date.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli())
        DatePickerDialog({ open = false }, confirmButton = {
            TextButton({ st.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }; open = false }) { Text("Готово") }
        }, dismissButton = { TextButton({ open = false }) { Text("Отмена") } }) { DatePicker(st) }
    }
}

@Composable
fun SwitchRow(title: String, checked: Boolean, sub: String? = null, onChange: (Boolean) -> Unit) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().pressable({ Haptic.select(); onChange(!checked) }, 0.99f).padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = p.text, fontSize = 16.sp)
            if (sub != null) Text(sub, color = p.secondary, fontSize = 12.sp)
        }
        Switch(checked, { Haptic.select(); onChange(it) }, colors = SwitchDefaults.colors(checkedTrackColor = p.accent, checkedThumbColor = p.onAccent))
    }
}

@Composable
fun Confirm(title: String, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val p = LocalPal.current
    AlertDialog(onDismiss, confirmButton = { TextButton({ onConfirm(); onDismiss() }) { Text(action, color = p.exp) } },
        dismissButton = { TextButton(onDismiss) { Text("Отмена") } }, title = { Text(title, fontSize = 18.sp) }, containerColor = p.card)
}

@Composable
fun StatBox(title: String, value: String, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(p.soft).padding(10.dp)) {
        Text(title, fontSize = 12.sp, color = p.secondary, maxLines = 1)
        Text(value, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = p.text, maxLines = 1)
    }
}

@Composable
fun Pill(text: String, color: Color) {
    Text(text, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = color,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.15f)).padding(horizontal = 8.dp, vertical = 3.dp))
}
