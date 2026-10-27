package ru.koshelek.app.core

import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import ru.koshelek.app.data.Settings
import ru.koshelek.app.data.Tx
import ru.koshelek.app.data.TxKind
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.YearMonth
import java.time.temporal.ChronoUnit
import kotlin.math.abs

data class CompanionState(
    val mood: CompanionMood = CompanionMood.CALM,
    val level: Int = 1,
    val xpInLevel: Int = 0,
    val xpNeed: Int = 60,
    val totalXP: Int = 0,
    val treats: Int = 0,
    val fed: Int = 0,
    val phrase: String = "",
) {
    val progress: Float get() = if (xpNeed > 0) minOf(1f, xpInLevel.toFloat() / xpNeed) else 0f
}

/** Настроение, опыт, уровни и угощения выводятся из операций — те же правила, что на iPhone. */
object CompanionEngine {
    val epoch: LocalDate = LocalDate.of(2026, 10, 27)
    private const val FALLBACK_DAILY_LIMIT = 1500.0

    // Выбор живёт на этом устройстве; значения наблюдаемые, чтобы экран обновлялся сразу.
    private val idState = mutableStateOf(Settings.str("pet.id").let { s -> if (CompanionCatalog.all.any { it.id == s }) s else CompanionCatalog.DEFAULT_ID })
    private val fedState = mutableIntStateOf(Settings.int("pet.fed", 0))
    private val fedDayState = mutableIntStateOf(Settings.int("pet.fedDay", -1))
    var petId: String
        get() = idState.value
        set(v) { Settings.setStr("pet.id", v); idState.value = v }
    var fedCount: Int
        get() = fedState.intValue
        set(v) { Settings.setInt("pet.fed", v); fedState.intValue = v }
    var fedDay: Int
        get() = fedDayState.intValue
        set(v) { Settings.setInt("pet.fedDay", v); fedDayState.intValue = v }

    fun dayIndex(d: LocalDate): Int = ChronoUnit.DAYS.between(epoch, d).toInt()

    fun compute(
        txs: List<Tx>, budget: Double, pet: CompanionDef,
        now: LocalDateTime = LocalDateTime.now(), fed: Int = fedCount, fedDay: Int = this.fedDay,
    ): CompanionState {
        val today = dayIndex(now.toLocalDate())
        val mine = txs.filter { it.kind != TxKind.TR && dayIndex(it.date) in 0..today }
        val daysInMonth = YearMonth.from(now).lengthOfMonth()
        val dailyLimit = if (budget > 0) budget / daysInMonth else FALLBACK_DAILY_LIMIT

        val spendByDay = HashMap<Int, Double>()
        val catDays = HashMap<Int, MutableSet<String>>()
        for (o in mine) if (o.kind == TxKind.EXP && Calc.counts(o)) {
            val i = dayIndex(o.date)
            spendByDay[i] = (spendByDay[i] ?: 0.0) + o.amount
            catDays.getOrPut(i) { mutableSetOf() }.add(o.cat)
        }

        var xp = mine.size * 10 + fed * 15
        val closed = maxOf(0, today)
        var noSpend = 0; var cafeFree = 0; var funFree = 0
        val funCats = setOf("fun", "clothes", "gifts", "other")
        for (i in 0 until closed) {
            if ((spendByDay[i] ?: 0.0) == 0.0) noSpend++
            val cs = catDays[i] ?: emptySet()
            if ("cafe" !in cs) cafeFree++
            if (cs.none { it in funCats }) funFree++
        }
        xp += noSpend * 30
        var w = 0
        while ((w + 1) * 7 <= closed) {
            val sum = (w * 7 until (w + 1) * 7).sumOf { spendByDay[it] ?: 0.0 }
            if (sum <= dailyLimit * 7) xp += 50
            w++
        }

        var level = 1; var left = xp
        while (left >= 60 * level) { left -= 60 * level; level++ }

        val treats = maxOf(0, cafeFree / 3 + funFree / 7 - fed)

        val todaySpend = spendByDay[today] ?: 0.0
        val ym = YearMonth.from(now)
        val monthExp = mine.filter { it.kind == TxKind.EXP && Calc.counts(it) && YearMonth.from(it.date) == ym }.sumOf { it.amount }
        val hour = now.hour
        val opsToday = mine.any { dayIndex(it.date) == today }
        val ratio = noSpend.toDouble() / maxOf(1, closed)
        var mood = when {
            (hour >= 23 || hour < 6) && !opsToday -> CompanionMood.SLEEPY
            (budget > 0 && monthExp > budget) || todaySpend > dailyLimit * 2 -> CompanionMood.SAD
            todaySpend <= dailyLimit && closed >= 3 && ratio >= 0.35 -> CompanionMood.HAPPY
            else -> CompanionMood.CALM
        }
        if (fedDay == today) {
            if (mood == CompanionMood.SAD) mood = CompanionMood.CALM else if (mood == CompanionMood.CALM) mood = CompanionMood.HAPPY
        }
        return CompanionState(mood, level, left, 60 * level, xp, treats, fed, phrase(pet, mood, today))
    }

    fun phrase(pet: CompanionDef, mood: CompanionMood, seed: Int): String {
        if (mood == CompanionMood.SAD && pet.id == "iskorka") return "Ой, кажется, мы тратим слишком быстро. Давай поаккуратнее!"
        val arr = pet.lines[mood].orEmpty()
        return if (arr.isEmpty()) "" else arr[abs(seed) % arr.size]
    }

    /** Угостить: нужен хотя бы один гостинец. */
    fun feed(state: CompanionState, now: LocalDate = LocalDate.now()): Boolean {
        if (state.treats <= 0) return false
        fedCount += 1
        fedDay = dayIndex(now)
        return true
    }
}

/** Голос питомца для ИИ. */
object AICoach {
    fun persona(pet: CompanionDef, mood: CompanionMood, base: String): String {
        if (pet.id == CompanionCatalog.DEFAULT_ID) return base
        return base + "\n\nНа время этого разговора ты — питомец-напарник. ${pet.voice} Настроение сейчас: ${mood.title.lowercase()}. Оставайся в образе, но цифры и советы давай точно и по делу; отвечай коротко."
    }
}
