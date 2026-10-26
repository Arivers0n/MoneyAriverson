package ru.koshelek.app.data

import kotlinx.serialization.json.*
import ru.koshelek.app.core.*
import java.time.LocalDate
import java.util.UUID

/** Запись так, как она лежит на сервере: модели — лишь «взгляд» на data, поэтому поля iPhone не теряются. */
data class Doc(
    val cid: String,
    val kind: String,
    val data: JsonObject,
    val deleted: Boolean = false,
    val cts: Double = System.currentTimeMillis().toDouble(),   // мс
    val author: String = "",
    val space: String = "",
    val dirty: Boolean = false,
)

fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull ?: ""
fun JsonObject.num(k: String): Double = (this[k] as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.let(::parseAmount) } ?: 0.0
fun JsonObject.bool(k: String): Boolean = (this[k] as? JsonPrimitive)?.booleanOrNull ?: false
fun JsonObject.has(k: String) = this[k] != null && this[k] !is JsonNull

fun newId(): String = UUID.randomUUID().toString().uppercase()

enum class TxKind(val raw: String) { EXP("exp"), INC("inc"), TR("tr");
    companion object { fun of(s: String) = entries.firstOrNull { it.raw == s } ?: EXP } }

data class Tx(
    val id: String = newId(),
    val kind: TxKind = TxKind.EXP,
    val amount: Double = 0.0,
    val cat: String = "other",
    val note: String = "",
    val date: LocalDate = LocalDate.now(),
    val created: Double = nowEpoch(),
    val acc: String? = null,
    val to: String? = null,
    val rec: String? = null,
    val author: String = "",
) {
    val signed: Double get() = when (kind) { TxKind.INC -> amount; TxKind.EXP -> -amount; TxKind.TR -> 0.0 }
    fun payload(base: JsonObject = JsonObject(emptyMap())): JsonObject {
        val m = base.toMutableMap()
        m["type"] = JsonPrimitive(kind.raw); m["amount"] = JsonPrimitive(amount); m["cat"] = JsonPrimitive(cat)
        m["note"] = JsonPrimitive(note); m["date"] = JsonPrimitive(dateToEpoch(date)); m["created"] = JsonPrimitive(created)
        if (acc != null) m["acc"] = JsonPrimitive(acc) else m.remove("acc")
        if (to != null) m["to"] = JsonPrimitive(to) else m.remove("to")
        if (rec != null) m["rec"] = JsonPrimitive(rec) else m.remove("rec")
        return JsonObject(m)
    }
    companion object {
        fun from(d: Doc) = Tx(
            id = d.cid, kind = TxKind.of(d.data.str("type")), amount = d.data.num("amount"),
            cat = d.data.str("cat").ifEmpty { "other" }, note = d.data.str("note"),
            date = epochToDate(d.data.num("date")), created = d.data.num("created"),
            acc = d.data.str("acc").ifEmpty { null }, to = d.data.str("to").ifEmpty { null },
            rec = d.data.str("rec").ifEmpty { null }, author = d.author,
        )
    }
}


data class Account(val id: String = newId(), val name: String = "", val start: Double = 0.0, val hex: String = "2B47C9", val created: Double = nowEpoch()) {
    fun payload() = buildJsonObject { put("name", name); put("start", start); put("hex", hex); put("created", created) }
    companion object {
        fun from(d: Doc) = Account(d.cid, d.data.str("name"), d.data.num("start"), d.data.str("hex").ifEmpty { "2B47C9" }, d.data.num("created"))
    }
}

data class Paid(val date: LocalDate, val amount: Double, val late: Boolean)
data class ExtraPay(val date: LocalDate, val amount: Double)

enum class DebtType(val raw: String, val title: String) {
    CREDIT("credit", "Кредит"), CARD("card", "Кредитка"), MICRO("micro", "Микрозайм"), PERSON("person", "Человек");
    companion object { fun of(s: String) = entries.firstOrNull { it.raw == s } ?: CREDIT }
}

