package ru.koshelek.app.core

import ru.koshelek.app.data.Settings
import ru.koshelek.app.data.Snapshot
import ru.koshelek.app.data.TxKind
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.YearMonth
import java.time.temporal.ChronoUnit

// Данные виджета и тексты блоков. Правила и подписи — те же, что в Koshelek/Widgets/Shared/WidgetSnapshot.swift.
// На Android снимок собирается в момент рисования из актуальных данных, поэтому «устаревания» нет.

enum class WidgetDot { none, future, missed, partial, done, today }

data class WidgetStat(val name: String, val value: Double)
data class WidgetGoal(val name: String, val fraction: Double)
data class WidgetPayment(val name: String, val amount: Double, val due: LocalDate)

data class WidgetSnapshot(
    val budget: Double,
    val monthExpense: Double,
    val monthIncome: Double,
    val todaySpend: Double,
    val balance: Double?,
    val saved: Double,
    val goal: WidgetGoal?,
    val nextPayment: WidgetPayment?,
    val topCats: List<WidgetStat>,
    val level: Int,
    val levelFraction: Double,
    val mood: String,
    val userName: String,
    val petId: String,
    val petName: String,
    val phrase: String,
    val week: List<WidgetDot>,
    val hideAmounts: Boolean,
    /** 2 — понедельник, 1 — воскресенье. */
    val firstWeekday: Int = 2,
) {
    companion object {
        /** Пример для предпросмотра и галереи виджетов. */
        fun sample(now: LocalDate = LocalDate.now()) = WidgetSnapshot(
            budget = 60000.0, monthExpense = 37200.0, monthIncome = 85000.0, todaySpend = 640.0,
            balance = 45300.0, saved = 28500.0, goal = WidgetGoal("Отпуск", 0.24),
            nextPayment = WidgetPayment("Кредит на машину", 12000.0, now.plusDays(4)),
            topCats = listOf(WidgetStat("Продукты", 12840.0), WidgetStat("Кафе и рестораны", 4560.0), WidgetStat("Транспорт", 3210.0)),
            level = 4, levelFraction = 0.38, mood = "happy", userName = "", petId = CompanionCatalog.DEFAULT_ID, petName = "Искорка",
            phrase = "Ура! Ты отлично держишься в лимите — так и продолжай!",
            week = listOf(WidgetDot.done, WidgetDot.done, WidgetDot.partial, WidgetDot.missed, WidgetDot.today, WidgetDot.future, WidgetDot.future),
            hideAmounts = false,
        )

        private const val FALLBACK_DAILY_LIMIT = 1500.0

        /** Собирает снимок из данных приложения теми же правилами, что и на iPhone. */
        fun build(s: Snapshot, now: LocalDateTime = LocalDateTime.now()): WidgetSnapshot {
            val today = now.toLocalDate()
            val ym = YearMonth.from(today)
            val budget = maxOf(0.0, s.prefs.budget)
            val real = s.txs.filter { it.kind != TxKind.TR && Calc.counts(it) }

            var exp = 0.0; var inc = 0.0; var todaySum = 0.0
            val byCat = HashMap<String, Double>()
            val spendByDay = HashMap<LocalDate, Double>()
            for (t in real) {
                if (t.kind == TxKind.EXP) {
                    spendByDay[t.date] = (spendByDay[t.date] ?: 0.0) + t.amount
                    if (ym.contains(t.date)) { exp += t.amount; byCat[t.cat] = (byCat[t.cat] ?: 0.0) + t.amount }
                    if (t.date == today) todaySum += t.amount
                } else if (t.kind == TxKind.INC && ym.contains(t.date)) inc += t.amount
            }
            val top = byCat.entries.sortedWith(compareByDescending<Map.Entry<String, Double>> { it.value }.thenBy { it.key })
                .take(3).map { WidgetStat(Catalog.cat(it.key).name, it.value) }

            val weekStart = today.minusDays(((today.dayOfWeek.value - 1)).toLong())
            val week = (0 until 7).map { i ->
                val day = weekStart.plusDays(i.toLong())
                dot(day, today, spendByDay[day] ?: 0.0, budget)
            }

            val pet = CompanionCatalog.def(CompanionEngine.petId)
            val state = CompanionEngine.compute(s.txs, budget, pet, now)
            val total = if (s.accounts.isEmpty()) null else s.accounts.sumOf { balance(it, s.txs) }
            val name = Settings.str("userName").trim().split(" ").firstOrNull().orEmpty()

            return WidgetSnapshot(
                budget = budget, monthExpense = exp, monthIncome = inc, todaySpend = todaySum, balance = total,
                saved = s.goals.sumOf { it.saved }, goal = pickGoal(s), nextPayment = nextPayment(s, today),
                topCats = top, level = state.level, levelFraction = state.progress.toDouble().coerceIn(0.0, 1.0),
                mood = state.mood.raw, userName = name, petId = pet.id, petName = pet.name, phrase = state.phrase,
                week = week, hideAmounts = ru.koshelek.app.ui.Look.hideAmounts,
            )
        }

        private fun dot(day: LocalDate, today: LocalDate, spend: Double, budget: Double): WidgetDot {
            if (day.isAfter(today)) return WidgetDot.future
            if (day == today && spend == 0.0) return WidgetDot.today
            val limit = if (budget > 0) budget / day.lengthOfMonth() else FALLBACK_DAILY_LIMIT
            return when {
                spend <= limit -> WidgetDot.done
                spend <= limit * 2 -> WidgetDot.partial
                else -> WidgetDot.missed
            }
        }

        /** Самая «близкая к цели» из незавершённых копилок; если таких нет — первая. */
        private fun pickGoal(s: Snapshot): WidgetGoal? {
            fun frac(g: ru.koshelek.app.data.Goal) = if (g.target > 0) minOf(1.0, g.saved / g.target) else 0.0
            val open = s.goals.filter { it.target > 0 && it.saved < it.target }
            val g = open.maxByOrNull { frac(it) } ?: s.goals.firstOrNull() ?: return null
            return WidgetGoal(g.name, frac(g))
        }

        /** Ближайший платёж: открытая выплата по кредиту или регулярный платёж этого месяца. */
        private fun nextPayment(s: Snapshot, today: LocalDate): WidgetPayment? {
            var best: WidgetPayment? = null
            fun consider(p: WidgetPayment) { val b = best; if (b == null || b.due.isAfter(p.due)) best = p }
            for (i in allInstallments(s.debts)) if (i.isOpen && i.debt.isOut) consider(WidgetPayment(i.debt.name, i.amount, i.due))
            val ym = YearMonth.from(today)
            for (r in s.recs) {
                if (r.kind != TxKind.EXP) continue
                val d = r.due(ym) ?: continue
                if (r.isRecorded(ym, s.txs)) continue
                consider(WidgetPayment(r.name, r.amount, d))
            }
            return best
        }
    }
}

