package ru.koshelek.app.data

import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import ru.koshelek.app.core.*
import java.time.LocalDate
import java.time.YearMonth

class AIError(message: String) : Exception(message)

/** ИИ через сервер Копилки: ключ хранится на сервере, приложение передаёт только токен входа. */
object Claude {
    val available get() = Server.loggedIn && Settings.bool("serverAI")

    suspend fun ask(prompt: String, images: List<ByteArray> = emptyList(), maxTokens: Int = 2048, system: String? = null): String {
        val content = buildJsonArray {
            images.forEach { img ->
                add(buildJsonObject {
                    put("type", "image")
                    put("source", buildJsonObject {
                        put("type", "base64"); put("media_type", "image/jpeg")
                        put("data", Base64.encodeToString(img, Base64.NO_WRAP))
                    })
                })
            }
            add(buildJsonObject { put("type", "text"); put("text", prompt) })
        }
        return send(buildJsonObject {
            put("max_tokens", maxTokens)
            system?.let { put("system", it) }
            put("messages", buildJsonArray { add(buildJsonObject { put("role", "user"); put("content", content) }) })
        })
    }

    suspend fun chat(system: String, messages: List<Pair<Boolean, String>>): String = send(buildJsonObject {
        put("max_tokens", 2000); put("system", system)
        put("messages", buildJsonArray { messages.forEach { (u, t) -> add(buildJsonObject { put("role", if (u) "user" else "assistant"); put("content", t) }) } })
    })

