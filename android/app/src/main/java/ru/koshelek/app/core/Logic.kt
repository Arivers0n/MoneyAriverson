package ru.koshelek.app.core

import ru.koshelek.app.data.*
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToLong

// MARK: Месяц

data class MonthTotals(val month: YearMonth, val inc: Double, val exp: Double, val items: List<Tx>) {
    val net get() = inc - exp
}

object Calc {
    var debtInTotals = true
    fun counts(t: Tx) = debtInTotals || (t.cat != "loans" && t.cat != "debtback")
}

fun totals(month: YearMonth, txs: List<Tx>): MonthTotals {
    val items = txs.filter { month.contains(it.date) && Calc.counts(it) }
    return MonthTotals(month, items.filter { it.kind == TxKind.INC }.sumOf { it.amount },
        items.filter { it.kind == TxKind.EXP }.sumOf { it.amount }, items)
}

data class CatSum(val cat: Category, val sum: Double)

fun byCategory(items: List<Tx>, kind: TxKind = TxKind.EXP): List<CatSum> =
    items.filter { it.kind == kind && Calc.counts(it) }.groupBy { it.cat }
        .map { (k, v) -> CatSum(Catalog.cat(k), v.sumOf { it.amount }) }.sortedByDescending { it.sum }

fun averageIncome(txs: List<Tx>): Double {
    val now = YearMonth.now()
    val vals = (0..2).map { k -> val m = now.minusMonths(k.toLong()); txs.filter { it.kind == TxKind.INC && it.cat != "debtback" && m.contains(it.date) }.sumOf { it.amount } }.filter { it > 0 }
    return if (vals.isEmpty()) 0.0 else vals.average()
}

// MARK: Долги

enum class InstStatus(val title: String) { OK("В срок"), LATE("С опозданием"), OVERDUE("Просрочен"), DUE("Предстоит"), COVERED("Не нужен") }

data class Inst(val debt: Debt, val i: Int, val n: Int, val due: LocalDate, val amount: Double, val plan: Double, val st: InstStatus, val paid: Paid?) {
    val isOpen get() = st == InstStatus.DUE || st == InstStatus.OVERDUE
    val id get() = "${debt.id}-$i"
}

val Debt.paidSum get() = payments.values.sumOf { it.amount } + extras.sumOf { it.amount }
val Debt.remaining get() = max(0.0, ((total - paidSum) * 100).roundToLong() / 100.0)
val Debt.isClosed get() = remaining <= 0
val Debt.progress get() = if (total > 0) min(1.0, paidSum / total) else 0.0

fun Debt.schedule(): List<Inst> {
    val count = max(1, n)
    val pay = if (payment > 0) payment else total
    val rem = remaining
    val today = LocalDate.now()
    return (0 until count).map { i ->
        var amt = pay
        if (i == count - 1 && count > 1) {
            val last = ((total - pay * (count - 1)) * 100).roundToLong() / 100.0
            if (last > 0 && last <= pay * 2) amt = last
        }
        val due = first.plusMonths(i.toLong())
        val p = payments[i]
        val st = when {
            p != null -> if (p.late) InstStatus.LATE else InstStatus.OK
            rem <= 0 -> InstStatus.COVERED
            due.isBefore(today) -> InstStatus.OVERDUE
            else -> InstStatus.DUE
        }
        Inst(this, i, count, due, p?.amount ?: amt, amt, st, p)
    }
}

val Debt.nextInst get() = schedule().firstOrNull { it.isOpen }

fun allInstallments(debts: List<Debt>) = debts.flatMap { it.schedule() }.filter { it.st != InstStatus.COVERED }

/** Записать платёж по долгу: отмечает ближайший платёж (или досрочный) и создаёт операцию. */
fun payDebt(d: Debt, amount: Double, date: LocalDate, acc: String?): Debt {
    val ni = d.nextInst
    val nd = if (ni != null) d.copy(payments = d.payments + (ni.i to Paid(date, amount, date.isAfter(ni.due))))
             else d.copy(extras = d.extras + ExtraPay(date, amount))
    Store.saveDebt(nd)
    Store.saveTx(Tx(kind = if (d.isOut) TxKind.EXP else TxKind.INC, amount = amount, cat = if (d.isOut) "loans" else "debtback",
        note = d.name, date = date, acc = acc))
    return nd
}

data class ExtraEffect(val months: Int, val left: Int, val saved: Double?)

fun extraPaymentEffect(d: Debt, x: Double): ExtraEffect? {
    val p = d.payment
    val left = d.schedule().count { it.isOpen }
    if (x <= 0 || p <= 0 || left <= 0) return null
    val r = d.rate / 1200
    if (r > 0) {
        var bal = p * (1 - (1 + r).pow(-left.toDouble())) / r
        var paid = 0.0; var m = 0
        while (bal > 0.5 && m < 1200) { val i = bal * r; val pay = min(p + x, bal + i); bal = bal + i - pay; paid += pay; m++ }
        return ExtraEffect(m, left, max(0.0, p * left - paid))
    }
    return ExtraEffect(ceil(d.remaining / (p + x)).toInt(), left, null)
}

