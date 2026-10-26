package ru.koshelek.app.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*

/** Проверка распознанного голосом или со скана перед сохранением. */
@Composable
fun ReviewScreen(initial: List<ParsedItem>, subtitle: String) {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    val items = remember { mutableStateListOf<ParsedItem>().apply { addAll(initial.map { it.copy() }) } }
    val texts = remember { mutableStateListOf<String>().apply { addAll(initial.map { Fmt.input(it.amount) }) } }
    var acc by remember { mutableStateOf(snap.accounts.firstOrNull { it.id == Settings.str("lastAcc") }?.id ?: snap.accounts.firstOrNull()?.id) }
    val onCount = items.count { it.on }

    fun upd(i: Int, f: (ParsedItem) -> Unit) { items[i] = items[i].copy().also(f) }

    fun save() {
        val list = items.mapIndexed { i, x -> x.copy(amount = parseAmount(texts[i]) ?: 0.0) }
        val res = Saver.apply(list, Store.snapshot.value, acc)
        acc?.let { Settings.setStr("lastAcc", it) }
        Router.close()
        when {
            res.closedDebt != null -> Router.celebrate = "«${res.closedDebt}» закрыт!" to "Долг полностью погашен. Так держать."
            res.goalDone != null -> Router.celebrate = "Цель «${res.goalDone}» достигнута!" to "Копилка полная. Время тратить с удовольствием."
            else -> { Haptic.success(); Router.say("Добавлено: ${res.count}") }
        }
    }

    val title = if (items.size == 1) "Проверьте" else "Проверьте ${items.size} ${plural(items.size, "запись", "записи", "записей")}"
    SheetScaffold(title, bottom = {
        PrimaryButton(if (onCount == 0) "Ничего не выбрано" else "Добавить $onCount", Modifier.padding(16.dp), enabled = onCount > 0) { save() }
    }) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (subtitle.isNotEmpty()) item {
                Text(subtitle, color = p.secondary, fontSize = 15.sp, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic, modifier = Modifier.padding(horizontal = 4.dp))
            }
            if (snap.accounts.isNotEmpty() && items.any { it.kind != ItemKind.REC }) item {
                Group("Счёт") { AccountChooser(snap.accounts, acc) { acc = it } }
            }
            itemsIndexed(items, key = { _, it -> it.id }) { i, it ->
                ReviewCard(it, texts[i], snap, { t -> texts[i] = t }) { f -> upd(i, f) }
            }
        }
    }
}

@Composable
private fun ReviewCard(item: ParsedItem, amountText: String, snap: Snapshot, onAmount: (String) -> Unit, upd: ((ParsedItem) -> Unit) -> Unit) {
    val p = LocalPal.current
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().alpha(if (item.on) 1f else 0.5f).cardBg().padding(14.dp).animateContentSize(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(if (item.on) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, tint = if (item.on) p.accent else p.tertiary,
            modifier = Modifier.size(28.dp).pressable({ Haptic.select(); upd { it.on = !it.on } }))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when (item.kind) {
                ItemKind.DEBT -> Header(Icons.Rounded.AccountBalance, p.accent, snap.debts.firstOrNull { it.id == item.debtId }?.name ?: item.note, "платёж по долгу")
                ItemKind.GOAL -> Header(Icons.Rounded.Savings, p.inc, snap.goals.firstOrNull { it.id == item.goalId }?.name ?: item.note, if (item.sign < 0) "из копилки" else "в копилку")
                ItemKind.REC -> Header(Icons.Rounded.Repeat, p.accent, "Регулярный платёж", if (item.recYearly) "раз в год, ${item.recDay}-го" else "каждый месяц, ${item.recDay}-го")
                ItemKind.TX -> Box {
                    val c = Catalog.cat(item.cat)
                    Row(Modifier.pressable({ menu = true }), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Tile(c.icon, c.color, 30.dp)
                        Text(c.name, fontWeight = FontWeight.SemiBold, color = p.text, fontSize = 16.sp)
                        Text(if (item.type == TxKind.INC) "доход" else "расход", fontSize = 12.sp, color = if (item.type == TxKind.INC) p.inc else p.secondary)
                        Icon(Icons.Rounded.UnfoldMore, null, tint = p.secondary, modifier = Modifier.size(16.dp))
                    }
                    DropdownMenu(menu, { menu = false }, Modifier.heightIn(max = 420.dp)) {
                        Text("Расходы", color = p.secondary, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 14.dp, vertical = 4.dp))
                        Catalog.expense.forEach { c -> DropdownMenuItem({ Text(c.name) }, { menu = false; upd { it.type = TxKind.EXP; it.cat = c.id } }, leadingIcon = { Icon(c.icon, null, tint = c.color) }) }
                        Text("Доходы", color = p.secondary, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 14.dp, vertical = 4.dp))
                        Catalog.income.forEach { c -> DropdownMenuItem({ Text(c.name) }, { menu = false; upd { it.type = TxKind.INC; it.cat = c.id } }, leadingIcon = { Icon(c.icon, null, tint = c.color) }) }
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(DF.dayLabel(item.date), color = p.secondary, fontSize = 14.sp, modifier = Modifier.weight(1f))
                BasicTextField(amountText, { s -> onAmount(s.filter { it.isDigit() || it == ',' || it == '.' }) },
                    textStyle = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = p.text, textAlign = TextAlign.End),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true, cursorBrush = SolidColor(p.accent),
                    modifier = Modifier.widthIn(min = 40.dp, max = 140.dp).clip(RoundedCornerShape(10.dp)).background(p.soft).padding(horizontal = 10.dp, vertical = 6.dp))
                Text(" ₽", color = p.secondary)
            }
            if (item.kind == ItemKind.TX || item.kind == ItemKind.REC) {
                Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(p.soft)) {
                    KTextField(item.note, { s -> upd { it.note = s.take(80) } }, if (item.kind == ItemKind.REC) "Название" else "Заметка",
                        textStyle = TextStyle(fontSize = 15.sp))
                }
            }
            snap.accounts.firstOrNull { it.id == item.acc }?.let { a ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Rounded.CreditCard, null, tint = p.secondary, modifier = Modifier.size(14.dp))
                    Text(a.name, fontSize = 12.sp, color = p.secondary)
                }
            }
        }
    }
}

@Composable
private fun Header(icon: androidx.compose.ui.graphics.vector.ImageVector, color: androidx.compose.ui.graphics.Color, title: String, sub: String) {
    val p = LocalPal.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Tile(icon, color, 30.dp)
        Column {
            Text(title, fontWeight = FontWeight.SemiBold, color = p.text, fontSize = 16.sp)
            Text(sub, fontSize = 12.sp, color = p.secondary)
        }
    }
}