object WidgetMoney {
    /** «12 340 ₽» с неразрывными пробелами; «−» для отрицательных. Скрытые суммы — «•••• ₽». */
    fun rub(v: Double, hidden: Boolean = false): String {
        if (hidden) return "•••• ₽"
        if (!v.isFinite()) return "0 ₽"
        val n = Math.round(minOf(Math.abs(v), 1e15))
        val digits = n.toString()
        val sb = StringBuilder()
        digits.forEachIndexed { i, ch ->
            if (i > 0 && (digits.length - i) % 3 == 0) sb.append(' ')
            sb.append(ch)
        }
        return (if (v < 0 && n > 0) "−" else "") + sb + " ₽"
    }
}

/** Готовое к показу содержимое блока. Рисовальщик только рисует его. */
sealed class WidgetValue {
    data class Text(val t: String) : WidgetValue()
    data class Stat(val value: String, val caption: String) : WidgetValue()
    data class Ring(val fraction: Double, val center: String, val caption: String) : WidgetValue()
    data class Bar(val fraction: Double, val label: String) : WidgetValue()
    data class Dots(val dots: List<WidgetDot>, val first: Int) : WidgetValue()
    data class Lines(val lines: List<String>) : WidgetValue()
    data class Pet(val mood: String, val name: String) : WidgetValue()
}