// MARK: Счета

fun balance(acc: Account, txs: List<Tx>): Double {
    var b = acc.start
    for (t in txs) {
        if (t.acc == acc.id) b += if (t.kind == TxKind.INC) t.amount else -t.amount
        if (t.kind == TxKind.TR && t.to == acc.id) b += t.amount
    }
    return b
}

// MARK: Регулярные

fun Recurring.due(month: YearMonth): LocalDate? {
    if (yearly && this.month != month.monthValue) return null
    return month.atDay(min(max(1, day), month.lengthOfMonth()))
}
fun Recurring.isRecorded(month: YearMonth, txs: List<Tx>) = txs.any { it.rec == id && month.contains(it.date) }
val Recurring.perMonth get() = if (kind == TxKind.INC) 0.0 else if (yearly) amount / 12 else amount

fun pendingRecurring(recs: List<Recurring>, txs: List<Tx>): List<Recurring> {
    val now = YearMonth.now(); val today = LocalDate.now()
    return recs.filter { r -> val d = r.due(now); d != null && !d.isAfter(today) && !r.isRecorded(now, txs) }
}

// MARK: Частое

data class Frequent(val key: String, val sample: Tx, val count: Int)

fun frequentTxs(txs: List<Tx>, limit: Int = 8): List<Frequent> {
    val from = LocalDate.now().minusDays(90)
    val groups = LinkedHashMap<String, Pair<Tx, Int>>()
    for (t in txs) {
        if (t.date.isBefore(from) || t.kind == TxKind.TR || t.cat == "loans" || t.cat == "debtback" || t.rec != null) continue
        val k = "${t.kind.raw}|${t.cat}|${t.amount.toLong()}|${t.note.lowercase().trim()}"
        val g = groups[k]
        groups[k] = if (g == null) t to 1 else (if (g.first.date.isAfter(t.date)) g.first else t) to g.second + 1
    }
    return groups.filter { it.value.second >= 2 }.map { Frequent(it.key, it.value.first, it.value.second) }
        .sortedWith(compareByDescending<Frequent> { it.count }.thenByDescending { it.sample.date }).take(limit)
}

// MARK: Подсказки без интернета

enum class Tone { GOOD, WARN, BAD, INFO }
data class Insight(val tone: Tone, val symbol: String, val text: String)

