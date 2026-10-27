package ru.koshelek.app.ui

import androidx.compose.animation.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*
import java.time.YearMonth

// MARK: Категории и тренды

@Composable
fun StatsScreen() {
    val p = LocalPal.current
    val ctx = LocalContext.current
    val snap by Store.snapshot.collectAsState()
    val txs = Router.accFilter?.let { a -> snap.txs.filter { it.acc == a || it.to == a } } ?: snap.txs
    var month by remember { mutableStateOf(YearMonth.now()) }
    var kind by remember { mutableIntStateOf(1) }
    var trends by remember { mutableStateOf(false) }
    var hidden by remember { mutableStateOf(setOf<String>()) }
    var selected by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(kind, month) { hidden = emptySet(); selected = null }
    val masked = Look.hideAmounts
    fun m(v: Double) = if (masked) "•••" else Fmt.rubU(v)

    SheetScaffold(if (trends) "Тренды" else "Категории", trailing = {
        GlassIconGroup(listOf(
            IconItem(if (trends) Icons.Rounded.PieChart else Icons.Rounded.BarChart) { Haptic.select(); trends = !trends },
            IconItem(Icons.Rounded.IosShare) { Csv.share(ctx, txs, snap.accounts) },
        ))
    }) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)) {
            AnimatedContent(trends, transitionSpec = { fadeIn(Motion.entrance(300)) togetherWith fadeOut(androidx.compose.animation.core.tween(150)) }, label = "mode") { tr ->
                Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    if (tr) {
                        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { MonthPill(month) { month = it } }
                        TrendsCard(txs, month, masked)
                        CompareCard(txs, month, masked)
                    } else {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                            PillToggle(listOf(PillOption(0, "Приход", Icons.Rounded.SouthWest, p.inc), PillOption(1, "Расход", Icons.Rounded.NorthEast, p.warn)), kind) { kind = it }
                            MonthPill(month) { month = it }
                        }
                        val k = if (kind == 0) TxKind.INC else TxKind.EXP
                        val rows = remember(txs, month, k) {
                            txs.filter { it.kind == k && month.contains(it.date) }.groupBy { it.cat }
                                .map { (c, l) -> CatSum(Catalog.cat(c), l.sumOf { it.amount }) }.sortedByDescending { it.sum }
                        }
                        val shown = rows.filter { it.cat.id !in hidden }
                        val total = shown.sumOf { it.sum }
                        val focus = selected?.let { id -> shown.firstOrNull { it.cat.id == id } }
                        Box(Modifier.fillMaxWidth().height(300.dp), contentAlignment = Alignment.Center) {
                            Donut(shown, selected, Modifier.size(280.dp))
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(focus?.cat?.name ?: "Итого", color = p.secondary, fontSize = 15.sp)
                                AnimatedContent(m(focus?.sum ?: total), label = "sum") { Text(it, fontSize = 32.sp, fontWeight = FontWeight.Bold, color = p.text) }
                                if (focus != null && total > 0) Text("${Math.round(focus.sum / total * 100)}%", color = focus.cat.color, fontWeight = FontWeight.SemiBold)
                            }
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            RowCard {
                                Text("Все категории", fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.text, modifier = Modifier.weight(1f))
                                Text(m(total), fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.text)
                                CheckDot(hidden.isEmpty()) { hidden = if (hidden.isEmpty()) rows.map { it.cat.id }.toSet() else emptySet() }
                            }
                            if (rows.isEmpty()) Text(if (kind == 0) "Доходов в этом месяце нет" else "Расходов в этом месяце нет", color = p.secondary,
                                modifier = Modifier.fillMaxWidth().padding(vertical = 20.dp), textAlign = TextAlign.Center)
                            rows.forEach { r ->
                                val on = r.cat.id !in hidden
                                Row(Modifier.fillMaxWidth().alpha(if (on) 1f else 0.45f).clip(RoundedCornerShape(22.dp))
                                    .background(if (selected == r.cat.id) r.cat.color.copy(alpha = 0.18f) else p.card)
                                    .pressable({ Haptic.select(); selected = if (selected == r.cat.id) null else r.cat.id }, 0.98f)
                                    .padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Icon(r.cat.icon, null, tint = r.cat.color, modifier = Modifier.size(24.dp))
                                    Text(r.cat.name, fontSize = 18.sp, fontWeight = FontWeight.Medium, color = r.cat.color, modifier = Modifier.weight(1f))
                                    Text(m(r.sum), fontSize = 18.sp, fontWeight = FontWeight.Medium, color = p.text)
                                    CheckDot(on) { Haptic.tap(); hidden = if (on) hidden + r.cat.id else hidden - r.cat.id }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun CheckDot(on: Boolean, onClick: () -> Unit) {
    val p = LocalPal.current
    Icon(if (on) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, tint = if (on) p.text.copy(alpha = 0.85f) else p.secondary,
        modifier = Modifier.size(28.dp).pressable(onClick, 0.85f))
}

@Composable
private fun TrendsCard(txs: List<Tx>, month: YearMonth, masked: Boolean) {
    val p = LocalPal.current
    val ms = remember(txs, month) { (5 downTo 0).map { totals(month.minusMonths(it.toLong()), txs) } }
    val maxV = maxOf(1.0, ms.maxOf { maxOf(it.inc, it.exp) })
    val nz = ms.filter { it.inc > 0 || it.exp > 0 }
    val avg = if (nz.isEmpty()) 0.0 else nz.sumOf { it.exp } / nz.size
    Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle("Полгода")
        Canvas(Modifier.fillMaxWidth().height(180.dp)) {
            val slot = size.width / ms.size; val bw = slot * 0.28f; val h = size.height
            ms.forEachIndexed { i, mt ->
                val x = slot * i + slot / 2
                val hi = (mt.inc / maxV * h).toFloat(); val he = (mt.exp / maxV * h).toFloat()
                drawRoundRect(p.inc, Offset(x - bw - 2, h - hi), Size(bw, hi), CornerRadius(8f))
                drawRoundRect(p.exp, Offset(x + 2, h - he), Size(bw, he), CornerRadius(8f))
            }
        }
        Row { ms.forEach { Text(DF.monthTitle(it.month).take(3), fontSize = 11.sp, color = p.secondary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center) } }
        if (avg > 0 && !masked) Text("В среднем тратите ${Fmt.rubU(avg)} в месяц", fontSize = 13.sp, color = p.secondary)
        Row { listOf("Месяц", "Доход", "Расход", "Итог").forEachIndexed { i, t -> Text(t, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = p.secondary, modifier = Modifier.weight(if (i == 0) 1.1f else 1f), textAlign = if (i == 0) TextAlign.Start else TextAlign.End) } }
        ms.reversed().forEach { mt ->
            Row {
                Text(DF.monthTitle(mt.month), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = p.text, modifier = Modifier.weight(1.1f))
                Text(if (masked) "•••" else Fmt.compact(mt.inc), fontSize = 14.sp, color = p.text, modifier = Modifier.weight(1f), textAlign = TextAlign.End)
                Text(if (masked) "•••" else Fmt.compact(mt.exp), fontSize = 14.sp, color = p.text, modifier = Modifier.weight(1f), textAlign = TextAlign.End)
                Text(if (masked) "•••" else (if (mt.net < 0) "−" else "") + Fmt.compact(mt.net), fontSize = 14.sp, color = if (mt.net >= 0) p.inc else p.exp, modifier = Modifier.weight(1f), textAlign = TextAlign.End)
            }
        }
    }
}

@Composable
private fun CompareCard(txs: List<Tx>, month: YearMonth, masked: Boolean) {
    val p = LocalPal.current
    val cur = totals(month, txs); val prev = totals(month.minusMonths(1), txs)
    val a = byCategory(cur.items).associate { it.cat.id to it.sum }; val b = byCategory(prev.items).associate { it.cat.id to it.sum }
    val diffs = (a.keys + b.keys).map { k -> Triple(k, (a[k] ?: 0.0) - (b[k] ?: 0.0), b[k] ?: 0.0) }.filter { kotlin.math.abs(it.second) >= 1 }
        .sortedByDescending { kotlin.math.abs(it.second) }.take(5)
    Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle("Сравнение с прошлым месяцем")
        if (diffs.isEmpty()) Text("Пока нечего сравнивать — нужны траты за два месяца подряд.", fontSize = 14.sp, color = p.secondary)
        diffs.forEach { (id, d, before) ->
            val c = Catalog.cat(id)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(10.dp).clip(RoundedCornerShape(3.dp)).background(c.color))
                Text(c.name, fontSize = 14.sp, color = p.text, modifier = Modifier.weight(1f))
                val label = if (masked) "•••" else (if (d > 0) "+" else "−") + Fmt.rubU(d) + if (before > 0) " (${if (d > 0) "+" else ""}${Math.round(d / before * 100)}%)" else " новое"
                Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (d > 0) p.exp else p.inc)
            }
        }
        if (diffs.isNotEmpty() && !masked) Text("${DF.monthTitle(month)}: ${Fmt.rubU(cur.exp)} против ${Fmt.rubU(prev.exp)} в прошлом месяце.", fontSize = 13.sp, color = p.secondary)
    }
}

