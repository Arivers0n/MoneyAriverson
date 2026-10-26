package ru.koshelek.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.ceil

private data class PayTarget(val debtId: String, val index: Int)
private data class Editing<T>(val item: T?)

@Composable
fun PaymentsScreen() {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    val debts = snap.debts
    var calMonth by remember { mutableStateOf(YearMonth.now()) }
    var selDay by remember { mutableStateOf<LocalDate?>(null) }
    var form by remember { mutableStateOf<Editing<Debt>?>(null) }
    var pay by remember { mutableStateOf<PayTarget?>(null) }
    var detail by remember { mutableStateOf<String?>(null) }
    var rec by remember { mutableStateOf<Editing<Recurring>?>(null) }
    var showClosed by remember { mutableStateOf(false) }
    val outOpen = debts.filter { it.isOut && !it.isClosed }
    val inOpen = debts.filter { !it.isOut && !it.isClosed }
    val closed = debts.filter { it.isClosed }
    val masked = Look.hideAmounts
    fun m(v: Double) = if (masked) "•••" else Fmt.rubU(v)

    SheetScaffold("Платежи", Icons.Rounded.CalendarMonth, trailing = { GlassCircle(Icons.Rounded.Add, desc = "Добавить долг") { form = Editing(null) } }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // Шапка
            Column(Modifier.fillMaxWidth().cardBg(RoundedCornerShape(24.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (debts.isEmpty()) {
                    Caps("Кредиты и долги")
                    Text("Добавьте кредит, кредитку, микрозайм или долг знакомому. Приложение построит график, напомнит о платежах и посчитает, когда вы станете свободны от долгов.", color = p.text, fontSize = 15.sp)
                    PrimaryButton("Добавить долг") { form = Editing(null) }
                } else {
                    val next = allInstallments(debts).filter { it.debt.isOut && it.isOpen }.minByOrNull { it.due }
                    val freedom = outOpen.mapNotNull { it.lastOpenDue }.maxOrNull()
                    Column { Caps("Осталось выплатить"); Text(m(outOpen.sumOf { it.remaining }), fontSize = 38.sp, fontWeight = FontWeight.Bold, color = p.text, maxLines = 1) }
                    if (next != null) {
                        val (rt, bad) = relDays(next.due)
                        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(p.soft).pressable({ pay = PayTarget(next.debt.id, next.i) }, 0.98f).padding(12.dp)) {
                            Text("Ближайший платёж", fontSize = 12.sp, color = p.secondary)
                            Text("${next.debt.name} · ${m(next.amount)}", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text)
                            Text("${DF.short(next.due)}, $rt", fontSize = 14.sp, color = if (bad) p.exp else p.secondary)
                        }
                    } else if (outOpen.isEmpty()) Text("Все ваши долги закрыты. Так держать.", color = p.text)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatBox("Уже выплачено", m(debts.filter { it.isOut }.sumOf { it.paidSum }), Modifier.weight(1f))
                        StatBox("Свобода от долгов", freedom?.let { DF.s(it, "LLL yyyy").replace(".", "").cap() } ?: "—", Modifier.weight(1f))
                    }
                    freedom?.let { Text("Последний платёж — ${spanText(it)}, если платить по графику.", fontSize = 13.sp, color = p.secondary) }
                }
            }
            // Просрочки
            val ov = allInstallments(debts).filter { it.st == InstStatus.OVERDUE && it.debt.isOut }.sortedBy { it.due }
            ov.firstOrNull()?.let { x ->
                AlertBox(p.exp, "${ov.size} ${plural(ov.size, "просроченный платёж", "просроченных платежа", "просроченных платежей")}. ${x.debt.name}: ${m(x.amount)}, срок был ${DF.short(x.due)}. Нажмите, чтобы отметить оплату.") { pay = PayTarget(x.debt.id, x.i) }
            }
            // Плитки
            if (debts.isNotEmpty()) {
                val monthly = allInstallments(debts).filter { it.debt.isOut && YearMonth.now().contains(it.due) }.sumOf { it.plan }
                val avg = averageIncome(snap.txs)
                val load = if (avg > 0) monthly / avg else null
                val streak = onTimeStreak(debts)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MiniTile("В этом месяце", m(monthly), "по графику", p.text, Modifier.weight(1f))
                    MiniTile("Нагрузка", load?.let { "${Math.round(it * 100)}%" } ?: "—",
                        when { load == null -> "нет доходов"; load < 0.3 -> "от дохода, норма"; load < 0.5 -> "от дохода, много"; else -> "от дохода, опасно" },
                        when { load == null -> p.text; load < 0.3 -> p.inc; load < 0.5 -> p.warn; else -> p.exp }, Modifier.weight(1f))
                    MiniTile("В срок подряд", "$streak", if (streak >= 6) "железно" else if (streak >= 3) "отличная серия" else plural(streak, "платёж", "платежа", "платежей"),
                        if (streak >= 3) p.inc else p.text, Modifier.weight(1f))
                }
            }
            // Календарь
            val inst = allInstallments(debts)
            val list = (selDay?.let { d -> inst.filter { it.due == d } } ?: inst.filter { calMonth.contains(it.due) }).sortedBy { it.due }
            Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(DF.month(calMonth), fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text, modifier = Modifier.weight(1f))
                    Row(Modifier.clip(RoundedCornerShape(50)).background(p.soft), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.ChevronLeft, null, tint = p.accent, modifier = Modifier.size(34.dp, 30.dp).pressable({ calMonth = calMonth.minusMonths(1); selDay = null }))
                        Text("Сегодня", color = p.accent, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.pressable({ calMonth = YearMonth.now(); selDay = LocalDate.now() }).padding(horizontal = 6.dp))
                        Icon(Icons.Rounded.ChevronRight, null, tint = p.accent, modifier = Modifier.size(34.dp, 30.dp).pressable({ calMonth = calMonth.plusMonths(1); selDay = null }))
                    }
                }
                CalendarGrid(calMonth, inst.groupBy { it.due }, selDay) { selDay = if (selDay == it) null else it }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    LegendDot(p.accent, "Предстоит"); LegendDot(p.inc, "В срок"); LegendDot(p.warn, "С опозданием"); LegendDot(p.exp, "Просрочен")
                }
                Divider1()
                Row {
                    Text((selDay?.let { DF.s(it, "d MMMM") } ?: "Платежи в этом месяце").uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = p.secondary, modifier = Modifier.weight(1f))
                    if (list.isNotEmpty()) Text(m(list.sumOf { it.amount }), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = p.secondary)
                }
                if (list.isEmpty()) Text(if (debts.isEmpty()) "Здесь появится график платежей" else "Платежей нет", color = p.secondary, fontSize = 14.sp,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), textAlign = TextAlign.Center)
                list.forEach { x -> InstRow(x, masked) { pay = PayTarget(x.debt.id, x.i) } }
            }
            RecurringCard(snap, masked) { rec = Editing(it) }
            // Списки
            if (outOpen.isNotEmpty()) Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SectionTitle("Мои кредиты и долги")
                outOpen.sortedByDescending { it.remaining }.forEach { d -> DebtLink(d, masked) { detail = d.id } }
            }
            if (inOpen.isNotEmpty()) Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SectionTitle("Мне должны · ${m(inOpen.sumOf { it.remaining })}")
                inOpen.forEach { d -> DebtLink(d, masked) { detail = d.id } }
            }
            if (closed.isNotEmpty()) Column(Modifier.fillMaxWidth().cardBg().padding(16.dp).animateContentSize(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(Modifier.fillMaxWidth().pressable({ showClosed = !showClosed }, 0.99f), verticalAlignment = Alignment.CenterVertically) {
                    Text("Закрытые долги · ${closed.size}", fontWeight = FontWeight.SemiBold, color = p.text, modifier = Modifier.weight(1f))
                    Icon(if (showClosed) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null, tint = p.secondary)
                }
                if (showClosed) closed.forEach { d -> DebtLink(d, masked) { detail = d.id } }
            }
            Advice(outOpen)
        }
    }

    Overlay(detail, { detail = null }) { id ->
        snap.debts.firstOrNull { it.id == id }?.let { d -> DebtDetail(d, { detail = null }, { form = Editing(d) }, { pay = PayTarget(d.id, it) }) }
            ?: LaunchedEffect(Unit) { detail = null }
    }
    Overlay(form, { form = null }) { e -> DebtForm(e.item) { form = null } }
    Overlay(pay, { pay = null }) { t -> snap.debts.firstOrNull { it.id == t.debtId }?.let { PaySheet(it, t.index) { pay = null } } }
    Overlay(rec, { rec = null }) { e -> RecurringForm(e.item) { rec = null } }
}