    private suspend fun send(body: JsonObject): String {
        if (!Server.loggedIn) throw AIError("ИИ работает после входа в аккаунт Копилки")
        val o = try { Server.call("/api/kp/ai", body) } catch (e: ApiError) {
            throw AIError(when (e.status) {
                429 -> "Лимит ИИ на сегодня исчерпан"
                503 -> "ИИ на сервере не настроен"
                0 -> "Нет связи с сервером"
                else -> e.message ?: "Ошибка ИИ"
            })
        }
        val text = (o["content"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.takeIf { b -> b.str("type") == "text" }?.str("text") }?.joinToString("") ?: ""
        if (text.isBlank()) throw AIError("Не удалось разобрать ответ. Попробуйте иначе.")
        return text
    }

    suspend fun json(prompt: String, images: List<ByteArray> = emptyList()): JsonElement {
        var s = ask(prompt, images).trim()
        val i = s.indexOf("```")
        if (i >= 0) {
            var inner = s.substring(i + 3)
            inner.indexOf('\n').takeIf { it >= 0 }?.let { inner = inner.substring(it + 1) }
            inner.indexOf("```").takeIf { it >= 0 }?.let { inner = inner.substring(0, it) }
            s = inner
        }
        runCatching { return Json.parseToJsonElement(s) }
        val a = listOf(s.indexOf('['), s.indexOf('{')).filter { it >= 0 }.minOrNull()
        val b = listOf(s.lastIndexOf(']'), s.lastIndexOf('}')).maxOrNull()
        if (a != null && b != null && a < b) runCatching { return Json.parseToJsonElement(s.substring(a, b + 1)) }
        throw AIError("Не удалось разобрать ответ. Попробуйте сказать иначе.")
    }
}

// MARK: Распознанные записи

enum class ItemKind { TX, DEBT, GOAL, REC }

data class ParsedItem(
    val id: String = newId(),
    var kind: ItemKind = ItemKind.TX,
    var type: TxKind = TxKind.EXP,
    var cat: String = "other",
    var amount: Double = 0.0,
    var date: LocalDate = LocalDate.now(),
    var note: String = "",
    var debtId: String? = null,
    var goalId: String? = null,
    var sign: Double = 1.0,
    var recId: String? = null,
    var on: Boolean = true,
    var acc: String? = null,
    var recDay: Int = 1,
    var recYearly: Boolean = false,
    var recMonth: Int = 1,
)

object Brain {
    private fun contextLines(s: Snapshot): String {
        var t = ""
        if (s.accounts.isNotEmpty()) {
            val js = buildJsonArray { s.accounts.forEach { a -> add(buildJsonObject { put("id", a.id); put("название", a.name) }) } }
            t += "\nСчета пользователя: $js\nЕсли человек назвал, откуда платил или куда пришли деньги («с карты», «наличкой», «на Сбер»), добавь к операции \"acc\":\"<id>\" подходящего счёта. Если не назвал — не добавляй."
        }
        t += "\nЕсли человек говорит о регулярном платеже или подписке («каждый месяц», «ежемесячно», «раз в год», «подписка ... списывается 15-го») — добавь {\"kind\":\"rec\",\"type\":\"exp\"|\"inc\",\"amount\":число,\"cat\":\"id\",\"note\":\"название\",\"day\":число месяца,\"yearly\":false,\"month\":номер месяца для годовых}. Если при этом он сказал, что уже заплатил сейчас, — добавь ещё и обычную операцию."
        val debts = s.debts.filter { !it.isClosed }
        if (debts.isNotEmpty()) {
            val js = buildJsonArray {
                debts.forEach { d ->
                    add(buildJsonObject {
                        put("id", d.id); put("название", d.name); put("кредитор", d.lender); put("вид", d.type.title)
                        put("кто_должен", if (d.isOut) "пользователь должен" else "должны пользователю")
                        d.nextInst?.let { nx -> put("след_платёж", buildJsonObject { put("сумма", nx.amount); put("дата", DF.iso(nx.due)) }) }
                    })
                }
            }
            t += "\nДолги и кредиты пользователя: $js\nЕсли человек говорит, что заплатил, внёс, закинул, погасил по кредиту/займу/кредитке/долгу (или ему вернули долг) — верни {\"kind\":\"debt\",\"debt\":\"<id>\",\"amount\":число,\"date\":\"YYYY-MM-DD\"} для подходящего долга. Если сумму не назвал — возьми сумму следующего платежа. Такие платежи НЕ дублируй обычной тратой."
        }
        if (s.goals.isNotEmpty()) {
            val js = buildJsonArray { s.goals.forEach { g -> add(buildJsonObject { put("id", g.id); put("название", g.name) }) } }
            t += "\nКопилки пользователя: $js\nЕсли человек отложил, положил, закинул в копилку/на цель — верни {\"kind\":\"goal\",\"goal\":\"<id>\",\"amount\":число,\"date\":\"YYYY-MM-DD\"}; если взял из копилки — amount отрицательный. НЕ дублируй обычной тратой."
        }
        return t
    }