// MARK: Поиск

@Composable
fun SearchScreen() {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    var query by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { delay(400); runCatching { focus.requestFocus() } }
    val q = query.trim().lowercase()
    val num = parseAmount(q)
    val res = remember(q, snap) {
        if (q.isEmpty()) emptyList() else snap.txs.filter { t ->
            t.note.lowercase().contains(q) || Catalog.cat(t.cat).name.lowercase().contains(q) ||
                (snap.accounts.firstOrNull { it.id == t.acc }?.name?.lowercase()?.contains(q) ?: false) ||
                (num != null && Math.round(num) == Math.round(t.amount))
        }
    }
    SheetScaffold("Поиск", Icons.Rounded.Search) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item {
                Row(Modifier.fillMaxWidth().height(54.dp).cardBg(RoundedCornerShape(50)).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Rounded.Search, null, tint = p.secondary)
                    Box(Modifier.weight(1f)) {
                        if (query.isEmpty()) Text("Пятёрочка, такси, 1500…", fontSize = 19.sp, color = p.tertiary)
                        BasicTextField(query, { query = it }, singleLine = true, textStyle = TextStyle(fontSize = 19.sp, color = p.text),
                            cursorBrush = SolidColor(p.accent), modifier = Modifier.fillMaxWidth().focusRequester(focus))
                    }
                    if (query.isNotEmpty()) Icon(Icons.Rounded.Cancel, "Очистить", tint = p.secondary, modifier = Modifier.pressable({ query = "" }))
                }
                Spacer(Modifier.height(10.dp))
            }
            when {
                q.isEmpty() -> item { Text("Ищите по заметке, категории, счёту или сумме", color = p.secondary, modifier = Modifier.fillMaxWidth().padding(top = 30.dp), textAlign = TextAlign.Center) }
                res.isEmpty() -> item { EmptyState(Icons.Rounded.Search, "Ничего не нашлось", "Попробуйте другое слово или точную сумму.") }
                else -> {
                    item {
                        Row(Modifier.padding(horizontal = 10.dp)) {
                            Text(if (res.size > 100) "Найдено ${res.size}, показаны первые 100" else "Найдено ${res.size}", fontSize = 14.sp, color = p.secondary, modifier = Modifier.weight(1f))
                            Text("итого ${Fmt.rub(res.sumOf { it.signed })}", fontSize = 14.sp, color = p.secondary)
                        }
                    }
                    items(res.take(100), key = { it.id }) { t ->
                        Column {
                            Text(DF.dayLabel(t.date), fontSize = 12.sp, color = p.tertiary, modifier = Modifier.padding(start = 10.dp, bottom = 2.dp))
                            TxRow(t, snap.accounts, Look.hideAmounts)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Инсайты

fun insightIcon(sf: String): ImageVector = when (sf) {
    "exclamationmark.triangle.fill" -> Icons.Rounded.Warning
    "speedometer" -> Icons.Rounded.Speed
    "checkmark.circle.fill" -> Icons.Rounded.CheckCircle
    "chart.line.uptrend.xyaxis" -> Icons.AutoMirrored.Rounded.ShowChart
    "flame.fill" -> Icons.Rounded.LocalFireDepartment
    "scalemass.fill" -> Icons.Rounded.Balance
    "repeat" -> Icons.Rounded.Repeat
    else -> Icons2.of(sf)
}

@Composable
fun InsightsScreen() {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    val scope = rememberCoroutineScope()
    var month by remember { mutableStateOf(YearMonth.now()) }
    var tip by remember { mutableStateOf(Settings.str("tipText").takeIf { Settings.str("tipDate") == DF.iso(java.time.LocalDate.now()) && it.isNotEmpty() }) }
    var tipLoading by remember { mutableStateOf(false) }
    var review by remember { mutableStateOf("") }
    var reviewing by remember { mutableStateOf(false) }
    var reviewErr by remember { mutableStateOf<String?>(null) }
    var chat by remember { mutableStateOf(false) }
    val list = remember(snap) { insights(snap) }
    LaunchedEffect(Unit) {
        if (tip == null && Claude.available) { tipLoading = true; tip = runCatching { Brain.dailyTip(snap) }.getOrNull(); tipLoading = false }
    }

    SheetScaffold("Инсайты", Icons.Rounded.AutoAwesome) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            MonthOverview(snap, month, { month = it })
            if (list.isNotEmpty() || Claude.available) Text("Подсказки", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text, modifier = Modifier.padding(top = 8.dp))
            if (Claude.available) {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(p.accent.copy(alpha = 0.12f)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Rounded.AutoAwesome, null, tint = p.accent, modifier = Modifier.size(18.dp))
                        Text("Совет дня", fontWeight = FontWeight.SemiBold, color = p.accent, fontSize = 15.sp)
                    }
                    when {
                        tip != null -> Text(tip!!, color = p.text, fontSize = 16.sp)
                        tipLoading -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            CircularProgressIndicator(Modifier.size(18.dp), color = p.accent, strokeWidth = 2.dp); Text("Смотрю на ваши цифры…", color = p.secondary)
                        }
                    }
                }
            }
            list.forEach { i ->
                val c = when (i.tone) { Tone.GOOD -> p.inc; Tone.WARN -> p.warn; Tone.BAD -> p.exp; Tone.INFO -> p.accent }
                RowCard { Tile(insightIcon(i.symbol), c, 42.dp); Text(i.text, fontSize = 15.sp, color = p.text, modifier = Modifier.weight(1f)) }
            }
            if (list.isEmpty() && !Claude.available) EmptyState(Icons.Rounded.AutoAwesome, "Пока всё спокойно", "Записывайте траты — и здесь появятся подсказки. После входа будет ещё совет дня и разбор месяца.")
            Row(Modifier.fillMaxWidth().height(52.dp).glass(RoundedCornerShape(50)).pressable({ chat = true }, 0.97f), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Forum, null, tint = p.text); Spacer(Modifier.width(8.dp)); Text("Спросить советника", fontWeight = FontWeight.SemiBold, color = p.text)
            }
            Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionTitle("Разбор месяца", if (Claude.available && !reviewing) (if (review.isEmpty()) "Разобрать" else "Ещё раз") else null) {
                    reviewing = true; reviewErr = null
                    scope.launch { runCatching { Brain.review(snap, month) }.onSuccess { review = it.trim() }.onFailure { reviewErr = it.message }; reviewing = false }
                }
                when {
                    reviewing -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(18.dp), color = p.accent, strokeWidth = 2.dp); Text("Claude думает…", color = p.secondary)
                    }
                    review.isNotEmpty() -> SelectionContainer { Text(review, color = p.text, fontSize = 16.sp) }
                    !Claude.available -> Text("Войдите в аккаунт — и Claude разберёт месяц: где перерасход, что выросло, и даст советы с суммами.", fontSize = 14.sp, color = p.secondary)
                    else -> Text("Claude посмотрит на траты, лимит, долги и копилки за этот месяц и даст короткий разбор с советами.", fontSize = 14.sp, color = p.secondary)
                }
                reviewErr?.let { Text(it, fontSize = 13.sp, color = p.exp) }
            }
        }
    }
    AnimatedVisibility(chat, enter = slideInVertically { it / 3 } + fadeIn(), exit = slideOutVertically { it / 4 } + fadeOut()) {
        androidx.activity.compose.BackHandler { chat = false }
        AdvisorChat(onClose = { chat = false })
    }
}