object WidgetContent {
    fun value(b: WidgetBlock, s: WidgetSnapshot, now: LocalDateTime = LocalDateTime.now()): WidgetValue {
        fun money(v: Double) = WidgetMoney.rub(v, s.hideAmounts)
        return when (b.kind) {
            WidgetBlockKind.budgetRing -> {
                if (s.budget <= 0) WidgetValue.Ring(0.0, "—", "Нет лимита")
                else {
                    val f = s.monthExpense / s.budget
                    WidgetValue.Ring(f, "${Math.round(f * 100)}%", if (f > 1) "перерасход" else "лимита")
                }
            }
            WidgetBlockKind.percentText ->
                if (s.budget <= 0) WidgetValue.Text("—") else WidgetValue.Text("${Math.round(s.monthExpense / s.budget * 100)}%")
            WidgetBlockKind.todaySpend -> WidgetValue.Stat(money(s.todaySpend), "сегодня")
            WidgetBlockKind.dailyLeft -> {
                if (s.budget <= 0) WidgetValue.Stat("—", "Нет лимита")
                else {
                    val left = s.budget - s.monthExpense
                    if (left <= 0) WidgetValue.Stat(money(0.0), "лимит исчерпан")
                    else {
                        val daysLeft = maxOf(1, YearMonth.from(now).lengthOfMonth() - now.dayOfMonth + 1)
                        WidgetValue.Stat(money(left / daysLeft), "можно в день")
                    }
                }
            }
            WidgetBlockKind.monthExpense -> WidgetValue.Stat(money(s.monthExpense), "расходы за месяц")
            WidgetBlockKind.monthIncome -> WidgetValue.Stat(money(s.monthIncome), "доходы за месяц")
            WidgetBlockKind.balance -> s.balance?.let { WidgetValue.Stat(money(it), "на счетах") } ?: WidgetValue.Stat("—", "Нет счетов")
            WidgetBlockKind.savings ->
                if (s.goal == null && s.saved == 0.0) WidgetValue.Stat("—", "Нет копилок") else WidgetValue.Stat(money(s.saved), "в копилках")
            WidgetBlockKind.goalBar -> {
                val g = s.goal
                if (g == null) WidgetValue.Bar(0.0, "Нет копилок")
                else { val f = g.fraction.coerceIn(0.0, 1.0); WidgetValue.Bar(f, "${g.name} · ${Math.round(f * 100)}%") }
            }
            WidgetBlockKind.nextPayment -> {
                val p = s.nextPayment
                if (p == null) WidgetValue.Stat("Платежей нет", "Ближайший платёж")
                else {
                    val days = ChronoUnit.DAYS.between(now.toLocalDate(), p.due).toInt()
                    val whenText = when { days < 0 -> "просрочен"; days == 0 -> "сегодня"; days == 1 -> "завтра"; else -> "через $days дн." }
                    WidgetValue.Stat(p.name, "$whenText · ${money(p.amount)}")
                }
            }
            WidgetBlockKind.topCategories ->
                if (s.topCats.isEmpty()) WidgetValue.Lines(listOf("Нет трат")) else WidgetValue.Lines(s.topCats.map { "${it.name} · ${money(it.value)}" })
            WidgetBlockKind.level -> WidgetValue.Bar(s.levelFraction, "Уровень ${s.level}")
            WidgetBlockKind.phrase -> WidgetValue.Text(s.phrase.ifEmpty { "Я рядом" })
            WidgetBlockKind.weekDots -> WidgetValue.Dots(if (s.week.size == 7) s.week else List(7) { WidgetDot.none }, s.firstWeekday)
            WidgetBlockKind.date -> WidgetValue.Text(russianDate(now.toLocalDate()))
            WidgetBlockKind.greeting -> {
                val base = when (now.hour) { in 5..11 -> "Доброе утро"; in 12..17 -> "Добрый день"; in 18..22 -> "Добрый вечер"; else -> "Доброй ночи" }
                val name = s.userName.trim()
                WidgetValue.Text(if (name.isEmpty()) base else "$base, $name")
            }
            WidgetBlockKind.petImage -> WidgetValue.Pet(s.mood, s.petName)
            WidgetBlockKind.customText -> WidgetValue.Text(b.text.ifEmpty { "Мой текст" })
        }
    }

    /** «пн, 26 октября». Названия заданы явно, чтобы результат не зависел от платформы и локали. */
    fun russianDate(d: LocalDate): String {
        val weekdays = listOf("пн", "вт", "ср", "чт", "пт", "сб", "вс")
        val months = listOf("января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря")
        return "${weekdays[d.dayOfWeek.value - 1]}, ${d.dayOfMonth} ${months[d.monthValue - 1]}"
    }
}