fun insights(s: Snapshot): List<Insight> {
    val out = mutableListOf<Insight>()
    val now = LocalDate.now(); val ym = YearMonth.now()
    val cur = totals(ym, s.txs); val prev = totals(ym.minusMonths(1), s.txs)
    allInstallments(s.debts).firstOrNull { it.st == InstStatus.OVERDUE && it.debt.isOut }?.let {
        out += Insight(Tone.BAD, "exclamationmark.triangle.fill", "Просрочен платёж «${it.debt.name}» на ${Fmt.rubU(it.amount)}. Каждый день просрочки — пени и минус к кредитной истории.")
    }
    val budget = s.prefs.budget
    if (budget > 0) {
        val day = now.dayOfMonth.toDouble(); val days = ym.lengthOfMonth().toDouble()
        val forecast = cur.exp / max(1.0, day) * days
        if (forecast > budget * 1.08 && cur.exp > 0)
            out += Insight(Tone.WARN, "speedometer", "Тратите быстрее плана: к концу месяца выйдет около ${Fmt.rubU(forecast)} при лимите ${Fmt.rubU(budget)}. Чтобы уложиться, держитесь в пределах ${Fmt.rubU(max(0.0, budget - cur.exp) / max(1.0, days - day + 1))} в день.")
        else if (cur.exp > 0 && day > 10) out += Insight(Tone.GOOD, "checkmark.circle.fill", "Идёте в рамках лимита. Так держать.")
    }
    val spent = cur.items.filter { it.kind == TxKind.EXP }.groupBy { it.cat }.mapValues { e -> e.value.sumOf { it.amount } }
    for ((id, lim) in s.prefs.catLimits.entries.sortedByDescending { (spent[it.key] ?: 0.0) / max(it.value, 1.0) }) {
        if (lim <= 0) continue
        val sp = spent[id] ?: 0.0; val c = Catalog.cat(id)
        if (sp > lim) { out += Insight(Tone.BAD, c.symbol, "Бюджет «${c.name}» превышен на ${Fmt.rubU(sp - lim)}. Лучше притормозить с этой категорией до конца месяца."); break }
        else if (sp > lim * 0.8) { out += Insight(Tone.WARN, c.symbol, "По «${c.name}» потрачено ${(sp / lim * 100).toInt()}% бюджета, осталось ${Fmt.rubU(lim - sp)}."); break }
    }
    val frac = now.dayOfMonth.toDouble() / ym.lengthOfMonth()
    val a = byCategory(cur.items).associate { it.cat.id to it.sum }; val b = byCategory(prev.items).associate { it.cat.id to it.sum }
    a.filter { it.key in setOf("cafe", "fun", "clothes", "other", "gifts") }
        .map { Triple(it.key, it.value, (b[it.key] ?: 0.0) * frac) }
        .filter { it.second > 2000 && it.second > it.third * 1.4 }
        .maxByOrNull { it.second - it.third }?.let {
            out += Insight(Tone.WARN, "chart.line.uptrend.xyaxis", "«${Catalog.cat(it.first).name}» уже ${Fmt.rubU(it.second)} — заметно больше, чем к этому дню в прошлом месяце. Это то, что легче всего урезать.")
        }
    val cafe = cur.items.filter { it.kind == TxKind.EXP && it.cat == "cafe" }
    if (cafe.size >= 8) {
        val sum = cafe.sumOf { it.amount }
        out += Insight(Tone.INFO, "cup.and.saucer.fill", "${cafe.size} ${plural(cafe.size, "раз", "раза", "раз")} кафе и кофе за месяц — ${Fmt.rubU(sum)}. Мелочи складываются: это ${Fmt.rubU(sum * 12)} в год.")
    }
    s.debts.firstOrNull { it.type == DebtType.MICRO && it.isOut && !it.isClosed }?.let {
        out += Insight(Tone.BAD, "flame.fill", "Микрозайм «${it.name}» — самые дорогие деньги. Любые свободные рубли сначала туда: осталось ${Fmt.rubU(it.remaining)}.")
    }
    val inc = averageIncome(s.txs)
    val monthly = allInstallments(s.debts).filter { it.debt.isOut && ym.contains(it.due) }.sumOf { it.plan }
    if (inc > 0 && monthly / inc > 0.4)
        out += Insight(Tone.BAD, "scalemass.fill", "На кредиты уходит ${(monthly / inc * 100).toInt()}% дохода. Больше 40% — опасная зона: новые займы сейчас лучше не брать.")
    val subs = s.recs.filter { it.kind == TxKind.EXP }.sumOf { it.perMonth }
    if (subs > 0 && s.recs.size >= 3)
        out += Insight(Tone.INFO, "repeat", "Регулярные платежи — ${Fmt.rubU(subs)} в месяц, ${Fmt.rubU(subs * 12)} в год. Проверьте, всеми ли подписками пользуетесь.")
    return out
}

fun daysBetween(a: LocalDate, b: LocalDate) = ChronoUnit.DAYS.between(a, b).toInt()

// MARK: Помощники для экрана платежей

val DebtType.hex get() = when (this) { DebtType.CREDIT -> "2B47C9"; DebtType.CARD -> "7B5CC4"; DebtType.MICRO -> "C2621F"; DebtType.PERSON -> "1A8F86" }
val DebtType.longName get() = if (this == DebtType.PERSON) "Долг человеку" else title
val DebtType.lenderLabel get() = when (this) { DebtType.CREDIT, DebtType.CARD -> "Банк"; DebtType.MICRO -> "МФО"; DebtType.PERSON -> "Кто" }
val DebtType.placeholder get() = when (this) { DebtType.CREDIT -> "Сбер"; DebtType.CARD -> "Т-Банк"; DebtType.MICRO -> "Займер"; DebtType.PERSON -> "Имя" }

val Debt.lastOpenDue: LocalDate? get() = schedule().lastOrNull { it.isOpen }?.due

fun onTimeStreak(debts: List<Debt>): Int {
    val done = debts.filter { it.isOut }.flatMap { it.schedule() }
        .filter { it.st == InstStatus.OK || it.st == InstStatus.LATE || it.st == InstStatus.OVERDUE }.sortedByDescending { it.due }
    var s = 0
    for (x in done) { if (x.st == InstStatus.OK) s++ else break }
    return s
}

fun spanText(to: LocalDate): String {
    val now = LocalDate.now()
    val m = ChronoUnit.MONTHS.between(now, to).toInt()
    if (m < 1) { val n = daysBetween(now, to); return if (n <= 0) "уже скоро" else "через $n ${plural(n, "день", "дня", "дней")}" }
    val y = m / 12; val mm = m % 12
    val parts = mutableListOf<String>()
    if (y > 0) parts += "$y ${plural(y, "год", "года", "лет")}"
    if (mm > 0) parts += "$mm мес."
    return "через " + parts.joinToString(" ")
}