private data class Msg(val user: Boolean, val text: String, val id: Long = System.nanoTime())

@Composable
internal fun AdvisorChat(onClose: () -> Unit, pet: CompanionDef? = null, mood: CompanionMood = CompanionMood.CALM) {
    val p = LocalPal.current
    val scope = rememberCoroutineScope()
    val msgs = remember { mutableStateListOf<Msg>() }
    var input by remember { mutableStateOf("") }
    var thinking by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    val state = rememberLazyListState()
    val suggestions = listOf("Как мне быстрее закрыть долги?", "На чём я трачу лишнее?", "Сколько я могу откладывать в месяц?", "Составь план на следующий месяц")
    LaunchedEffect(msgs.size, thinking) { if (msgs.isNotEmpty()) state.animateScrollToItem(msgs.size + if (thinking) 1 else 0) }

    fun send(text: String) {
        val t = text.trim()
        if (t.isEmpty() || thinking) return
        if (!Claude.available) { err = "ИИ работает после входа в аккаунт"; return }
        input = ""; err = null; msgs += Msg(true, t); thinking = true
        val system = (if (pet != null) AICoach.persona(pet, mood, Brain.persona) else Brain.persona) + "\n\nСвежие данные пользователя (JSON): " + Brain.context(Store.snapshot.value)
        val history = msgs.takeLast(16).map { it.user to it.text }
        scope.launch {
            runCatching { Claude.chat(system, history) }.onSuccess { msgs += Msg(false, it.trim()) }.onFailure { err = it.message }
            thinking = false
        }
    }

    SheetScaffold(pet?.name ?: "Советник", Icons.Rounded.Forum, onClose = onClose, bottom = {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f).clip(RoundedCornerShape(20.dp)).background(p.soft)) {
                KTextField(input, { input = it }, if (pet == null) "Спросить советника…" else "Написать ${pet.name}…", singleLine = false)
            }
            Box(Modifier.size(46.dp).clip(CircleShape).background(if (input.isBlank() || thinking) p.soft else p.accent).pressable({ send(input) }, 0.9f), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.ArrowUpward, "Отправить", tint = if (input.isBlank() || thinking) p.secondary else p.onAccent)
            }
        }
    }) {
        LazyColumn(Modifier.fillMaxSize(), state = state, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (msgs.isEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (pet != null) PetView(pet, mood, Modifier.size(96.dp))
                    else Icon(Icons.Rounded.AutoAwesome, null, tint = p.accent, modifier = Modifier.size(32.dp))
                    Text(pet?.greetLine ?: "Спросите что угодно о своих деньгах", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
                    Text("Советник видит ваши траты, долги, подписки и копилки — и отвечает с цифрами.", fontSize = 14.sp, color = p.secondary)
                    suggestions.forEach { s ->
                        Text(s, fontSize = 15.sp, color = p.text, modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(p.soft).pressable({ send(s) }, 0.98f).padding(12.dp))
                    }
                }
            }
            items(msgs, key = { it.id }) { m ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.user) Arrangement.End else Arrangement.Start) {
                    SelectionContainer {
                        Text(m.text, color = if (m.user) p.onAccent else p.text, fontSize = 16.sp,
                            modifier = Modifier.widthIn(max = 520.dp).padding(start = if (m.user) 40.dp else 0.dp, end = if (m.user) 0.dp else 24.dp)
                                .clip(RoundedCornerShape(18.dp)).background(if (m.user) p.accent else p.soft).padding(12.dp))
                    }
                }
            }
            if (thinking) item {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = p.accent, strokeWidth = 2.dp); Text("Думаю…", color = p.secondary)
                }
            }
            err?.let { e -> item { Text(e, color = p.exp, fontSize = 13.sp) } }
        }
    }
}
