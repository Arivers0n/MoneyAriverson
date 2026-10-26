package ru.koshelek.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.ceil

val Palette = listOf("2B47C9", "17805A", "C2621F", "8A4FD0", "1A9BB0", "D04F6E", "9A8A1F", "4E5E9E")

private data class Edit<T>(val item: T?)

// MARK: Копилки — расчёты

object Savings {
    fun monthlyPace(g: Goal): Double {
        val from = LocalDate.now().minusDays(90)
        val sum = g.log.filter { !it.date.isBefore(from) }.sumOf { it.amount }
        val created = epochToDate(g.created)
        val span = (ChronoUnit.DAYS.between(if (created.isAfter(from)) created else from, LocalDate.now()) / 30.0).coerceIn(1.0, 3.0)
        return maxOf(0.0, sum / span)
    }
    fun forecast(g: Goal): Pair<String, Boolean>? {
        val left = g.target - g.saved
        if (g.target <= 0 || left <= 0) return null
        val pace = monthlyPace(g)
        g.deadline?.let { dl ->
            val months = maxOf(1, ChronoUnit.MONTHS.between(LocalDate.now(), dl).toInt() + 1)
            val need = left / months
            if (dl.isBefore(LocalDate.now())) return "Срок прошёл — осталось ${Fmt.rubU(left)}" to false
            if (pace >= need * 0.95) return "Успеваете к ${DF.short(dl)}: откладываете ~${Fmt.rubU(pace)} в месяц" to true
            return "Чтобы успеть к ${DF.short(dl)}, нужно ${Fmt.rubU(need)} в месяц" + (if (pace > 0) " (сейчас ~${Fmt.rubU(pace)})" else "") to false
        }
        if (pace <= 0) return "Пополните копилку — и я посчитаю, когда наберётся сумма" to true
        val date = LocalDate.now().plusMonths(ceil(left / pace).toLong())
        return "При текущем темпе — к ${DF.s(date, "LLLL yyyy")} (~${Fmt.rubU(pace)} в месяц)" to true
    }
    fun cushionTarget(txs: List<Tx>): Double {
        val now = YearMonth.now()
        val vals = (1..3).map { totals(now.minusMonths(it.toLong()), txs).exp }.filter { it > 0 }
        val avg = if (vals.isEmpty()) totals(now, txs).exp else vals.average()
        val t = avg * 3
        return if (t > 0) ceil(t / 1000) * 1000 else 0.0
    }
}

// MARK: Шторка «Бюджеты | Копилки»

@Composable
fun GoalsScreen(initialTab: Int) {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    var tab by remember { mutableIntStateOf(initialTab) }
    var limit by remember { mutableStateOf<Edit<String>?>(null) }
    var goalEdit by remember { mutableStateOf<Edit<Goal>?>(null) }
    var goalAdd by remember { mutableStateOf<String?>(null) }
    var cushionPreset by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        Backdrop()
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                Box(Modifier.align(Alignment.Center)) {
                    PillToggle(listOf(PillOption(0, "Бюджеты", Icons.Rounded.DataUsage), PillOption(1, "Копилки", Icons.Rounded.Savings)), tab) { tab = it }
                }
                Row(Modifier.fillMaxWidth().align(Alignment.Center)) {
                    GlassCircle(Icons.Rounded.Close) { Router.close() }
                    Spacer(Modifier.weight(1f))
                    GlassCircle(Icons.Rounded.Add, desc = "Добавить") { if (tab == 0) limit = Edit(null) else { cushionPreset = false; goalEdit = Edit(null) } }
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                Column(Modifier.widthIn(max = 720.dp).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 10.dp, bottom = 30.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    if (tab == 0) Budgets(snap) { limit = Edit(it) }
                    else SavingsTab(snap, { goalEdit = Edit(it) }, { goalAdd = it.id }) { cushionPreset = true; goalEdit = Edit(null) }
                }
            }
        }
    }
    Overlay(limit, { limit = null }) { e -> LimitForm(e.item, snap.prefs) { limit = null } }
    Overlay(goalEdit, { goalEdit = null }) { e -> GoalForm(e.item, snap, cushionPreset) { goalEdit = null } }
    Overlay(goalAdd, { goalAdd = null }) { id -> snap.goals.firstOrNull { it.id == id }?.let { GoalAddSheet(it, snap) { goalAdd = null } } }
}