@Composable
private fun Caps(t: String) = Text(t.uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp, color = LocalPal.current.secondary)

@Composable
private fun AlertBox(color: Color, text: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(color.copy(alpha = 0.14f)).pressable(onClick, 0.98f).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Rounded.Warning, null, tint = color, modifier = Modifier.size(20.dp))
        Text(text, color = LocalPal.current.text, fontSize = 14.sp)
    }
}

@Composable
private fun MiniTile(title: String, value: String, sub: String, color: Color, modifier: Modifier) {
    val p = LocalPal.current
    Column(modifier.cardBg(RoundedCornerShape(18.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, fontSize = 12.sp, color = p.secondary, maxLines = 1)
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = color, maxLines = 1)
        Text(sub, fontSize = 11.sp, color = p.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun LegendDot(c: Color, t: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(c)); Text(t, fontSize = 11.sp, color = LocalPal.current.secondary)
    }
}

@Composable
fun statusColor(st: InstStatus): Color {
    val p = LocalPal.current
    return when (st) { InstStatus.OK -> p.inc; InstStatus.LATE -> p.warn; InstStatus.OVERDUE -> p.exp; InstStatus.DUE -> p.accent; InstStatus.COVERED -> p.secondary }
}

@Composable
private fun CalendarGrid(month: YearMonth, byDay: Map<LocalDate, List<Inst>>, sel: LocalDate?, onSel: (LocalDate) -> Unit) {
    val p = LocalPal.current
    val first = month.atDay(1)
    val offset = first.dayOfWeek.value - 1
    val cells = offset + month.lengthOfMonth()
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row { listOf("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс").forEach { Text(it, fontSize = 11.sp, color = p.secondary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center) } }
        for (r in 0 until (cells + 6) / 7) {
            Row {
                for (c in 0 until 7) {
                    val i = r * 7 + c - offset + 1
                    if (i < 1 || i > month.lengthOfMonth()) { Spacer(Modifier.weight(1f).height(42.dp)); continue }
                    val d = month.atDay(i)
                    val xs = byDay[d] ?: emptyList()
                    val today = d == LocalDate.now()
                    Column(Modifier.weight(1f).height(42.dp).clip(RoundedCornerShape(10.dp))
                        .background(if (sel == d) p.accent.copy(alpha = 0.18f) else Color.Transparent)
                        .then(if (today) Modifier.border(1.dp, p.accent, RoundedCornerShape(10.dp)) else Modifier)
                        .pressable({ Haptic.select(); onSel(d) }, 0.9f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Text("$i", fontSize = 14.sp, fontWeight = if (xs.isEmpty()) FontWeight.Normal else FontWeight.SemiBold, color = p.text)
                        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) { xs.take(3).forEach { Box(Modifier.size(5.dp).clip(CircleShape).background(statusColor(it.st))) } }
                    }
                }
            }
        }
    }
}