data class Debt(
    val id: String = newId(),
    val type: DebtType = DebtType.CREDIT,
    val dirIn: Boolean = false,
    val name: String = "",
    val lender: String = "",
    val total: Double = 0.0,
    val payment: Double = 0.0,
    val n: Int = 1,
    val first: LocalDate = LocalDate.now(),
    val rate: Double = 0.0,
    val created: Double = nowEpoch(),
    val payments: Map<Int, Paid> = emptyMap(),
    val extras: List<ExtraPay> = emptyList(),
) {
    val isOut get() = !dirIn
    fun payload() = buildJsonObject {
        put("type", type.raw); put("dirIn", dirIn); put("name", name); put("lender", lender)
        put("total", total); put("payment", payment); put("n", n); put("first", dateToEpoch(first))
        put("rate", rate); put("created", created)
        // Формат Swift для словаря с числовыми ключами: [ключ, значение, ключ, значение…]
        put("payments", buildJsonArray {
            payments.toSortedMap().forEach { (k, p) ->
                add(k)
                add(buildJsonObject { put("date", dateToRef(p.date)); put("amount", p.amount); put("late", p.late) })
            }
        })
        put("extras", buildJsonArray {
            extras.forEach { e -> add(buildJsonObject { put("date", dateToRef(e.date)); put("amount", e.amount) }) }
        })
    }
    companion object {
        fun from(d: Doc): Debt {
            val o = d.data
            val pays = mutableMapOf<Int, Paid>()
            (o["payments"] as? JsonArray)?.let { arr ->
                var i = 0
                while (i + 1 < arr.size) {
                    val k = (arr[i] as? JsonPrimitive)?.intOrNull
                    val v = arr[i + 1] as? JsonObject
                    if (k != null && v != null) pays[k] = Paid(refToDate(v.num("date")), v.num("amount"), v.bool("late"))
                    i += 2
                }
            }
            (o["payments"] as? JsonObject)?.forEach { (k, v) ->
                val vo = v as? JsonObject ?: return@forEach
                k.toIntOrNull()?.let { pays[it] = Paid(refToDate(vo.num("date")), vo.num("amount"), vo.bool("late")) }
            }
            val ex = (o["extras"] as? JsonArray)?.mapNotNull { e -> (e as? JsonObject)?.let { ExtraPay(refToDate(it.num("date")), it.num("amount")) } } ?: emptyList()
            return Debt(d.cid, DebtType.of(o.str("type")), o.bool("dirIn"), o.str("name"), o.str("lender"), o.num("total"),
                o.num("payment"), maxOf(1, o.num("n").toInt()), epochToDate(o.num("first")), o.num("rate"), o.num("created"), pays, ex)
        }
    }
}

data class Recurring(
    val id: String = newId(), val name: String = "", val amount: Double = 0.0, val kind: TxKind = TxKind.EXP,
    val cat: String = "subs", val day: Int = 1, val yearly: Boolean = false, val month: Int = 1, val created: Double = nowEpoch(),
) {
    fun payload() = buildJsonObject {
        put("name", name); put("amount", amount); put("type", kind.raw); put("cat", cat); put("day", day)
        put("yearly", yearly); put("month", month); put("created", created)
    }
    companion object {
        fun from(d: Doc) = Recurring(d.cid, d.data.str("name"), d.data.num("amount"), TxKind.of(d.data.str("type")),
            d.data.str("cat").ifEmpty { "subs" }, maxOf(1, d.data.num("day").toInt()), d.data.bool("yearly"),
            maxOf(1, d.data.num("month").toInt()), d.data.num("created"))
    }
}

data class GoalEntry(val date: LocalDate, val amount: Double)

data class Goal(
    val id: String = newId(), val name: String = "", val target: Double = 0.0, val deadline: LocalDate? = null,
    val hex: String = "2B47C9", val created: Double = nowEpoch(), val log: List<GoalEntry> = emptyList(),
    val autoPercent: Double = 0.0, val roundUp: Int = 0, val symbol: String = "banknote.fill",
) {
    val saved get() = log.sumOf { it.amount }
    fun payload() = buildJsonObject {
        put("name", name); put("target", target); put("hex", hex); put("created", created)
        put("log", buildJsonArray { log.forEach { e -> add(buildJsonObject { put("date", dateToRef(e.date)); put("amount", e.amount) }) } })
        put("autoPercent", autoPercent); put("roundUp", roundUp); put("symbol", symbol)
        deadline?.let { put("deadline", dateToEpoch(it)) }
    }
    companion object {
        fun from(d: Doc) = Goal(d.cid, d.data.str("name"), d.data.num("target"),
            if (d.data.has("deadline")) epochToDate(d.data.num("deadline")) else null,
            d.data.str("hex").ifEmpty { "2B47C9" }, d.data.num("created"),
            (d.data["log"] as? JsonArray)?.mapNotNull { e -> (e as? JsonObject)?.let { GoalEntry(refToDate(it.num("date")), it.num("amount")) } } ?: emptyList(),
            d.data.num("autoPercent"), d.data.num("roundUp").toInt(), d.data.str("symbol").ifEmpty { "banknote.fill" })
    }
}

/** Настройки пространства: общий лимит, лимиты категорий, свои категории. */
data class SpacePrefs(
    val budget: Double = 0.0,
    val catLimits: Map<String, Double> = emptyMap(),
    val cats: JsonObject = JsonObject(emptyMap()),
) {
    fun payload() = buildJsonObject {
        put("budget", budget)
        put("catLimits", buildJsonObject { catLimits.forEach { (k, v) -> put(k, v) } })
        put("cats", cats)
    }
    companion object {
        fun from(o: JsonObject) = SpacePrefs(
            o.num("budget"),
            (o["catLimits"] as? JsonObject)?.mapValues { (it.value as? JsonPrimitive)?.doubleOrNull ?: 0.0 } ?: emptyMap(),
            (o["cats"] as? JsonObject) ?: JsonObject(emptyMap()),
        )
    }
}