    fun clean(raw: JsonElement, s: Snapshot): List<ParsedItem> {
        val arr: List<JsonObject> = when (raw) {
            is JsonArray -> raw.mapNotNull { it as? JsonObject }
            is JsonObject -> (raw["items"] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
            else -> emptyList()
        }
        val limit = LocalDate.now().plusMonths(1)
        return arr.mapNotNull { x ->
            val rawAmount = x.num("amount")
            val amount = Math.round(Math.abs(rawAmount) * 100) / 100.0
            if (amount <= 0) return@mapNotNull null
            var date = DF.parseISO(x.str("date")) ?: LocalDate.now()
            if (date.isAfter(limit)) date = LocalDate.now()
            val it = ParsedItem(amount = amount, date = date)
            val kind = x.str("kind")
            if (kind == "debt") {
                val d = s.debts.firstOrNull { d -> d.id == x.str("debt") && !d.isClosed }
                if (d != null) { it.kind = ItemKind.DEBT; it.debtId = d.id; it.note = d.name; return@mapNotNull it }
            }
            if (kind == "goal") {
                val g = s.goals.firstOrNull { g -> g.id == x.str("goal") }
                if (g != null) { it.kind = ItemKind.GOAL; it.goalId = g.id; it.note = g.name; it.sign = if (rawAmount < 0) -1.0 else 1.0; return@mapNotNull it }
            }
            s.accounts.firstOrNull { a -> a.id == x.str("acc") }?.let { a -> it.acc = a.id }
            if (kind == "rec") {
                it.kind = ItemKind.REC
                it.recDay = x.num("day").toInt().takeIf { d -> d > 0 } ?: LocalDate.now().dayOfMonth
                it.recYearly = x.bool("yearly")
                it.recMonth = x.num("month").toInt().takeIf { m -> m > 0 } ?: LocalDate.now().monthValue
            }
            it.type = if (x.str("type") == "inc") TxKind.INC else TxKind.EXP
            it.cat = Catalog.valid(x.str("cat"), it.type)
            it.note = x.str("note").take(80)
            it
        }
    }

    suspend fun parseSpeech(text: String, s: Snapshot): List<ParsedItem> {
        if (!Claude.available) return LocalParser.parse(text)
        val prompt = """
            Ты помогаешь вести личный бюджет в рублях. ${timeNowLine()}
            Пользователь рассказал (голосовая диктовка или быстрая запись — разговорная речь, с паразитами, ошибками распознавания и оговорками):
            «$text»
            ${Catalog.describe()}${contextLines(s)}
            Правила:
            - Выдели каждую реально совершённую денежную операцию. То, что человек только планирует или хочет купить, не добавляй.
            - Если человек поправился («ой нет, не пятьсот, а шестьсот») — бери исправленное.
            - Числа словами и сленг: «полторы тыщи»=1500, «тыща», «штука», «косарь»=1000, «пятихатка»=500, «полтос»=50, «сотка»=100, «пятёрка» в контексте тысяч=5000, «восемь пятьсот», «восемь с половиной» (о тысячах)=8500, «к» и «тыс»=×1000. «где-то», «примерно», «около» — бери названное число.
            - Даты: «вчера», «позавчера», «в пятницу», «на выходных» переведи в YYYY-MM-DD, не позже сегодня. Если не сказано — сегодня.
            - Обычные операции: {"kind":"tx","type":"exp"|"inc","amount":число,"cat":"id","date":"YYYY-MM-DD","note":"коротко, с большой буквы, до 40 символов"}. Магазин или место — в note.
            Ответь только JSON-массивом записей. Если ничего не нашлось — [].
        """.trimIndent()
        val items = clean(Claude.json(prompt), s)
        return items.ifEmpty { LocalParser.parse(text) }
    }

    suspend fun parseReceipts(images: List<ByteArray>, s: Snapshot): List<ParsedItem> {
        val prompt = """
            Ты помогаешь вести личный бюджет в рублях. ${timeNowLine()}
            На изображениях — кассовые чеки, электронные чеки или скриншоты банковского приложения (история операций, уведомления, переводы).
            ${Catalog.describe()}
            Правила:
            - Чек: обычно одна операция на чек на итоговую сумму с датой чека. Если в чеке явно разные категории (например, продукты и одежда), раздели по категориям, суммы должны сходиться с итогом. note — название магазина.
            - Скриншот банка: каждая видимая операция отдельно. Поступления — inc, списания — exp. Переводы между своими счетами и пополнения своих вкладов пропусти. note — получатель/магазин как на экране.
            - Даты в формате YYYY-MM-DD. Если год не виден — текущий или прошлый, чтобы дата была не позже сегодня. Если даты нет — сегодня.
            Ответь только JSON-массивом: [{"kind":"tx","type":"exp","amount":1234.5,"cat":"food","date":"${DF.iso(LocalDate.now())}","note":"Пятёрочка"}]. Если операций не видно — [].
        """.trimIndent()
        return clean(Claude.json(prompt, images), s)
    }

    data class DebtDraft(val type: DebtType, val name: String, val lender: String, val total: Double, val payment: Double, val n: Int, val first: LocalDate, val rate: Double)

    suspend fun parseDebt(images: List<ByteArray>): DebtDraft {
        val prompt = """
            ${timeNowLine()} На изображениях — график платежей, договор или экран кредита/займа/кредитной карты из приложения банка или МФО.
            Извлеки данные для учёта ОСТАВШЕЙСЯ части долга:
            - name: короткое название по-русски («Кредит наличными», «Ипотека», «Кредитная карта»)
            - lender: банк или МФО
            - dtype: "credit" | "card" | "micro"
            - total: сколько всего осталось заплатить (сумма будущих неоплаченных платежей вместе с процентами; если видна только сумма к погашению — она)
            - payment: ежемесячный платёж (для разового займа = total)
            - n: сколько платежей осталось (для разового = 1)
            - first: дата ближайшего неоплаченного платежа YYYY-MM-DD
            - rate: ставка в % годовых числом или null (дневную ставку умножь на 365)
            Ответь только JSON-объектом: {"name":"","lender":"","dtype":"credit","total":0,"payment":0,"n":0,"first":"${DF.iso(LocalDate.now())}","rate":null}
        """.trimIndent()
        val o = Claude.json(prompt, images) as? JsonObject ?: throw AIError("Не удалось разобрать график")
        val n = maxOf(1, o.num("n").toInt())
        val total = o.num("total")
        if (total <= 0) throw AIError("Не нашёл сумму долга на снимке")
        val t = DebtType.entries.firstOrNull { it.raw == o.str("dtype") && it != DebtType.PERSON } ?: DebtType.CREDIT
        return DebtDraft(t, o.str("name").take(40), o.str("lender").take(40), total, if (n <= 1) total else o.num("payment"), n,
            DF.parseISO(o.str("first")) ?: LocalDate.now().plusMonths(1), o.num("rate"))
    }

    const val persona = "Ты — личный финансовый советник в приложении «Копилка»: помогаешь человеку с бюджетом, накоплениями и долгами. Пиши по-русски, на «ты», коротко и по делу, как умный друг, а не банк. Опирайся только на данные пользователя, не выдумывай цифр. Давай конкретику: суммы, сроки, порядок действий. Если видишь проблему (лишние траты, просрочки, опасная долговая нагрузка, микрозаймы) — говори прямо, но без морали. Не давай советов по инвестициям в конкретные активы. Без markdown-заголовков и звёздочек; списки — строками с «— »."

    fun context(s: Snapshot): String {
        val now = YearMonth.now()
        return buildJsonObject {
            put("сегодня", DF.iso(LocalDate.now()))
            put("день_месяца", "${LocalDate.now().dayOfMonth} из ${now.lengthOfMonth()}")
            if (s.prefs.budget > 0) put("лимит_расходов_в_месяц", s.prefs.budget)
            put("средний_доход_в_месяц", averageIncome(s.txs).toInt())
            put("месяцы", buildJsonArray {
                for (k in 0..2) {
                    val t = totals(now.minusMonths(k.toLong()), s.txs)
                    add(buildJsonObject {
                        put("месяц", DF.month(t.month)); put("доход", t.inc.toInt()); put("расход", t.exp.toInt())
                        put("по_категориям", buildJsonObject { byCategory(t.items).forEach { c -> put(c.cat.name, c.sum.toInt()) } })
                    })
                }
            })
            put("долги", buildJsonArray {
                s.debts.filter { !it.isClosed }.forEach { d ->
                    add(buildJsonObject {
                        put("название", d.name); put("вид", d.type.title); put("я_должен", d.isOut); put("осталось", d.remaining.toInt())
                        put("платёж_в_месяц", d.payment.toInt()); put("платежей_осталось", d.schedule().count { it.isOpen })
                        put("ставка_годовых", d.rate); put("просрочено", d.schedule().count { it.st == InstStatus.OVERDUE })
                    })
                }
            })
            put("регулярные", buildJsonArray { s.recs.forEach { add("${it.name}: ${it.amount.toInt()} ₽ ${if (it.yearly) "в год" else "в месяц"}") } })
            put("копилки", buildJsonArray { s.goals.forEach { add("${it.name}: ${it.saved.toInt()} из ${it.target.toInt()}") } })
        }.toString()
    }

    suspend fun dailyTip(s: Snapshot, force: Boolean = false): String {
        val today = DF.iso(LocalDate.now())
        if (!force && Settings.str("tipDate") == today && Settings.str("tipText").isNotEmpty()) return Settings.str("tipText")
        val t = Claude.ask("$persona\n\nДанные пользователя: ${context(s)}\nДай ОДИН самый полезный на сегодня совет или замечание (2–3 предложения, до 300 знаков): что заметил в тратах, накоплениях или долгах и что конкретно сделать. Если данных мало — посоветуй, с чего начать вести учёт. Без вступлений.", maxTokens = 800).trim()
        Settings.setStr("tipText", t); Settings.setStr("tipDate", today)
        return t
    }

    suspend fun review(s: Snapshot, month: YearMonth): String {
        val data = buildJsonObject {
            put("месяц", DF.month(month))
            put("сегодня", DF.iso(LocalDate.now()))
            if (s.prefs.budget > 0) put("лимит_расходов", s.prefs.budget)
            put("по_месяцам", buildJsonArray {
                for (k in 2 downTo 0) {
                    val t = totals(month.minusMonths(k.toLong()), s.txs)
                    add(buildJsonObject {
                        put("месяц", DF.month(t.month)); put("доход", t.inc.toInt()); put("расход", t.exp.toInt())
                        put("расходы_по_категориям", buildJsonObject { byCategory(t.items).forEach { c -> put(c.cat.name, c.sum.toInt()) } })
                    })
                }
            })
            put("крупные_траты", buildJsonArray {
                totals(month, s.txs).items.filter { it.kind == TxKind.EXP }.sortedByDescending { it.amount }.take(8).forEach { t ->
                    add(buildJsonObject { put("сумма", t.amount.toInt()); put("категория", Catalog.cat(t.cat).name); put("заметка", t.note); put("дата", DF.iso(t.date)) })
                }
            })
        }
        val prompt = "Ты — внимательный финансовый помощник. Сделай короткий разбор личных финансов за ${DF.month(month).lowercase()} по данным ниже (суммы в рублях). Обращайся на «ты», пиши по-русски, живо и по делу.\nФормат: 5–8 пунктов, каждый с новой строки и начинается с «— ». Без заголовков, без markdown и звёздочек. Сначала что хорошо, потом проблемы (перерасход, рост категорий, долговая нагрузка, просрочки), в конце 2–3 конкретных совета с суммами. Если месяц ещё идёт, учитывай это. Не выдумывай данных, которых нет.\nДанные: $data"
        return Claude.ask(prompt, maxTokens = 1500)
    }
}

// MARK: Разбор без ИИ

object LocalParser {
    private val keywords = listOf(
        "salary" to "зарплат|зп(?![а-яё])|аванс|получк", "side" to "подработ|фриланс|халтур", "cashback" to "кэшб|кешб",
        "cafe" to "кафе|кофе|ресторан|бургер|пицц|шаурм|обед|ужин|кофейн|роллы|суши|доставк[аи] еды",
        "transport" to "такси|метро|автобус|бензин|азс|заправ|проезд|парковк|каршер|электричк",
        "food" to "продукт|магазин|пят[её]рочк|магнит|ашан|перекр[её]ст|лент[аы]|вкусвилл|мария|ярче|хлеб|молоко|еда",
        "home" to "квартир|аренд|жкх|жку|коммунал", "loans" to "кредит|займ|ипотек|долг",
        "subs" to "подписк|яндекс плюс|кинопоиск|иви|okko|icloud", "phone" to "связь|телефон|интернет|мтс|билайн|мегафон|теле2",
        "health" to "аптек|лекарств|врач|больниц|стоматолог|анализ", "clothes" to "одежд|обув|кроссовк|куртк|джинс",
        "fun" to "кино|игр|steam|концерт|клуб|скин", "gifts" to "подар",
    )
    private val numRe = Regex("(\\d[\\d\\s]*(?:[.,]\\d+)?)\\s*(тыс[а-яё.]*|к(?![а-яё])|k(?![a-z]))?", RegexOption.IGNORE_CASE)

