package ru.koshelek.app.ui

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TxForm(edit: Tx?) {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    var kind by remember { mutableStateOf(edit?.kind ?: TxKind.EXP) }
    var amount by remember { mutableStateOf(edit?.let { Fmt.input(it.amount) } ?: "") }
    var cat by remember { mutableStateOf(edit?.cat ?: "food") }
    var note by remember { mutableStateOf(edit?.note ?: "") }
    var date by remember { mutableStateOf(edit?.date ?: LocalDate.now()) }
    var acc by remember { mutableStateOf(edit?.acc ?: Router.accFilter ?: snap.accounts.firstOrNull()?.id) }
    var to by remember { mutableStateOf(edit?.to ?: snap.accounts.getOrNull(1)?.id) }
    var picker by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (edit == null) { delay(350); runCatching { focus.requestFocus() } } }
    LaunchedEffect(kind) { if (kind != TxKind.TR) cat = Catalog.valid(cat, kind) }

    val value = parseAmount(amount) ?: 0.0
    val canSave = value > 0 && (kind != TxKind.TR || (acc != null && to != null && acc != to))
    val color = when (kind) { TxKind.INC -> p.inc; TxKind.EXP -> p.text; TxKind.TR -> p.accent }

    fun save() {
        if (!canSave) return
        val t = (edit ?: Tx()).copy(kind = kind, amount = value, cat = if (kind == TxKind.TR) "" else cat, note = note.trim().cleanedNote(),
            date = date, acc = acc, to = if (kind == TxKind.TR) to else null)
        Store.saveTx(t)
        Haptic.success()
        Router.close()
        if (edit == null) Router.say("Записано: ${if (kind == TxKind.TR) "перевод" else Catalog.cat(t.cat).name} ${Fmt.rubU(value)}") { Store.delete("tx", t.id) }
    }

    SheetScaffold(if (edit == null) "Новая операция" else "Операция", trailing = {
        if (edit != null) GlassCircle(Icons.Rounded.Delete, tint = p.exp, desc = "Удалить") { Router.close(); TxActions.delete(edit) }
    }, bottom = {
        PrimaryButton(if (edit == null) "Записать" else "Сохранить", Modifier.padding(16.dp), enabled = canSave) { save() }
    }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
                PillToggle(listOfNotNull(
                    PillOption(0, "Расход", Icons.Rounded.NorthEast, p.warn),
                    PillOption(1, "Доход", Icons.Rounded.SouthWest, p.inc),
                    if (snap.accounts.size >= 2) PillOption(2, "Перевод", Icons.Rounded.SwapHoriz, p.accent) else null,
                ), kind.ordinal) { kind = TxKind.entries[it] }
            }
            // Сумма
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                BasicTextField(amount, { s -> amount = s.filter { it.isDigit() || it == ',' || it == '.' || it == ' ' }.take(12) },
                    textStyle = TextStyle(fontSize = 56.sp, fontWeight = FontWeight.Bold, color = color, textAlign = TextAlign.End, fontFamily = p.fontFamily),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true, cursorBrush = SolidColor(p.accent),
                    modifier = Modifier.width(IntrinsicSize.Min).widthIn(min = 40.dp).focusRequester(focus),
                    decorationBox = { inner -> Box(contentAlignment = Alignment.CenterEnd) { if (amount.isEmpty()) Text("0", fontSize = 56.sp, fontWeight = FontWeight.Bold, color = p.tertiary); inner() } })
                Text(" ₽", fontSize = 44.sp, fontWeight = FontWeight.Bold, color = p.tertiary)
            }

            if (kind == TxKind.TR) {
                Group("Откуда") { AccountChooser(snap.accounts, acc) { acc = it } }
                Group("Куда") { AccountChooser(snap.accounts, to) { to = it } }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SectionTitle("Категория")
                    val cats = Catalog.list(kind)
                    // Сетка без собственной прокрутки — внутри общего скролла
                    val cols = 4
                    cats.chunked(cols).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { c -> CatCell(c, c.id == cat, Modifier.weight(1f)) { Haptic.select(); cat = c.id } }
                            repeat(cols - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }

            Group {
                KTextField(note, { note = it.take(80) }, "Заметка — магазин, что купили")
                Divider1()
                Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.CalendarToday, null, tint = p.secondary, modifier = Modifier.padding(start = 4.dp).size(20.dp))
                    DateChip("Сегодня", date == LocalDate.now()) { date = LocalDate.now() }
                    DateChip("Вчера", date == LocalDate.now().minusDays(1)) { date = LocalDate.now().minusDays(1) }
                    val other = date != LocalDate.now() && date != LocalDate.now().minusDays(1)
                    DateChip(if (other) DF.short(date) else "Другая дата", other) { picker = true }
                }
                if (kind != TxKind.TR && snap.accounts.isNotEmpty()) {
                    Divider1()
                    AccountChooser(snap.accounts, acc, allowNone = true) { acc = it }
                }
            }
            Spacer(Modifier.height(10.dp))
        }
    }

    if (picker) {
        val st = rememberDatePickerState(date.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli())
        DatePickerDialog({ picker = false }, confirmButton = {
            TextButton({ st.selectedDateMillis?.let { date = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }; picker = false }) { Text("Готово") }
        }, dismissButton = { TextButton({ picker = false }) { Text("Отмена") } }) { DatePicker(st) }
    }
}

@Composable
fun CatCell(c: Category, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val p = LocalPal.current
    val bg by androidx.compose.animation.animateColorAsState(if (selected) c.color.copy(alpha = 0.22f) else Color.Transparent, label = "cat")
    Column(modifier.clip(RoundedCornerShape(18.dp)).background(bg).pressable(onClick, 0.94f).padding(vertical = 10.dp, horizontal = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Tile(c.icon, c.color, 44.dp)
        Text(c.name, fontSize = 11.sp, color = if (selected) p.text else p.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal, textAlign = TextAlign.Center)
    }
}

@Composable
fun DateChip(text: String, on: Boolean, onClick: () -> Unit) {
    val p = LocalPal.current
    Text(text, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = if (on) p.onAccent else p.text,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(if (on) p.accent else p.soft).pressable({ Haptic.select(); onClick() }).padding(horizontal = 12.dp, vertical = 7.dp))
}

@Composable
fun AccountChooser(accounts: List<Account>, sel: String?, allowNone: Boolean = false, onSel: (String?) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Rounded.AccountBalanceWallet, null, tint = LocalPal.current.secondary, modifier = Modifier.padding(start = 4.dp).size(20.dp))
        if (allowNone) DateChip("Без счёта", sel == null) { onSel(null) }
        accounts.forEach { a -> DateChip(a.name, sel == a.id) { onSel(a.id) } }
    }
}
