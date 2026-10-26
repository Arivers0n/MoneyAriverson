package ru.koshelek.app.core

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

val RU: Locale = Locale.forLanguageTag("ru-RU")
val zone: ZoneId get() = ZoneId.systemDefault()

/** Секунды Unix → дата (в полдень местного времени, как на iPhone). */
fun epochToDate(sec: Double): LocalDate = Instant.ofEpochMilli((sec * 1000).toLong()).atZone(zone).toLocalDate()
fun dateToEpoch(d: LocalDate): Double = d.atTime(12, 0).atZone(zone).toEpochSecond().toDouble()
fun nowEpoch(): Double = System.currentTimeMillis() / 1000.0

/** Swift JSONEncoder по умолчанию кодирует Date как секунды от 2001-01-01. */
const val REF_OFFSET = 978_307_200.0
fun refToDate(ref: Double): LocalDate = epochToDate(ref + REF_OFFSET)
fun dateToRef(d: LocalDate): Double = dateToEpoch(d) - REF_OFFSET

object Fmt {
    var showKopecks = false
    private val sym = DecimalFormatSymbols(RU).apply { groupingSeparator = ' '; decimalSeparator = ',' }
    private val nf0 = DecimalFormat("#,##0", sym)
    private val nf2 = DecimalFormat("#,##0.00", sym)
    private val nfIn = DecimalFormat("0.##", sym)

    fun rub(v: Double): String {
        val a = abs(v)
        val s = if (showKopecks && (a * 100).roundToLong() % 100 != 0L) nf2.format(a) else nf0.format(a.roundToLong())
        return (if (v < 0 && a >= 0.5) "−" else "") + s + " ₽"
    }
    fun rubU(v: Double) = rub(abs(v))
    fun signed(v: Double) = (if (v >= 0) "+" else "−") + rubU(v)
    fun input(v: Double) = if (v == 0.0) "" else nfIn.format(v)
    fun compact(v: Double): String {
        val a = abs(v)
        return when {
            a >= 1_000_000 -> String.format(RU, "%.1fм", a / 1_000_000)
            a >= 1000 -> "${(a / 1000).roundToLong()}к"
            else -> "${a.roundToLong()}"
        }
    }
}

fun parseAmount(s: String): Double? =
    s.replace(" ", "").replace(" ", "").replace(",", ".").toDoubleOrNull()?.takeIf { it.isFinite() }

fun plural(n: Int, one: String, few: String, many: String): String {
    val m = abs(n) % 100; val k = m % 10
    return when { m in 11..19 -> many; k == 1 -> one; k in 2..4 -> few; else -> many }
}

object DF {
    private val cache = HashMap<String, DateTimeFormatter>()
    fun f(p: String): DateTimeFormatter = cache.getOrPut(p) { DateTimeFormatter.ofPattern(p, RU) }
    fun s(d: LocalDate, p: String): String = d.format(f(p))
    fun iso(d: LocalDate): String = d.toString()
    fun parseISO(s: String): LocalDate? = runCatching { LocalDate.parse(s.take(10)) }.getOrNull()
    fun month(m: YearMonth): String = m.atDay(1).format(f("LLLL yyyy")).cap()
    fun monthTitle(m: YearMonth): String =
        if (m.year == YearMonth.now().year) m.atDay(1).format(f("LLLL")).cap()
        else m.atDay(1).format(f("LLL yyyy")).replace(".", "").cap()
    fun short(d: LocalDate): String = d.format(f("d MMM")).replace(".", "")
    fun dayLabel(d: LocalDate): String {
        val n = ChronoUnit.DAYS.between(d, LocalDate.now())
        return when (n) { 0L -> "Сегодня"; 1L -> "Вчера"; else -> d.format(f("EE, d MMMM")).cap() }
    }
}

fun String.cap(): String = replaceFirstChar { if (it.isLowerCase()) it.titlecase(RU) else it.toString() }

fun relDays(due: LocalDate): Pair<String, Boolean> {
    val n = ChronoUnit.DAYS.between(LocalDate.now(), due).toInt()
    return when {
        n == 0 -> "сегодня" to false
        n == 1 -> "завтра" to false
        n > 0 -> "через $n ${plural(n, "день", "дня", "дней")}" to false
        else -> "просрочен на ${-n} ${plural(-n, "день", "дня", "дней")}" to true
    }
}

fun YearMonth.contains(d: LocalDate) = d.year == year && d.month == month

/** «Купил кофе .» → «Купил кофе». */
fun String.cleanedNote(): String {
    var s = replace(Regex("\\s+"), " ").replace(Regex(" ([.,!?;:])"), "$1").trim()
    while (s.isNotEmpty() && s.last() in ".,;:-—") s = s.dropLast(1).trim()
    return s
}

fun timeNowLine(): String {
    val now = LocalDateTime.now()
    return "Сегодня ${DF.iso(now.toLocalDate())} (${now.toLocalDate().format(DF.f("EEEE"))}), сейчас ${now.toLocalTime().format(DateTimeFormatter.ofPattern("HH:mm"))}."
}

@Suppress("unused") private val noon = LocalTime.NOON
