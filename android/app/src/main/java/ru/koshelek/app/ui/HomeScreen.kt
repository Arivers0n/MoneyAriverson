package ru.koshelek.app.ui

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*
import java.time.LocalDate
import java.time.YearMonth

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen() {
    val p = LocalPal.current
    val snap by Store.snapshot.collectAsState()
    val syncState by SyncEngine.state.collectAsState()
    var month by remember { mutableStateOf(YearMonth.now()) }
    var reveal by remember { mutableStateOf(false) }
    val masked = Look.hideAmounts && !reveal
    val txs = remember(snap, Router.accFilter) { Router.accFilter?.let { a -> snap.txs.filter { it.acc == a || it.to == a } } ?: snap.txs }
    val monthTxs = remember(txs, month) { txs.filter { month.contains(it.date) } }
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf<String?>(null) }
    val pull = rememberPullToRefreshState()
    val wide = LocalConfiguration.current.screenWidthDp >= 840

    Box(Modifier.fillMaxSize()) {
        Backdrop()
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            TopBar(snap, masked)
            Row(Modifier.fillMaxSize()) {
                Column(Modifier.then(if (wide) Modifier.widthIn(max = 600.dp).weight(1f) else Modifier.fillMaxWidth())) {
                    Hero(month, { month = it }, txs, masked) { if (Look.hideAmounts) { Haptic.tap(); reveal = !reveal } }
                    Box(Modifier.weight(1f)) {
                        PullToRefreshBox(
                            isRefreshing = refreshing,
                            onRefresh = {
                                refreshing = true
                                scope.launch {
                                    val t0 = System.currentTimeMillis()
                                    SyncEngine.sync()
                                    val left = 900 - (System.currentTimeMillis() - t0)
                                    if (left > 0) delay(left)
                                    refreshing = false
                                    if (SyncEngine.state.value == SyncState.ERROR) Haptic.warning() else Haptic.success()
                                    done = if (SyncEngine.state.value == SyncState.ERROR) "Нет связи" else if (Server.loggedIn) "Синхронизировано" else "Всё актуально"
                                    delay(1300); done = null
                                }
                            },
                            state = pull,
                            indicator = {},
                        ) {
                            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 130.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                item {
                                    Box(Modifier.fillMaxWidth().padding(bottom = 10.dp), contentAlignment = Alignment.Center) {
                                        PullPill(pull.distanceFraction, refreshing, done) { Router.show(Route.Insights) }
                                    }
                                }
                                attention(snap)
                                item { CompanionCard(snap) }
                                item { QuickBlock(snap.txs, masked) }
                                feed(monthTxs, snap, masked)
                            }
                        }
                        // плавное растворение ленты под кнопками
                        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(150.dp)
                            .background(Brush.verticalGradient(listOf(Color.Transparent, p.bg.copy(alpha = 0.85f), p.bg))))
                        BottomButtons(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 10.dp))
                    }
                }
                if (wide) {
                    Box(Modifier.width(1.dp).fillMaxHeight().background(p.stroke))
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
                        MonthOverview(snap, month, { month = it }, showPill = false)
                    }
                }
            }
        }
    }
    LaunchedEffect(syncState) {}
}

@Composable
private fun TopBar(snap: Snapshot, masked: Boolean) {
    val accName = Router.accFilter?.let { a -> snap.accounts.firstOrNull { it.id == a }?.name }
        ?: SyncEngine.currentSpace?.takeIf { !it.personal }?.name ?: if (snap.accounts.isEmpty()) "Кошелёк" else "Все счета"
    val amount = when {
        masked -> "••••• ₽"
        Router.accFilter != null -> snap.accounts.firstOrNull { it.id == Router.accFilter }?.let { Fmt.rub(balance(it, snap.txs)) } ?: ""
        snap.accounts.isNotEmpty() -> Fmt.rub(snap.accounts.sumOf { balance(it, snap.txs) })
        else -> Fmt.rub(snap.txs.sumOf { it.signed })
    }
    val alert = allInstallments(snap.debts).any { it.st == InstStatus.OVERDUE && it.debt.isOut } || pendingRecurring(snap.recs, snap.txs).isNotEmpty()
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.weight(1f, fill = false).glass(RoundedCornerShape(50)).pressable({ Router.show(Route.Accounts) }, 0.96f).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(p.inc.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.AccountBalanceWallet, null, tint = p.inc, modifier = Modifier.size(20.dp))
            }
            Column(Modifier.padding(end = 8.dp)) {
                Text(accName, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(amount, fontSize = 13.sp, color = p.secondary, maxLines = 1)
            }
        }
        Spacer(Modifier.weight(0.0001f))
        GlassIconGroup(listOf(
            IconItem(Icons.Rounded.Search) { Router.show(Route.Search) },
            IconItem(Icons.Rounded.PieChart) { Router.show(Route.Stats) },
            IconItem(Icons.Rounded.CalendarMonth, alert) { Router.show(Route.Payments) },
            IconItem(Icons.Rounded.Savings) { Router.show(Route.Goals(1)) },
        ))
        GlassCircle(Icons.Rounded.Settings, desc = "Настройки") { Router.show(Route.Settings) }
    }
}