@Composable
private fun InstRow(x: Inst, masked: Boolean, onClick: () -> Unit) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().pressable(onClick, 0.98f).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.width(44.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("${x.due.dayOfMonth}", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
            Text(DF.s(x.due, "MMM").replace(".", ""), fontSize = 11.sp, color = p.secondary)
        }
        Column(Modifier.weight(1f)) {
            Text(x.debt.name, fontWeight = FontWeight.Medium, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (x.n > 1) "Платёж ${x.i + 1} из ${x.n}" else "Разовый платёж", fontSize = 13.sp, color = p.secondary)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(if (masked) "•••" else Fmt.rubU(x.amount), fontWeight = FontWeight.SemiBold, color = p.text)
            Pill(x.st.title, statusColor(x.st))
        }
    }
}

@Composable
private fun DebtLink(d: Debt, masked: Boolean, onClick: () -> Unit) {
    val p = LocalPal.current
    val c = hexColor(d.type.hex)
    Row(Modifier.fillMaxWidth().pressable(onClick, 0.98f).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Tile(if (d.type == DebtType.PERSON) Icons.Rounded.Person else Icons.Rounded.AccountBalance, c, 42.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row { Text(d.name, fontWeight = FontWeight.Medium, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(if (masked) "•••" else Fmt.rubU(d.remaining), fontWeight = FontWeight.SemiBold, color = p.text) }
            ProgressBar(d.progress, c, 6.dp)
            Text(listOfNotNull(d.lender.ifEmpty { null }, d.nextInst?.let { "след. ${DF.short(it.due)}" }, if (d.isClosed) "закрыт" else null).joinToString(" · "), fontSize = 12.sp, color = p.secondary)
        }
    }
}

@Composable
private fun Advice(outOpen: List<Debt>) {
    if (outOpen.size <= 1 && outOpen.none { it.type == DebtType.MICRO }) return
    val p = LocalPal.current
    val micro = outOpen.filter { it.type == DebtType.MICRO }.minByOrNull { it.remaining }
    val rated = outOpen.filter { it.rate > 0 }.maxByOrNull { it.rate }
    val small = outOpen.minByOrNull { it.remaining } ?: return
    val tip = when {
        micro != null -> Triple("!", "Свободные деньги — сначала на «${micro.name}».", "Микрозаймы — самые дорогие деньги: у МФО ставка до 0,8% в день. Закройте его как можно раньше, остальное — по графику.")
        rated != null -> Triple("%", "Метод лавины: досрочно гасите «${rated.name}».", "У него самая высокая ставка — ${Fmt.input(rated.rate)}% годовых. Каждый рубль досрочно экономит больше всего на процентах.")
        else -> Triple("1", "Метод снежного кома: закройте сначала «${small.name}».", "Осталось всего ${Fmt.rubU(small.remaining)}. Закрытый долг освобождает платёж и мотивирует гасить следующий. Укажите ставки — подскажу, где выгоднее.")
    }
    Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle("Что гасить первым")
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(p.accent), contentAlignment = Alignment.Center) {
                Text(tip.first, color = p.onAccent, fontWeight = FontWeight.Black, fontSize = 17.sp)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(tip.second, fontWeight = FontWeight.SemiBold, color = p.text)
                Text(tip.third, fontSize = 13.sp, color = p.secondary)
            }
        }
    }
}