@Composable
private fun Budgets(snap: Snapshot, onEdit: (String?) -> Unit) {
    val p = LocalPal.current
    val month = snap.txs.filter { it.kind == TxKind.EXP && YearMonth.now().contains(it.date) }
    val spentBy = month.groupBy { it.cat }.mapValues { e -> e.value.sumOf { it.amount } }
    val total = month.sumOf { it.amount }
    val budget = snap.prefs.budget
    val cats = snap.prefs.catLimits.filter { it.value > 0 }.entries.sortedByDescending { it.value }
    if (budget <= 0 && cats.isEmpty()) {
        EmptyState(Icons.Rounded.DataUsage, "Бюджетов пока нет", "Задайте лимит на месяц — общий или на категорию, например «Кафе — 8 000 ₽». Я покажу, сколько осталось, и предупрежу заранее.")
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Text("Создать бюджет", fontWeight = FontWeight.SemiBold, color = p.text, modifier = Modifier.glass(RoundedCornerShape(50)).pressable({ onEdit(null) }).padding(horizontal = 24.dp, vertical = 15.dp))
        }
    } else {
        val today = LocalDate.now()
        val daysLeft = YearMonth.now().lengthOfMonth() - today.dayOfMonth + 1
        Text("${DF.s(today, "LLLL").cap()} · осталось $daysLeft ${plural(daysLeft, "день", "дня", "дней")}", color = p.secondary, fontSize = 15.sp,
            modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        if (budget > 0) LimitCard(Icons.Rounded.Layers, p.accent, "Все расходы", total, budget, daysLeft) { onEdit("all") }
        cats.forEach { (id, lim) -> val c = Catalog.cat(id); LimitCard(c.icon, c.color, c.name, spentBy[id] ?: 0.0, lim, daysLeft) { onEdit(id) } }
    }
}

@Composable
private fun LimitCard(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, title: String, spent: Double, limit: Double, daysLeft: Int, onTap: () -> Unit) {
    val p = LocalPal.current
    val pr = if (limit > 0) spent / limit else 0.0
    val left = limit - spent
    val bar = if (pr > 1) p.exp else if (pr > 0.8) p.warn else color
    val masked = Look.hideAmounts
    Column(Modifier.fillMaxWidth().cardBg(RoundedCornerShape(24.dp)).pressable(onTap, 0.98f).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Tile(icon, color, 46.dp)
            Column(Modifier.weight(1f)) {
                Text(title, fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(if (masked) "•••" else "${Fmt.rubU(spent)} из ${Fmt.rubU(limit)}", fontSize = 14.sp, color = p.secondary)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(if (masked) "•••" else if (left >= 0) Fmt.rubU(left) else "−" + Fmt.rubU(-left), fontSize = 19.sp, fontWeight = FontWeight.SemiBold, color = if (left >= 0) p.text else p.exp)
                Text(if (left >= 0) "осталось" else "перерасход", fontSize = 12.sp, color = p.secondary)
            }
        }
        ProgressBar(pr, bar, 8.dp)
        if (left > 0 && daysLeft > 0 && !masked) Text("≈ ${Fmt.rubU(left / daysLeft)} в день", fontSize = 13.sp, color = p.secondary)
    }
}

@Composable
private fun LimitForm(cat: String?, prefs: SpacePrefs, onClose: () -> Unit) {
    val p = LocalPal.current
    var pick by remember { mutableStateOf(cat ?: "all") }
    fun current(id: String) = if (id == "all") prefs.budget else prefs.catLimits[id] ?: 0.0
    var amount by remember { mutableStateOf(current(pick).takeIf { it > 0 }?.let { Fmt.input(it) } ?: "") }
    val isNew = cat == null
    fun write(v: Double) {
        val np = if (pick == "all") prefs.copy(budget = v) else prefs.copy(catLimits = if (v > 0) prefs.catLimits + (pick to v) else prefs.catLimits - pick)
        Store.savePrefs(np); Haptic.success(); onClose()
    }
    SheetScaffold(if (isNew) "Новый бюджет" else if (pick == "all") "Все расходы" else Catalog.cat(pick).name, onClose = onClose, bottom = {
        PrimaryButton("Сохранить", Modifier.padding(16.dp), enabled = (parseAmount(amount) ?: 0.0) > 0) { write(maxOf(0.0, parseAmount(amount) ?: 0.0)) }
    }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (isNew) Group("На что") {
                Chips {
                    Chip("Все расходы", pick == "all", p.accent) { pick = "all"; amount = current("all").takeIf { it > 0 }?.let { Fmt.input(it) } ?: "" }
                    Catalog.expense.filter { it.id != "savings" }.forEach { c -> Chip(c.name, pick == c.id, c.color) { pick = c.id; amount = current(c.id).takeIf { it > 0 }?.let { Fmt.input(it) } ?: "" } }
                }
            }
            Group("Лимит на месяц", "Каждый месяц лимит начинается заново. Предупрежу, когда потрачено больше 80%.") { FieldRow("Сумма, ₽", amount, { amount = it }, "8 000") }
            if (!isNew) Text("Удалить бюджет", color = p.exp, fontWeight = FontWeight.Medium, modifier = Modifier.align(Alignment.CenterHorizontally).pressable({ write(0.0) }).padding(10.dp))
        }
    }
}