@Composable
private fun Hero(month: YearMonth, onMonth: (YearMonth) -> Unit, txs: List<Tx>, masked: Boolean, onTap: () -> Unit) {
    val p = LocalPal.current
    val t = remember(txs, month, Look.debtInTotals) { totals(month, txs) }
    val (label, value) = when (Look.bigNumber) { "exp" -> "Потрачено за" to t.exp; "inc" -> "Доход за" to t.inc; else -> "Итог за" to t.net }
    Column(Modifier.fillMaxWidth().padding(top = 22.dp, start = 16.dp, end = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(label, color = p.secondary, fontSize = 16.sp)
            MonthPill(month, onMonth)
            AnimatedVisibility(month != YearMonth.now()) {
                Icon(Icons.Rounded.Replay, "Текущий месяц", tint = p.secondary, modifier = Modifier.size(26.dp).pressable({ Haptic.select(); onMonth(YearMonth.now()) }))
            }
        }
        Box(Modifier.pointerInput(Unit) { detectTapGestures { onTap() } }) {
            RollingAmount(value, TextStyle(fontSize = if (Look.compact) 50.sp else 62.sp, fontWeight = FontWeight.Bold, fontFamily = p.fontFamily, letterSpacing = (-1).sp), p.text, masked, countUp = true)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(22.dp)) {
            if (Look.alwaysIncome || t.inc > 0) FlowChip(Icons.Rounded.SouthWest, p.inc, if (masked) "•••" else Fmt.rubU(t.inc), p.inc)
            FlowChip(Icons.Rounded.NorthEast, p.warn, if (masked) "•••" else Fmt.rubU(t.exp), p.text)
        }
    }
}

@Composable
private fun FlowChip(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, text: String, textColor: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(24.dp).clip(CircleShape).background(color.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = color, modifier = Modifier.size(14.dp))
        }
        Text(text, fontSize = 20.sp, fontWeight = FontWeight.Medium, color = textColor, maxLines = 1)
    }
}

/**
 * Капсула «Инсайты»: при оттягивании растягивается только по ширине, звёздочка крутится, в конце — галочка.
 * Положение и высота не меняются, поэтому капсула не наезжает на соседние блоки и не двигает ленту.
 */