// MARK: Карточка долга

@Composable
private fun DebtDetail(debt: Debt, onClose: () -> Unit, onEdit: () -> Unit, onPay: (Int) -> Unit) {
    val p = LocalPal.current
    var confirm by remember { mutableStateOf(false) }
    var extraText by remember { mutableStateOf("") }
    val sch = debt.schedule()
    val okN = sch.count { it.st == InstStatus.OK }; val lateN = sch.count { it.st == InstStatus.LATE }
    val c = hexColor(debt.type.hex)
    SheetScaffold(debt.name, onClose = onClose, trailing = { GlassCircle(Icons.Rounded.Edit, desc = "Изменить") { onEdit() } }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(if (debt.type == DebtType.PERSON) (if (debt.isOut) "Я должен" else "Мне должны") else debt.type.title, color = Color.White, fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold, modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(c).padding(horizontal = 8.dp, vertical = 2.dp))
                    if (debt.lender.isNotEmpty()) Text(debt.lender, color = p.secondary)
                }
                ProgressBar(debt.progress, c, 12.dp)
                Text(if (debt.isClosed) "Закрыт полностью" else "Выплачено ${Math.round(debt.progress * 100)}%" + (if (okN > 0) " · в срок: $okN" else "") + (if (lateN > 0) " · с опозданием: $lateN" else ""),
                    fontSize = 13.sp, color = p.secondary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatBox("Осталось", Fmt.rubU(debt.remaining), Modifier.weight(1f)); StatBox("Выплачено", Fmt.rubU(debt.paidSum), Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatBox(if (debt.n > 1) "Платёж в месяц" else "Разовый платёж", Fmt.rubU(debt.payment), Modifier.weight(1f))
                    StatBox(if (debt.rate > 0) "Ставка" else "Платежей", if (debt.rate > 0) "${Fmt.input(debt.rate)}%" else if (debt.n > 1) "${okN + lateN} из ${debt.n}" else "1", Modifier.weight(1f))
                }
                if (!debt.isClosed) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    debt.nextInst?.let { nx -> PrimaryButton("Внести платёж", Modifier.weight(1f)) { onPay(nx.i) } }
                    Box(Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(16.dp)).background(p.soft).pressable({ onPay(-1) }, 0.97f), contentAlignment = Alignment.Center) {
                        Text("Досрочно", fontWeight = FontWeight.SemiBold, color = p.accent)
                    }
                }
            }
            if (!debt.isClosed && debt.n > 1 && debt.isOut) Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionTitle("Если платить больше")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Доплачивать", color = p.text)
                    Box(Modifier.padding(horizontal = 8.dp).width(120.dp).clip(RoundedCornerShape(10.dp)).background(p.soft)) {
                        KTextField(extraText, { s -> extraText = s.filter { it.isDigit() || it == ',' || it == '.' } }, "5 000",
                            keyboard = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal))
                    }
                    Text("₽ в месяц", color = p.text)
                }
                val x = parseAmount(extraText); val r = x?.let { extraPaymentEffect(debt, it) }
                if (r == null) Text("Введите сумму — покажу, насколько раньше закроете кредит.", fontSize = 13.sp, color = p.secondary)
                else {
                    val gain = r.left - r.months
                    if (gain <= 0) Text("Почти не меняет срок — попробуйте сумму побольше.", fontSize = 14.sp, color = p.text)
                    else {
                        Text("Закроете за ${r.months} мес. вместо ${r.left} — на $gain мес. раньше, примерно в ${DF.s(LocalDate.now().plusMonths(r.months.toLong()), "LLLL yyyy")}.", fontSize = 14.sp, color = p.text)
                        if (r.saved != null) Text("Экономия на процентах ≈ ${Fmt.rubU(r.saved)}", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = p.inc)
                        else Text("Укажите ставку в долге, чтобы посчитать экономию на процентах.", fontSize = 13.sp, color = p.secondary)
                        Text("Расчёт примерный. При досрочке попросите банк уменьшить срок, а не платёж.", fontSize = 13.sp, color = p.secondary)
                    }
                }
            }
            Column(Modifier.fillMaxWidth().cardBg().padding(16.dp)) {
                SectionTitle("График платежей")
                sch.forEach { x ->
                    if (x.st == InstStatus.COVERED) Row(Modifier.fillMaxWidth().alpha(0.6f).padding(vertical = 8.dp)) {
                        Text("${DF.short(x.due)} · платёж ${x.i + 1}", fontSize = 14.sp, color = p.text, modifier = Modifier.weight(1f)); Text("не нужен", fontSize = 14.sp, color = p.secondary)
                    } else InstRow(x, false) { onPay(x.i) }
                }
            }
            if (debt.extras.isNotEmpty()) Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SectionTitle("Досрочные платежи")
                debt.extras.forEachIndexed { j, e ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(DF.short(e.date), color = p.secondary); Text(Fmt.rubU(e.amount), fontWeight = FontWeight.SemiBold, color = p.text, modifier = Modifier.weight(1f))
                        Text("Убрать", color = p.exp, fontSize = 14.sp, modifier = Modifier.pressable({ Store.saveDebt(debt.copy(extras = debt.extras.filterIndexed { k, _ -> k != j })) }))
                    }
                }
            }
            Text("Удалить долг", color = p.exp, fontWeight = FontWeight.Medium, modifier = Modifier.align(Alignment.CenterHorizontally).pressable({ confirm = true }).padding(10.dp))
        }
    }
    if (confirm) Confirm("Удалить «${debt.name}» вместе с графиком?", "Удалить", { Store.delete("debt", debt.id); onClose(); Router.say("Долг удалён") { Store.restore("debt", debt.id) } }) { confirm = false }
}

