package ru.koshelek.app.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material.icons.automirrored.rounded.TrendingUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.abs

data class StatFact(val id: String, val icon: ImageVector, val color: Color, val title: String, val value: String, val detail: String = "")

/** Обзор месяца: большая цифра, полоса сбережений, накопительный график и факты — как на iPhone. */
@Composable
fun MonthOverview(snap: Snapshot, month: YearMonth, onMonth: (YearMonth) -> Unit, showPill: Boolean = true) {
    val p = LocalPal.current
    val txs = Router.accFilter?.let { a -> snap.txs.filter { it.acc == a || it.to == a } } ?: snap.txs
    val cur = remember(txs, month, Look.debtInTotals) { totals(month, txs) }
    val prev = remember(txs, month, Look.debtInTotals) { totals(month.minusMonths(1), txs) }
    val isCurrent = month == YearMonth.now()
    val daysPassed = if (isCurrent) LocalDate.now().dayOfMonth else month.lengthOfMonth()
    val masked = Look.hideAmounts
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val grow by animateFloatAsState(if (shown) 1f else 0f, Motion.entrance(800), label = "grow")

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (showPill) MonthPill(month, onMonth)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (cur.net >= 0) "Осталось за месяц" else "Ушли в минус", color = p.secondary, fontSize = 15.sp)
            RollingAmount(cur.net, TextStyle(fontSize = 46.sp, fontWeight = FontWeight.Bold, fontFamily = p.fontFamily), if (cur.net >= 0) p.text else p.exp, masked)
        }
        if (cur.inc > 0) {
            val rate = (cur.net / cur.inc).coerceIn(-1.0, 1.0)
            Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row {
                    Text(if (rate >= 0) "Сохранено ${Math.round(rate * 100)}% дохода" else "Потрачено больше дохода на ${Math.round(-rate * 100)}%",
                        fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = p.text, modifier = Modifier.weight(1f))
                    Text(if (masked) "•••" else Fmt.rubU(cur.inc), fontSize = 13.sp, color = p.secondary)
                }
                Box(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(50)).background(p.soft)) {
                    Box(Modifier.fillMaxWidth((abs(rate) * grow).toFloat().coerceAtLeast(0.03f)).fillMaxHeight().clip(RoundedCornerShape(50))
                        .background(Brush.horizontalGradient(if (rate >= 0) listOf(p.inc.copy(alpha = 0.7f), p.inc) else listOf(p.warn, p.exp))))
                }
            }
        }
        CumChart(cur, prev, daysPassed, grow, masked)
        val facts = remember(cur, prev, masked) { facts(cur, prev, daysPassed, isCurrent, masked, p) }
        facts.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { FactTile(it, Modifier.weight(1f)) }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun CumChart(cur: MonthTotals, prev: MonthTotals, daysPassed: Int, grow: Float, masked: Boolean) {
    val p = LocalPal.current
    fun cum(m: MonthTotals, upTo: Int): List<Double> {
        val per = DoubleArray(32)
        m.items.filter { it.kind == TxKind.EXP }.forEach { per[minOf(31, it.date.dayOfMonth)] += it.amount }
        var s = 0.0
        return (1..upTo).map { d -> s += per[d]; s }
    }
    val a = cum(cur, maxOf(1, daysPassed)); val b = cum(prev, prev.month.lengthOfMonth())
    val prevSame = b.getOrNull(daysPassed - 1) ?: b.lastOrNull() ?: 0.0
    val diff = (a.lastOrNull() ?: 0.0) - prevSame
    val maxY = maxOf(1.0, (a + b).maxOrNull() ?: 1.0)
    Column(Modifier.fillMaxWidth().cardBg().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Траты по дням", fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = p.text)
        if (prevSame > 0 && !masked) Text(if (diff <= 0) "На ${Fmt.rubU(diff)} меньше, чем к этому дню в прошлом месяце" else "На ${Fmt.rubU(diff)} больше, чем к этому дню в прошлом месяце",
            fontSize = 13.sp, color = if (diff <= 0) p.inc else p.warn)
        Row {
            Canvas(Modifier.weight(1f).height(160.dp)) {
                val w = size.width; val h = size.height
                fun x(d: Int) = (d - 1) / 30f * w
                fun y(v: Double) = h - (v / maxY * h * grow).toFloat()
                for (k in 0..3) drawLine(p.text.copy(alpha = 0.06f), Offset(0f, h * k / 3f), Offset(w, h * k / 3f), 1f)
                fun path(vals: List<Double>): Path = Path().apply { vals.forEachIndexed { i, v -> if (i == 0) moveTo(x(1), y(v)) else lineTo(x(i + 1), y(v)) } }
                if (b.isNotEmpty()) drawPath(path(b), p.secondary.copy(alpha = 0.5f), style = Stroke(4f, cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f))))
                if (a.isNotEmpty()) {
                    val line = path(a)
                    val area = Path().apply { addPath(line); lineTo(x(a.size), h); lineTo(x(1), h); close() }
                    drawPath(area, Brush.verticalGradient(listOf(p.accent.copy(alpha = 0.35f), p.accent.copy(alpha = 0.02f))))
                    drawPath(line, p.accent, style = Stroke(7f, cap = StrokeCap.Round, join = StrokeJoin.Round))
                    drawCircle(p.accent, 9f, Offset(x(a.size), y(a.last())))
                }
            }
            Column(Modifier.height(160.dp).padding(start = 6.dp), verticalArrangement = Arrangement.SpaceBetween) {
                listOf(maxY, maxY * 2 / 3, maxY / 3, 0.0).forEach { Text(if (masked) "" else Fmt.compact(it), fontSize = 10.sp, color = p.tertiary) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Legend(p.accent, "Этот месяц"); Legend(p.secondary.copy(alpha = 0.5f), "Прошлый")
        }
    }
}