@Composable
private fun PullPill(fraction: Float, refreshing: Boolean, done: String?, onClick: () -> Unit) {
    val p = LocalPal.current
    val armed = fraction >= 1f && !refreshing
    val stretch = (110f * (1 - 1 / (fraction * 0.9f + 1))).coerceAtLeast(0f)
    // вращение запускается только на время обновления — раньше анимация крутилась постоянно и держала экран «в работе»
    val spin: State<Float>? = if (refreshing && Look.animated) {
        rememberInfiniteTransition(label = "spin").animateFloat(0f, 360f, infiniteRepeatable(tween(1100, easing = LinearEasing)), label = "spin")
    } else null
    val bg by animateColorAsState(when { armed -> p.accent; else -> p.accent.copy(alpha = (fraction.coerceIn(0f, 1f) * 0.16f)) }, label = "pillbg")
    val label = when { done != null -> done; refreshing -> "Обновляю…"; armed -> "Отпустите"; else -> "Инсайты" }
    val fg = when { armed -> p.onAccent; done != null -> p.inc; else -> p.text }
    Row(Modifier.glass(RoundedCornerShape(50)).background(bg, RoundedCornerShape(50))
        .pressable(onClick, 0.96f).padding(horizontal = (18 + stretch * 0.35f).dp).height(44.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        AnimatedContent(done != null, label = "ico") { isDone ->
            Icon(if (isDone) Icons.Rounded.Check else Icons.Rounded.AutoAwesome, null, tint = fg,
                modifier = Modifier.size(20.dp).graphicsLayer {
                    val f = fraction.coerceIn(0f, 1f)
                    rotationZ = spin?.value ?: (f * 180f)
                    scaleX = 0.9f + f * 0.2f
                    scaleY = 0.9f + f * 0.2f
                })
        }
        AnimatedContent(label, transitionSpec = { fadeIn(tween(180)) togetherWith fadeOut(tween(120)) }, label = "lbl") { l ->
            Text(l, fontWeight = FontWeight.Medium, fontSize = 16.sp, color = fg)
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.attention(s: Snapshot) {
    val soon = allInstallments(s.debts).filter { it.debt.isOut && (it.st == InstStatus.OVERDUE || (it.st == InstStatus.DUE && daysBetween(LocalDate.now(), it.due) <= 3)) }.minByOrNull { it.due }
    val pend = pendingRecurring(s.recs, s.txs)
    if (soon != null) item {
        val p = LocalPal.current
        AttentionPill(if (soon.st == InstStatus.OVERDUE) p.exp else p.warn, "${soon.debt.name} · ${Fmt.rubU(soon.amount)} · ${relDays(soon.due).first}") { Router.show(Route.Payments) }
    } else if (pend.isNotEmpty()) item {
        val p = LocalPal.current
        AttentionPill(p.accent, if (pend.size == 1) "Записать «${pend[0].name}» · ${Fmt.rubU(pend[0].amount)}" else "Записать регулярные платежи · ${pend.size}") {
            val items = pend.map { r -> ParsedItem(type = r.kind, cat = r.cat, amount = r.amount, date = r.due(YearMonth.now()) ?: LocalDate.now(), note = r.name, recId = r.id) }
            Router.show(Route.Review(items, "Регулярные платежи этого месяца"))
        }
    }
}

@Composable
private fun AttentionPill(color: Color, text: String, onClick: () -> Unit) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().padding(bottom = 10.dp).glass(RoundedCornerShape(50)).pressable(onClick, 0.97f).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(color))
        Text(text, color = p.text, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Icon(Icons.Rounded.ChevronRight, null, tint = p.tertiary)
    }
}

@Composable
private fun QuickBlock(all: List<Tx>, masked: Boolean) {
    val p = LocalPal.current
    val items = remember(all) { frequentTxs(all) }
    Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Bolt, null, tint = p.secondary, modifier = Modifier.size(18.dp))
            Text(" Частое", fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = p.secondary, modifier = Modifier.weight(1f))
            if (items.isNotEmpty()) Text("касание — записать", fontSize = 12.sp, color = p.tertiary)
        }
        if (items.isEmpty()) {
            Text("Здесь появятся траты, которые вы часто повторяете — кофе, проезд, обеды. Записывать их можно будет одним касанием.",
                fontSize = 13.sp, color = p.secondary, modifier = Modifier.fillMaxWidth().cardBg(RoundedCornerShape(20.dp)).padding(14.dp))
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(items, key = { it.key }) { f -> QuickChip(f.sample, masked) }
            }
        }
    }
}