// MARK: Копилки

@Composable
private fun SavingsTab(snap: Snapshot, onEdit: (Goal?) -> Unit, onAdd: (Goal) -> Unit, onCushion: () -> Unit) {
    val p = LocalPal.current
    val goals = snap.goals
    val active = goals.filter { it.target <= 0 || it.saved < it.target }
    val done = goals.filter { it.target > 0 && it.saved >= it.target }
    val masked = Look.hideAmounts
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Накоплено", color = p.secondary, fontSize = 15.sp)
        RollingAmount(goals.sumOf { it.saved }, TextStyle(fontSize = 46.sp, fontWeight = FontWeight.Bold, fontFamily = p.fontFamily), p.text, masked)
        val month = goals.flatMap { it.log }.filter { YearMonth.now().contains(it.date) }.sumOf { it.amount }
        if (month != 0.0 && !masked) Text((if (month > 0) "↗ +" else "↘ −") + Fmt.rubU(month) + " в этом месяце", color = if (month > 0) p.inc else p.exp, fontWeight = FontWeight.Medium, fontSize = 15.sp)
    }
    if (goals.isEmpty()) Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Начните копить", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        Text("Создайте копилку и включите автоправила: например, откладывать 10% с каждой зарплаты или округлять каждую трату до 100 ₽ и складывать сдачу.", color = p.secondary, fontSize = 15.sp)
        PrimaryButton("Создать копилку") { onEdit(null) }
    }
    active.forEach { g -> GoalCard(g, masked, { onEdit(g) }) { onAdd(g) } }
    if (done.isNotEmpty()) {
        Text("Достигнуто", fontWeight = FontWeight.SemiBold, color = p.secondary, fontSize = 15.sp)
        done.forEach { g -> GoalCard(g, masked, { onEdit(g) }) { onAdd(g) } }
    }
    val cushion = Savings.cushionTarget(snap.txs)
    if (cushion > 0 && goals.none { it.name.lowercase().contains("подушк") }) {
        Column(Modifier.fillMaxWidth().cardBg(RoundedCornerShape(24.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Rounded.Shield, null, tint = p.text, modifier = Modifier.size(18.dp)); Text("Подушка безопасности", fontWeight = FontWeight.SemiBold, color = p.text)
            }
            Text("Запас на 3 месяца ваших расходов — около ${Fmt.rubU(cushion)}. Он спасает при потере работы или болезни и избавляет от новых кредитов.", fontSize = 14.sp, color = p.secondary)
            Text("Создать подушку", color = p.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.pressable(onCushion))
        }
    }
}