@Composable
private fun Legend(c: Color, t: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(14.dp, 3.dp).clip(RoundedCornerShape(50)).background(c))
        Text(t, fontSize = 12.sp, color = LocalPal.current.secondary)
    }
}

private fun facts(c: MonthTotals, prev: MonthTotals, daysPassed: Int, isCurrent: Boolean, masked: Boolean, p: Pal): List<StatFact> {
    val out = mutableListOf<StatFact>()
    val exps = c.items.filter { it.kind == TxKind.EXP }; val incs = c.items.filter { it.kind == TxKind.INC }
    val days = maxOf(1, daysPassed)
    fun m(s: String) = if (masked) "•••" else s
    out += StatFact("avg", Icons.Rounded.CalendarMonth, p.accent, "Средние траты в день", m(Fmt.rubU(c.exp / days)),
        if (prev.exp > 0 && !masked) "в прошлом: ${Fmt.rubU(prev.exp / prev.month.lengthOfMonth())}" else "")
    exps.maxByOrNull { it.amount }?.let { b -> out += StatFact("bigE", Icons.Rounded.LocalFireDepartment, p.warn, "Самая большая трата", m(Fmt.rubU(b.amount)), b.note.ifEmpty { Catalog.cat(b.cat).name }) }
    incs.maxByOrNull { it.amount }?.let { b -> out += StatFact("bigI", Icons.Rounded.ArrowCircleDown, p.inc, "Самый большой доход", m(Fmt.rubU(b.amount)), b.note.ifEmpty { Catalog.cat(b.cat).name }) }
    val byDay = exps.groupBy { it.date.dayOfMonth }.mapValues { e -> e.value.sumOf { it.amount } }
    byDay.maxByOrNull { it.value }?.let { d -> out += StatFact("day", Icons.Rounded.EventBusy, p.exp, "Самый дорогой день", m(Fmt.rubU(d.value)), DF.s(c.month.atDay(d.key), "d MMMM, EEEE")) }
    if (exps.isNotEmpty()) {
        val zero = (1..days).count { it !in byDay }
        out += StatFact("zero", Icons.Rounded.Eco, p.inc, "Дней без трат", "$zero из $days", if (zero == 0) "попробуйте день-ноль" else "так держать")
    }
    byCategory(c.items).firstOrNull()?.takeIf { c.exp > 0 }?.let { t ->
        out += StatFact("top", t.cat.icon, t.cat.color, "Больше всего на", t.cat.name, if (masked) "${Math.round(t.sum / c.exp * 100)}%" else "${Fmt.rubU(t.sum)} · ${Math.round(t.sum / c.exp * 100)}%")
    }
    if (isCurrent && c.exp > 0) out += StatFact("fc", Icons.AutoMirrored.Rounded.TrendingUp, hexColor("AF52DE"), "Прогноз трат", m(Fmt.rubU(c.exp / days * c.month.lengthOfMonth())), "если темп сохранится")
    out += StatFact("cnt", Icons.Rounded.Tag, hexColor("30B0C7"), "Операций", "${c.items.size}", if (exps.isEmpty() || masked) "" else "средний чек ${Fmt.rubU(c.exp / exps.size)}")
    return out
}


@Composable
fun FactTile(f: StatFact, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    Column(modifier.heightIn(min = 128.dp).cardBg().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(32.dp).clip(RoundedCornerShape(10.dp)).background(f.color.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
            Icon(f.icon, null, tint = f.color, modifier = Modifier.size(18.dp))
        }
        Text(f.title, fontSize = 13.sp, color = p.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(f.value, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (f.detail.isNotEmpty()) Text(f.detail, fontSize = 12.sp, color = p.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Кольцо категорий. */
@Composable
fun Donut(rows: List<CatSum>, selected: String?, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val grow by animateFloatAsState(if (shown) 1f else 0f, Motion.entrance(700), label = "donut")
    val total = rows.sumOf { it.sum }
    Canvas(modifier) {
        val stroke = size.minDimension * 0.17f
        val d = size.minDimension - stroke
        val tl = Offset((size.width - d) / 2, (size.height - d) / 2)
        if (total <= 0) { drawArc(p.soft, 0f, 360f, false, tl, Size(d, d), style = Stroke(stroke)); return@Canvas }
        var start = -90f
        val gap = if (rows.size > 1) 2.5f else 0f
        rows.forEach { r ->
            val sweep = (r.sum / total * 360f * grow).toFloat()
            val a = if (selected == null || selected == r.cat.id) 1f else 0.3f
            if (sweep - gap > 0.3f) drawArc(r.cat.color.copy(alpha = a), start + gap / 2, sweep - gap, false, tl, Size(d, d), style = Stroke(stroke, cap = StrokeCap.Butt))
            start += sweep
        }
    }
}