@Composable
private fun QuickChip(t: Tx, masked: Boolean) {
    val p = LocalPal.current
    val c = Catalog.cat(t.cat)
    var pop by remember { mutableStateOf(false) }
    val s by animateFloatAsState(if (pop && Look.moves) 1.06f else 1f, spring(0.45f, 400f), label = "pop")
    LaunchedEffect(pop) { if (pop) { delay(140); pop = false } }
    Row(Modifier.scale(s).cardBg(RoundedCornerShape(50)).pressable({ TxActions.repeatToday(t); pop = true }, 0.95f)
        .padding(start = 6.dp, end = 12.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(30.dp).clip(CircleShape).background(c.color.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
            Icon(if (pop) Icons.Rounded.Check else c.icon, null, tint = c.color, modifier = Modifier.size(16.dp))
        }
        Column(Modifier.widthIn(max = 130.dp)) {
            Text(t.note.cleanedNote().cap().ifEmpty { c.name }, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (masked) "•••" else (if (t.kind == TxKind.INC) "+" else "") + Fmt.rubU(t.amount), fontSize = 12.sp, color = if (t.kind == TxKind.INC) p.inc else p.secondary)
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.feed(monthTxs: List<Tx>, s: Snapshot, masked: Boolean) {
    if (monthTxs.isEmpty()) {
        item {
            val p = LocalPal.current
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Rounded.GraphicEq, null, tint = p.secondary, modifier = Modifier.size(40.dp))
                Text(if (s.txs.isEmpty()) "Скажите, что купили" else "В этом месяце пусто", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text)
                Text("Нажмите на микрофон и говорите как обычно: «кофе 250, такси 400».", fontSize = 15.sp, color = p.secondary,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
        return
    }
    val groups = monthTxs.groupBy { it.date }.toSortedMap(compareByDescending { it })
    for ((day, list) in groups) {
        item(key = "h$day") {
            val p = LocalPal.current
            val net = list.sumOf { it.signed }
            Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 14.dp, bottom = 2.dp)) {
                Text(DF.dayLabel(day), fontSize = 15.sp, color = p.secondary, modifier = Modifier.weight(1f))
                Text(if (masked) "•••" else Fmt.signed(net), fontSize = 15.sp, color = if (net > 0) p.inc.copy(alpha = 0.8f) else p.secondary.copy(alpha = 0.7f))
            }
        }
        items(list.sortedByDescending { it.created }, key = { it.id }) { t -> TxRow(t, s.accounts, masked, Modifier.animateItem()) }
    }
}

@Composable
fun TxRow(t: Tx, accounts: List<Account>, masked: Boolean, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    var menu by remember { mutableStateOf(false) }
    fun accName(id: String?) = accounts.firstOrNull { it.id == id }?.name ?: ""
    Box(modifier) {
        RowCard(Modifier.pressable({ Router.show(Route.EditTx(t)) }, 0.98f, onLongClick = { menu = true })) {
            if (t.kind == TxKind.TR) {
                Tile(Icons.Rounded.SwapHoriz, Color.Gray, if (Look.compact) 40.dp else 50.dp)
                Column(Modifier.weight(1f)) {
                    Text("Перевод", fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.text)
                    Text("${accName(t.acc)} → ${accName(t.to)}", fontSize = 16.sp, color = p.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(if (masked) "•••" else Fmt.rubU(t.amount), fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.secondary, maxLines = 1, softWrap = false)
            } else {
                val c = Catalog.cat(t.cat)
                CategoryTile(c)
                Column(Modifier.weight(1f)) {
                    Text(c.name, fontSize = 19.sp, fontWeight = FontWeight.Medium, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val sub = listOf(t.note.cleanedNote(), if (accounts.size > 1) accName(t.acc) else "", SyncEngine.memberName(t.author) ?: "").filter { it.isNotEmpty() }.joinToString(" · ")
                    if (sub.isNotEmpty()) Text(sub, fontSize = 16.sp, color = p.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(if (masked) "•••" else (if (t.kind == TxKind.INC) "+" else "−") + Fmt.rubU(t.amount), fontSize = 19.sp, fontWeight = FontWeight.Medium,
                    color = if (t.kind == TxKind.INC) p.inc else p.text, maxLines = 1, softWrap = false)
            }
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem({ Text("Изменить") }, { menu = false; Router.show(Route.EditTx(t)) }, leadingIcon = { Icon(Icons.Rounded.Edit, null) })
            DropdownMenuItem({ Text("Повторить сегодня") }, { menu = false; TxActions.repeatToday(t) }, leadingIcon = { Icon(Icons.Rounded.Replay, null) })
            DropdownMenuItem({ Text("Удалить", color = p.exp) }, { menu = false; TxActions.delete(t) }, leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = p.exp) })
        }
    }
}

object TxActions {
    fun repeatToday(t: Tx) {
        val n = t.copy(id = newId(), date = LocalDate.now(), created = nowEpoch(), rec = null)
        Store.saveTx(n)
        Haptic.success()
        val sign = when (t.kind) { TxKind.INC -> "+"; TxKind.EXP -> "−"; else -> "" }
        Router.say("${Catalog.cat(t.cat).name} $sign${Fmt.rubU(t.amount)} — записано") { Store.delete("tx", n.id) }
    }
    fun delete(t: Tx) {
        Haptic.warning()
        Store.delete("tx", t.id)
        Router.say("Операция удалена") { Store.restore("tx", t.id) }
    }
}

@Composable
private fun BottomButtons(modifier: Modifier) {
    val p = LocalPal.current
    var pressed by remember { mutableStateOf(false) }
    val s by animateFloatAsState(if (pressed && Look.animated) 0.93f else 1f, if (pressed) tween(100) else spring(0.6f, 500f), label = "mic")
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(18.dp), verticalAlignment = Alignment.CenterVertically) {
        GlassCircle(Icons.Rounded.DocumentScanner, 60.dp, desc = "Скан чека") { Router.scanRequest++ }
        Box(Modifier.size(78.dp).scale(s).glass().pointerInput(Unit) {
            detectTapGestures(onPress = {
                pressed = true; Haptic.press(); Router.voiceOn = true
                val t0 = System.currentTimeMillis()
                tryAwaitRelease()
                pressed = false
                if (System.currentTimeMillis() - t0 > 450) VoiceBus.release++
            })
        }, contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.Mic, "Сказать голосом", tint = p.text, modifier = Modifier.size(32.dp))
        }
        GlassCircle(Icons.Rounded.Add, 60.dp, desc = "Новая операция") { Router.show(Route.NewTx) }
    }
}

/** Отпускание кнопки микрофона после удержания — сигнал закончить запись. */
object VoiceBus { var release by mutableIntStateOf(0) }