@Composable
private fun GoalCard(g: Goal, masked: Boolean, onEdit: () -> Unit, onAdd: () -> Unit) {
    val p = LocalPal.current
    val color = hexColor(g.hex)
    val saved = g.saved
    val pr = if (g.target > 0) saved / g.target else 0.0
    val fc = Savings.forecast(g)
    Column(Modifier.fillMaxWidth().cardBg(RoundedCornerShape(24.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(42.dp).clip(CircleShape).background(color.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                Icon(goalIcon(g.symbol), null, tint = color, modifier = Modifier.size(20.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(g.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(if (masked) "•••" else if (g.target > 0) "${Fmt.rubU(saved)} из ${Fmt.rubU(g.target)}" else Fmt.rubU(saved), fontSize = 14.sp, color = p.secondary)
            }
            if (g.target > 0) Text("${(minOf(1.0, pr) * 100).toInt()}%", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = color)
        }
        if (g.target > 0) ProgressBar(pr, color, 8.dp)
        if (fc != null) Text(fc.first, fontSize = 13.sp, color = if (fc.second) p.secondary else p.warn)
        else if (g.target > 0 && saved >= g.target) Text("Цель достигнута 🎉", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.inc)
        val rules = listOfNotNull(if (g.autoPercent > 0) "${Fmt.input(g.autoPercent)}% с каждого дохода" else null, if (g.roundUp > 0) "сдача с трат до ${g.roundUp} ₽" else null)
        if (rules.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(Icons.Rounded.AutoFixHigh, null, tint = p.secondary, modifier = Modifier.size(14.dp)); Text(rules.joinToString(" · "), fontSize = 12.sp, color = p.secondary)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Пополнить", color = Color.White, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, fontSize = 15.sp,
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(50)).background(color).pressable(onAdd).padding(vertical = 10.dp))
            Text("Настроить", color = p.text, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, fontSize = 15.sp,
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(50)).background(p.soft).pressable(onEdit).padding(vertical = 10.dp))
        }
    }
}

fun goalIcon(sf: String) = when (sf) {
    "shield.lefthalf.filled" -> Icons.Rounded.Shield
    else -> Icons2.of(sf)
}

private val goalPresets = listOf("Подушка безопасности" to "shield.lefthalf.filled", "Отпуск" to "airplane", "Новый телефон" to "iphone",
    "Машина" to "car.fill", "Ремонт" to "hammer.fill", "Учёба" to "graduationcap.fill", "Подарки" to "gift.fill")
private val goalSymbols = listOf("banknote.fill", "shield.lefthalf.filled", "airplane", "iphone", "car.fill", "house.fill", "hammer.fill",
    "graduationcap.fill", "gift.fill", "heart.fill", "gamecontroller.fill", "laptopcomputer", "bicycle", "pawprint.fill", "star.fill", "sparkles")

@Composable
private fun GoalForm(goal: Goal?, snap: Snapshot, cushion: Boolean, onClose: () -> Unit) {
    val p = LocalPal.current
    var name by remember { mutableStateOf(goal?.name ?: "") }
    var target by remember { mutableStateOf(goal?.takeIf { it.target > 0 }?.let { Fmt.input(it.target) } ?: "") }
    var hasDeadline by remember { mutableStateOf(goal?.deadline != null) }
    var deadline by remember { mutableStateOf(goal?.deadline ?: LocalDate.now().plusMonths(6)) }
    var hex by remember { mutableStateOf(goal?.hex ?: Palette[snap.goals.size % Palette.size]) }
    var symbol by remember { mutableStateOf(goal?.symbol ?: "banknote.fill") }
    var autoPercent by remember { mutableDoubleStateOf(goal?.autoPercent ?: 0.0) }
    var roundUp by remember { mutableIntStateOf(goal?.roundUp ?: 0) }
    var confirm by remember { mutableStateOf(false) }
    fun pick(i: Int) {
        name = goalPresets[i].first; symbol = goalPresets[i].second
        if (i == 0) { val c = Savings.cushionTarget(snap.txs); if (c > 0) target = Fmt.input(c); autoPercent = maxOf(autoPercent, 10.0) }
    }
    LaunchedEffect(Unit) { if (goal == null && cushion) pick(0) }
    val color = hexColor(hex)

    SheetScaffold(if (goal == null) "Новая копилка" else "Копилка", onClose = onClose, bottom = {
        PrimaryButton("Сохранить", Modifier.padding(16.dp), enabled = name.isNotBlank()) {
            val t = maxOf(0.0, parseAmount(target) ?: 0.0)
            Store.saveGoal((goal ?: Goal()).copy(name = name.trim(), target = t, deadline = if (hasDeadline) deadline else null, hex = hex, symbol = symbol,
                autoPercent = autoPercent, roundUp = roundUp))
            Haptic.success(); onClose()
        }
    }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (goal == null) Group { Chips { goalPresets.forEachIndexed { i, (n, _) -> Chip(n, name == n) { pick(i) } } } }
            Group {
                KTextField(name, { name = it }, "На что копим")
                Divider1(); FieldRow("Сколько нужно", target, { target = it }, "необязательно")
                Divider1(); SwitchRow("К определённой дате", hasDeadline) { hasDeadline = it }
                if (hasDeadline) DateRow("Дата", deadline) { deadline = it }
            }
            Group("Автоправила", "Процент с дохода: когда записываете зарплату или другой доход, часть сразу уходит в копилку. Сдача: трата 270 ₽ округляется до 300 ₽, а 30 ₽ откладываются сюда.") {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("С каждого дохода", color = p.text, modifier = Modifier.weight(1f))
                    Text(if (autoPercent > 0) "${autoPercent.toInt()}%" else "выкл", color = p.secondary, modifier = Modifier.padding(end = 10.dp))
                    Stepper({ autoPercent = maxOf(0.0, autoPercent - 5) }, { autoPercent = minOf(50.0, autoPercent + 5) })
                }
                Divider1()
                Text("Сдача с трат", color = p.text, modifier = Modifier.padding(start = 16.dp, top = 12.dp))
                Segmented(listOf("выкл", "до 10 ₽", "до 50 ₽", "до 100 ₽"), listOf(0, 10, 50, 100).indexOf(roundUp).coerceAtLeast(0), { roundUp = listOf(0, 10, 50, 100)[it] })
            }
            Group("Значок и цвет") {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    goalSymbols.chunked(8).forEach { row ->
                        Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                            row.forEach { s ->
                                Box(Modifier.size(36.dp).clip(CircleShape).background(if (symbol == s) color else color.copy(alpha = 0.12f)).pressable({ Haptic.select(); symbol = s }, 0.85f),
                                    contentAlignment = Alignment.Center) { Icon(goalIcon(s), null, tint = if (symbol == s) Color.White else color, modifier = Modifier.size(18.dp)) }
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        Palette.forEach { h ->
                            Box(Modifier.size(30.dp).clip(CircleShape).background(hexColor(h)).then(if (hex == h) Modifier.border(2.5.dp, p.text, CircleShape) else Modifier)
                                .pressable({ Haptic.select(); hex = h }, 0.85f))
                        }
                    }
                }
            }
            if (goal != null && goal.log.isNotEmpty()) Group("История") {
                goal.log.sortedByDescending { it.date }.take(30).forEach { e ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                        Text(DF.short(e.date), color = p.secondary, fontSize = 14.sp, modifier = Modifier.weight(1f))
                        Text((if (e.amount >= 0) "+" else "−") + Fmt.rubU(e.amount), color = if (e.amount >= 0) p.inc else p.exp, fontSize = 14.sp)
                    }
                }
            }
            if (goal != null) Text("Удалить копилку", color = p.exp, fontWeight = FontWeight.Medium, modifier = Modifier.align(Alignment.CenterHorizontally).pressable({ confirm = true }).padding(10.dp))
        }
    }
    if (confirm && goal != null) Confirm("Удалить копилку? Накопленное останется на ваших счетах — удалится только учёт.", "Удалить", { Store.delete("goal", goal.id); onClose() }) { confirm = false }
}