// MARK: Форма долга

@Composable
private fun DebtForm(debt: Debt?, onClose: () -> Unit) {
    val p = LocalPal.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var type by remember { mutableStateOf(debt?.type ?: DebtType.CREDIT) }
    var dirIn by remember { mutableStateOf(debt?.dirIn ?: false) }
    var name by remember { mutableStateOf(debt?.name ?: "") }
    var lender by remember { mutableStateOf(debt?.lender ?: "") }
    var monthly by remember { mutableStateOf(debt?.let { it.n > 1 } ?: true) }
    var total by remember { mutableStateOf(debt?.let { Fmt.input(it.total) } ?: "") }
    var payment by remember { mutableStateOf(debt?.takeIf { it.n > 1 }?.let { Fmt.input(it.payment) } ?: "") }
    var count by remember { mutableStateOf(debt?.takeIf { it.n > 1 }?.n?.toString() ?: "") }
    var nTouched by remember { mutableStateOf(debt != null) }
    var first by remember { mutableStateOf(debt?.first ?: LocalDate.now().plusMonths(1)) }
    var rate by remember { mutableStateOf(debt?.takeIf { it.rate > 0 }?.let { Fmt.input(it.rate) } ?: "") }
    var err by remember { mutableStateOf<String?>(null) }
    var scanning by remember { mutableStateOf(false) }
    var scanNote by remember { mutableStateOf<String?>(null) }

    fun autoCount() {
        if (nTouched) return
        val t = parseAmount(total) ?: return; val pp = parseAmount(payment) ?: return
        if (t > 0 && pp > 0) count = "${ceil(t / pp - 1e-9).toInt()}"
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(4)) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scanning = true; err = null
        scope.launch {
            try {
                val bytes = withContext(Dispatchers.IO) { uris.mapNotNull { loadScaled(ctx, it) }.map { jpeg(it) } }
                val d = Brain.parseDebt(bytes)
                type = d.type; if (d.name.isNotEmpty()) name = d.name; if (d.lender.isNotEmpty()) lender = d.lender
                monthly = d.n > 1; total = Fmt.input(Math.round(d.total * 100) / 100.0)
                if (d.n > 1) { payment = Fmt.input(Math.round(d.payment * 100) / 100.0); count = "${d.n}"; nTouched = true }
                first = d.first; if (d.rate > 0) rate = Fmt.input(Math.round(d.rate * 100) / 100.0)
                scanNote = "Заполнено — проверьте поля"
            } catch (e: Exception) { err = e.message } finally { scanning = false }
        }
    }

    fun save() {
        val t = parseAmount(total)?.takeIf { it > 0 } ?: run { err = "Укажите, сколько осталось вернуть."; return }
        var pay = t; var n = 1
        if (monthly) {
            pay = parseAmount(payment)?.takeIf { it > 0 } ?: run { err = "Укажите ежемесячный платёж."; return }
            n = count.toIntOrNull()?.takeIf { it >= 1 } ?: ceil(t / pay).toInt()
            if (n > 600) { err = "Слишком много платежей — проверьте сумму и платёж."; return }
        }
        val r = maxOf(0.0, parseAmount(rate) ?: 0.0)
        val fn = name.trim().ifEmpty { if (type == DebtType.PERSON) lender.ifEmpty { "Долг" } else type.title }
        val d = (debt ?: Debt()).copy(type = type, dirIn = type == DebtType.PERSON && dirIn, name = fn, lender = lender.trim(), total = t, payment = pay, n = n, first = first, rate = r)
        Store.saveDebt(d)
        Haptic.success(); onClose()
        Router.say(if (debt == null) "Долг добавлен, график построен" else "Сохранено")
    }

    SheetScaffold(if (debt == null) "Новый долг" else "Изменить долг", onClose = onClose, bottom = { PrimaryButton("Сохранить", Modifier.padding(16.dp)) { save() } }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (debt == null) Group(footer = "Сделайте скриншот графика платежей в приложении банка — поля заполнятся сами.") {
                Row(Modifier.fillMaxWidth().pressable({
                    if (!Claude.available) err = "Для скана нужен ИИ: войдите в аккаунт." else picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }, 0.98f, enabled = !scanning).padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (scanning) CircularProgressIndicator(Modifier.size(20.dp), color = p.accent, strokeWidth = 2.dp) else Icon(Icons.Rounded.DocumentScanner, null, tint = p.accent)
                    Text(if (scanning) "Claude читает график…" else scanNote ?: "Заполнить по скриншоту графика", color = p.accent, fontWeight = FontWeight.SemiBold)
                }
            }
            Group("Вид") {
                Chips { DebtType.entries.forEach { t -> Chip(t.longName, type == t, hexColor(t.hex)) { type = t; if (t != DebtType.PERSON) dirIn = false; if (debt == null) monthly = !(t == DebtType.MICRO || t == DebtType.PERSON) } } }
                if (type == DebtType.PERSON) Segmented(listOf("Я должен", "Мне должны"), if (dirIn) 1 else 0, { dirIn = it == 1 })
            }
            Group {
                KTextField(name, { name = it }, "Название, например «Кредит на машину»")
                Divider1()
                KTextField(lender, { lender = it }, if (type == DebtType.PERSON) (if (dirIn) "Кто должен" else "Кому") else "${type.lenderLabel} (${type.placeholder})")
            }
            Group(footer = "Сумму и платёж берите из графика банка, вместе с процентами. Ставка нужна для калькулятора досрочки и совета, что гасить первым.") {
                Segmented(listOf("Каждый месяц", "Одним платежом"), if (monthly) 0 else 1, { monthly = it == 0 })
                FieldRow("Осталось вернуть", total, { total = it; autoCount() }, "120 000")
                if (monthly) {
                    Divider1(); FieldRow("Платёж в месяц", payment, { payment = it; autoCount() }, "8 500")
                    Divider1(); FieldRow("Платежей осталось", count, { s -> count = s.filter { it.isDigit() }; nTouched = true }, "15")
                }
                Divider1(); DateRow(if (monthly) "Ближайший платёж" else "Вернуть до", first) { first = it }
                Divider1(); FieldRow("Ставка, % годовых", rate, { rate = it }, "необязательно")
            }
            err?.let { Text(it, color = p.exp, fontSize = 14.sp) }
        }
    }
}