    fun parse(text: String): List<ParsedItem> {
        val lt = text.lowercase()
        val date = when { lt.contains("позавчера") -> LocalDate.now().minusDays(2); lt.contains("вчера") -> LocalDate.now().minusDays(1); else -> LocalDate.now() }
        return text.split(Regex("[,;\\n]")).map { it.trim() }.filter { it.isNotEmpty() }.mapNotNull { p ->
            val m = numRe.find(p) ?: return@mapNotNull null
            var amount = parseAmount(m.groupValues[1]) ?: return@mapNotNull null
            if (m.groupValues[2].isNotEmpty()) amount *= 1000
            if (amount <= 0) return@mapNotNull null
            val low = p.lowercase()
            val cat = keywords.firstOrNull { Regex(it.second).containsMatchIn(low) }?.first
            val isInc = (cat?.let { Catalog.cat(it).kind == TxKind.INC } ?: false) || Regex("получил|пришл|доход|заработал").containsMatchIn(low)
            val type = if (isInc) TxKind.INC else TxKind.EXP
            var note = p.removeRange(m.range)
            for (w in listOf("позавчера", "вчера", "сегодня", "рублей", "рубля", "руб", "₽")) note = note.replace(w, "", ignoreCase = true)
            note = note.split(" ").filter { it.isNotBlank() }.joinToString(" ").cap()
            ParsedItem(type = type, cat = Catalog.valid(cat ?: "", type), amount = amount, date = date, note = note.take(40))
        }
    }
}

// MARK: Сохранение

data class SaveResult(var count: Int = 0, val summary: MutableList<String> = mutableListOf(), var closedDebt: String? = null, var goalDone: String? = null)

object Saver {
    fun apply(items: List<ParsedItem>, s: Snapshot, account: String? = null): SaveResult {
        val res = SaveResult()
        for (x in items) {
            if (!x.on || x.amount <= 0) continue
            val acc = x.acc ?: account
            when (x.kind) {
                ItemKind.REC -> {
                    val name = x.note.trim().ifEmpty { Catalog.cat(x.cat).name }
                    Store.saveRec(Recurring(name = name, amount = x.amount, kind = x.type, cat = Catalog.valid(x.cat, x.type),
                        day = x.recDay.coerceIn(1, 31), yearly = x.recYearly, month = x.recMonth.coerceIn(1, 12)))
                    res.summary += "регулярный «$name» ${Fmt.rubU(x.amount)}"
                }
                ItemKind.DEBT -> {
                    val d = s.debts.firstOrNull { it.id == x.debtId } ?: continue
                    val before = d.remaining
                    val nd = payDebt(d, x.amount, x.date, acc)
                    if (before > 0 && nd.remaining <= 0) res.closedDebt = d.name
                    res.summary += "${d.name} ${Fmt.rubU(x.amount)}"
                }
                ItemKind.GOAL -> {
                    val g = s.goals.firstOrNull { it.id == x.goalId } ?: continue
                    val before = g.saved
                    val ng = g.copy(log = g.log + GoalEntry(x.date, x.sign * x.amount))
                    Store.saveGoal(ng)
                    if (before < g.target && ng.saved >= g.target) res.goalDone = g.name
                    res.summary += "${if (x.sign < 0) "из" else "в"} копилку «${g.name}» ${Fmt.rubU(x.amount)}"
                }
                ItemKind.TX -> {
                    Store.saveTx(Tx(kind = x.type, amount = x.amount, cat = Catalog.valid(x.cat, x.type), note = x.note.trim().cleanedNote(),
                        date = x.date, acc = acc, rec = x.recId))
                    res.summary += "${x.note.ifEmpty { Catalog.cat(x.cat).name }} ${Fmt.rubU(x.amount)}"
                }
            }
            res.count++
        }
        return res
    }
}

suspend fun <T> io(block: suspend () -> T): T = withContext(Dispatchers.IO) { block() }