@Composable
private fun GoalAddSheet(goal: Goal, snap: Snapshot, onClose: () -> Unit) {
    val p = LocalPal.current
    var take by remember { mutableStateOf(false) }
    var amount by remember { mutableStateOf("") }
    var toBudget by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    fun save() {
        val v = parseAmount(amount)?.takeIf { it > 0 } ?: run { err = "Введите сумму больше нуля."; return }
        val before = goal.saved
        if (take && v > before) { err = "В копилке только ${Fmt.rubU(before)}."; return }
        val ng = goal.copy(log = goal.log + GoalEntry(LocalDate.now(), if (take) -v else v))
        Store.saveGoal(ng)
        if (!take && toBudget) {
            val acc = snap.accounts.firstOrNull { it.id == Settings.str("lastAcc") }?.id ?: snap.accounts.firstOrNull()?.id
            Store.saveTx(Tx(kind = TxKind.EXP, amount = v, cat = "savings", note = goal.name, acc = acc))
        }
        onClose()
        if (!take && goal.target > 0 && before < goal.target && ng.saved >= goal.target) Router.celebrate = "Цель «${goal.name}» достигнута!" to "Накоплено ${Fmt.rubU(ng.saved)}. Время тратить с удовольствием."
        else { Haptic.success(); Router.say(if (take) "Взято ${Fmt.rubU(v)}" else "+${Fmt.rubU(v)} в «${goal.name}»") }
    }
    SheetScaffold(goal.name, onClose = onClose, bottom = { PrimaryButton(if (take) "Взять" else "Положить", Modifier.padding(16.dp)) { save() } }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(if (goal.target > 0) "В копилке ${Fmt.rubU(goal.saved)} из ${Fmt.rubU(goal.target)}" else "В копилке ${Fmt.rubU(goal.saved)}", color = p.secondary, modifier = Modifier.padding(horizontal = 4.dp))
            Group {
                Segmented(listOf("Положить", "Взять"), if (take) 1 else 0, { take = it == 1 })
                FieldRow("Сумма, ₽", amount, { amount = it }, "0")
                if (!take) Chips { listOf(500.0, 1000.0, 5000.0, 10000.0).forEach { v -> Chip("+" + Fmt.rubU(v), false) { amount = Fmt.input((parseAmount(amount) ?: 0.0) + v) } } }
            }
            if (!take) Group(footer = "Включите, если хотите видеть отложенное в расходах — тогда остаток месяца будет честнее.") { SwitchRow("Учесть в расходах месяца", toBudget) { toBudget = it } }
            err?.let { Text(it, color = p.exp) }
        }
    }
}