// MARK: Платёж

@Composable
private fun PaySheet(debt: Debt, index: Int, onClose: () -> Unit) {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    val inst = if (index >= 0) debt.schedule().firstOrNull { it.i == index } else null
    val isExtra = index < 0
    var amount by remember { mutableStateOf(inst?.let { x -> x.paid?.let { Fmt.input(it.amount) } ?: Fmt.input(minOf(x.plan, if (debt.remaining > 0) debt.remaining else x.plan)) } ?: "") }
    var date by remember { mutableStateOf(inst?.paid?.date ?: LocalDate.now()) }
    var late by remember { mutableStateOf(inst?.paid?.late ?: (inst?.let { LocalDate.now().isAfter(it.due) } ?: false)) }
    var toBudget by remember { mutableStateOf(true) }
    var err by remember { mutableStateOf<String?>(null) }
    val wasPaid = inst?.paid != null

    fun save() {
        val v = parseAmount(amount)?.takeIf { it > 0 } ?: run { err = "Введите сумму больше нуля."; return }
        val before = debt.remaining
        val nd = if (isExtra) debt.copy(extras = debt.extras + ExtraPay(date, v)) else debt.copy(payments = debt.payments + (index to Paid(date, v, late)))
        Store.saveDebt(nd)
        if (toBudget && !wasPaid) {
            val acc = snap.accounts.firstOrNull { it.id == Settings.str("lastAcc") }?.id ?: snap.accounts.firstOrNull()?.id
            Store.saveTx(Tx(kind = if (debt.isOut) TxKind.EXP else TxKind.INC, amount = v, cat = if (debt.isOut) "loans" else "debtback",
                note = debt.name + if (isExtra) " · досрочно" else "", date = date, acc = acc))
        }
        onClose()
        if (before > 0 && nd.remaining <= 0) Router.celebrate = if (debt.isOut) "«${debt.name}» закрыт!" to "Долг полностью погашен. Так держать." else "«${debt.name}» вам вернули!" to "Долг полностью погашен."
        else { Haptic.success(); Router.say(if (isExtra) "Досрочный платёж внесён" else if (late) "Отмечено: с опозданием" else "Отмечено: оплачено в срок") }
    }

    val title = if (isExtra) "Досрочный платёж" else if (debt.n > 1) "Платёж ${index + 1} из ${debt.n}" else "Платёж"
    SheetScaffold(title, onClose = onClose, bottom = { PrimaryButton(if (wasPaid) "Сохранить" else if (isExtra) "Внести" else "Оплачено", Modifier.padding(16.dp)) { save() } }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(inst?.let { "Срок ${DF.s(it.due, "d MMMM yyyy")}, по графику ${Fmt.rubU(it.plan)}" } ?: "Осталось вернуть ${Fmt.rubU(debt.remaining)}", color = p.secondary,
                modifier = Modifier.padding(horizontal = 4.dp))
            Group { FieldRow("Сумма, ₽", amount, { amount = it }, "0") }
            Group {
                DateRow("Когда заплатил", date) { d -> date = d; inst?.let { late = d.isAfter(it.due) } }
                if (!isExtra) Segmented(listOf("В срок", "С опозданием"), if (late) 1 else 0, { late = it == 1 })
                if (!wasPaid) SwitchRow(if (debt.isOut) "Записать в бюджет как расход" else "Записать в бюджет как доход", toBudget) { toBudget = it }
            }
            err?.let { Text(it, color = p.exp) }
            if (wasPaid) Text("Снять отметку об оплате", color = p.exp, fontWeight = FontWeight.Medium, modifier = Modifier.align(Alignment.CenterHorizontally)
                .pressable({ Store.saveDebt(debt.copy(payments = debt.payments - index)); onClose() }).padding(10.dp))
        }
    }
}