// MARK: Счета

@Composable
fun AccountsScreen() {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    var edit by remember { mutableStateOf<Edit<Account>?>(null) }
    SheetScaffold("Счета", Icons.Rounded.AccountBalanceWallet, trailing = { GlassCircle(Icons.Rounded.Add, desc = "Добавить счёт") { edit = Edit(null) } }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            AccRow(null, "Все счета", if (snap.accounts.isEmpty()) snap.txs.sumOf { it.signed } else snap.accounts.sumOf { balance(it, snap.txs) }, p.inc, null)
            snap.accounts.forEach { a -> AccRow(a.id, a.name, balance(a, snap.txs), hexColor(a.hex)) { edit = Edit(a) } }
            Text(if (snap.accounts.isEmpty()) "Добавьте карту, наличные или накопительный счёт — баланс каждого будет считаться сам." else "Удерживайте счёт, чтобы изменить его",
                color = if (snap.accounts.isEmpty()) p.secondary else p.tertiary, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(20.dp))
        }
    }
    Overlay(edit, { edit = null }) { e -> AccountForm(e.item, snap) { edit = null } }
}

@Composable
private fun AccRow(id: String?, title: String, amount: Double, color: Color, onLong: (() -> Unit)?) {
    val p = LocalPal.current
    RowCard(Modifier.pressable({ Haptic.select(); Router.accFilter = id; Router.close() }, 0.98f, onLongClick = onLong)) {
        Tile(if (id == null) Icons.Rounded.AccountBalanceWallet else Icons.Rounded.CreditCard, color, 46.dp)
        Text(title, fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(if (Look.hideAmounts) "•••" else Fmt.rub(amount), fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.text)
        if (Router.accFilter == id) Icon(Icons.Rounded.Check, null, tint = p.accent)
    }
}

@Composable
private fun AccountForm(a: Account?, snap: Snapshot, onClose: () -> Unit) {
    val p = LocalPal.current
    var name by remember { mutableStateOf(a?.name ?: "") }
    var start by remember { mutableStateOf(a?.let { Fmt.input(it.start) } ?: "") }
    var confirm by remember { mutableStateOf(false) }
    SheetScaffold(if (a == null) "Новый счёт" else "Счёт", onClose = onClose, bottom = {
        PrimaryButton("Сохранить", Modifier.padding(16.dp), enabled = name.isNotBlank()) {
            val s = start.replace("−", "-").let { t -> (if (t.trim().startsWith("-")) -1 else 1) * (parseAmount(t.replace("-", "")) ?: 0.0) }
            Store.saveAccount((a ?: Account(hex = Palette[snap.accounts.size % Palette.size])).copy(name = name.trim(), start = s))
            Haptic.success(); onClose()
        }
    }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (a == null) Group { Chips { listOf("Карта", "Наличные", "Накопительный", "Кредитка").forEach { n -> Chip(n, name == n) { name = n } } } }
            Group(footer = "Баланс дальше считается сам по операциям с этим счётом.") {
                KTextField(name, { name = it }, "Название")
                Divider1()
                KTextField(start, { s -> start = s.filter { it.isDigit() || it in ",.- " } }, "Сколько на нём сейчас, ₽",
                    keyboard = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number))
            }
            if (a != null) Text("Удалить счёт", color = p.exp, fontWeight = FontWeight.Medium, modifier = Modifier.align(Alignment.CenterHorizontally).pressable({ confirm = true }).padding(10.dp))
        }
    }
    if (confirm && a != null) Confirm("Операции останутся, но без счёта. Удалить?", "Удалить", {
        Store.delete("acc", a.id); if (Router.accFilter == a.id) Router.accFilter = null; onClose()
    }) { confirm = false }
}