// MARK: Регулярные

@Composable
fun RecurringCard(snap: Snapshot, masked: Boolean, onEdit: (Recurring?) -> Unit) {
    val p = LocalPal.current
    val recs = snap.recs.sortedBy { it.day }
    val now = YearMonth.now(); val today = LocalDate.now()
    Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle("Подписки и регулярные", "+ Платёж") { onEdit(null) }
        if (recs.isEmpty()) Text("Интернет, связь, Яндекс Плюс, аренда, зарплата. Будут напоминать о себе и записываться в одно касание. Можно сказать голосом: «подписка Яндекс 399 каждый месяц 15-го».", fontSize = 14.sp, color = p.secondary)
        else {
            val per = recs.sumOf { it.perMonth }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { StatBox("В месяц", if (masked) "•••" else Fmt.rubU(per), Modifier.weight(1f)); StatBox("В год", if (masked) "•••" else Fmt.rubU(per * 12), Modifier.weight(1f)) }
            recs.forEach { r ->
                val c = Catalog.cat(r.cat)
                Row(Modifier.fillMaxWidth().pressable({ onEdit(r) }, 0.98f).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Tile(c.icon, c.color, 40.dp)
                    Column(Modifier.weight(1f)) {
                        Text(r.name, fontWeight = FontWeight.Medium, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text((if (r.yearly) "Раз в год, ${r.day} ${DF.s(LocalDate.of(2026, r.month, 1), "MMMM")}" else "Каждый месяц, ${r.day}-го") + " · " + c.name,
                            fontSize = 13.sp, color = p.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(if (masked) "•••" else (if (r.kind == TxKind.INC) "+" else "") + Fmt.rubU(r.amount), fontWeight = FontWeight.SemiBold, color = if (r.kind == TxKind.INC) p.inc else p.text)
                        val d = r.due(now)
                        when {
                            d == null -> Pill("не в этом месяце", p.secondary)
                            r.isRecorded(now, snap.txs) -> Pill("Записан", p.inc)
                            !d.isAfter(today) -> Pill("Пора записать", p.exp)
                            else -> Pill(DF.short(d), p.accent)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun RecurringForm(rec: Recurring?, onClose: () -> Unit) {
    val p = LocalPal.current
    val presets = listOf(Triple("Яндекс Плюс", 399.0, "subs"), Triple("Интернет", 700.0, "phone"), Triple("Связь", 500.0, "phone"),
        Triple("Аренда", 25000.0, "home"), Triple("ЖКУ", 5000.0, "home"), Triple("Зарплата", 0.0, "salary"))
    var name by remember { mutableStateOf(rec?.name ?: "") }
    var amount by remember { mutableStateOf(rec?.let { Fmt.input(it.amount) } ?: "") }
    var kind by remember { mutableStateOf(rec?.kind ?: TxKind.EXP) }
    var cat by remember { mutableStateOf(rec?.cat ?: "subs") }
    var day by remember { mutableIntStateOf(rec?.day ?: LocalDate.now().dayOfMonth) }
    var yearly by remember { mutableStateOf(rec?.yearly ?: false) }
    var month by remember { mutableIntStateOf(rec?.month ?: LocalDate.now().monthValue) }
    var confirm by remember { mutableStateOf(false) }
    LaunchedEffect(kind) { cat = Catalog.valid(cat, kind) }
    val v = parseAmount(amount) ?: 0.0
    val ok = v > 0 && name.isNotBlank()

    SheetScaffold(if (rec == null) "Регулярный платёж" else rec.name, onClose = onClose, bottom = {
        PrimaryButton("Сохранить", Modifier.padding(16.dp), enabled = ok) {
            Store.saveRec((rec ?: Recurring()).copy(name = name.trim(), amount = v, kind = kind, cat = Catalog.valid(cat, kind), day = day, yearly = yearly, month = month))
            Haptic.success(); onClose()
        }
    }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (rec == null) Group { Chips { presets.forEach { (n, a, c) -> Chip(n, name == n) { name = n; if (a > 0) amount = Fmt.input(a); cat = c; kind = Catalog.cat(c).kind } } } }
            Group {
                Segmented(listOf("Расход", "Доход"), if (kind == TxKind.INC) 1 else 0, { kind = if (it == 1) TxKind.INC else TxKind.EXP })
                KTextField(name, { name = it }, "Название")
                Divider1()
                FieldRow("Сумма", amount, { amount = it }, "399")
            }
            Group("Категория") { Chips { Catalog.list(kind).forEach { c -> Chip(c.name, cat == c.id, c.color) { cat = c.id } } } }
            Group {
                Segmented(listOf("Каждый месяц", "Раз в год"), if (yearly) 1 else 0, { yearly = it == 1 })
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Число месяца: $day", color = p.text, modifier = Modifier.weight(1f))
                    Stepper({ if (day > 1) day-- }, { if (day < 31) day++ })
                }
                if (yearly) Chips { (1..12).forEach { m -> Chip(DF.s(LocalDate.of(2026, m, 1), "LLLL").cap(), month == m) { month = m } } }
            }
            if (rec != null) Text("Удалить", color = p.exp, fontWeight = FontWeight.Medium, modifier = Modifier.align(Alignment.CenterHorizontally).pressable({ confirm = true }).padding(10.dp))
        }
    }
    if (confirm && rec != null) Confirm("Удалить регулярный платёж?", "Удалить", { Store.delete("rec", rec.id); onClose() }) { confirm = false }
}

@Composable
fun Stepper(onMinus: () -> Unit, onPlus: () -> Unit) {
    val p = LocalPal.current
    Row(Modifier.clip(RoundedCornerShape(10.dp)).background(p.soft)) {
        Icon(Icons.Rounded.Remove, "Меньше", tint = p.text, modifier = Modifier.size(44.dp, 34.dp).pressable({ Haptic.select(); onMinus() }).padding(6.dp))
        Box(Modifier.width(1.dp).height(34.dp).background(p.stroke))
        Icon(Icons.Rounded.Add, "Больше", tint = p.text, modifier = Modifier.size(44.dp, 34.dp).pressable({ Haptic.select(); onPlus() }).padding(6.dp))
    }
}
