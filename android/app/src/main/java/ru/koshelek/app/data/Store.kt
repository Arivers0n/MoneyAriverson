package ru.koshelek.app.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.io.File

/** Всё, что видно в текущем бюджете (пространстве). */
data class Snapshot(
    val txs: List<Tx> = emptyList(),
    val accounts: List<Account> = emptyList(),
    val debts: List<Debt> = emptyList(),
    val recs: List<Recurring> = emptyList(),
    val goals: List<Goal> = emptyList(),
    val prefs: SpacePrefs = SpacePrefs(),
)

object Settings {
    lateinit var sp: SharedPreferences
    fun init(ctx: Context) { sp = ctx.getSharedPreferences("kopilka", Context.MODE_PRIVATE) }
    fun str(k: String, d: String = "") = sp.getString(k, d) ?: d
    fun setStr(k: String, v: String?) = sp.edit().apply { if (v == null) remove(k) else putString(k, v) }.apply()
    fun bool(k: String, d: Boolean = false) = sp.getBoolean(k, d)
    fun setBool(k: String, v: Boolean) = sp.edit().putBoolean(k, v).apply()
    fun dbl(k: String, d: Double = 0.0) = sp.getString(k, null)?.toDoubleOrNull() ?: d
    fun setDbl(k: String, v: Double) = sp.edit().putString(k, v.toString()).apply()
    fun int(k: String, d: Int = 0) = sp.getInt(k, d)
    fun setInt(k: String, v: Int) = sp.edit().putInt(k, v).apply()
}

object Space {
    const val LOCAL = "local"
    var current: String
        get() = Settings.str("space", LOCAL).ifEmpty { LOCAL }
        set(v) = Settings.setStr("space", v)
}

object Store {
    private val json = Json { ignoreUnknownKeys = true }
    private lateinit var file: File
    private val docs = LinkedHashMap<String, Doc>()   // ключ: space|kind|cid
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var saveJob: Job? = null
    private val _snap = MutableStateFlow(Snapshot())
    val snapshot: StateFlow<Snapshot> = _snap
    /** Вызывается после локальных изменений — синхронизация подхватит. */
    var onLocalChange: (() -> Unit)? = null

    fun init(ctx: Context) {
        file = File(ctx.filesDir, "docs.json")
        runCatching {
            if (file.exists()) {
                val arr = json.parseToJsonElement(file.readText()).jsonArray
                for (e in arr) {
                    val o = e.jsonObject
                    val d = Doc(o.str("cid"), o.str("kind"), o["data"]?.jsonObject ?: JsonObject(emptyMap()), o.bool("deleted"),
                        o.num("cts"), o.str("author"), o.str("space"), o.bool("dirty"))
                    docs[key(d)] = d
                }
            }
        }
        publish()
    }

    private fun key(d: Doc) = "${d.space}|${d.kind}|${d.cid}"
    private fun key(space: String, kind: String, cid: String) = "$space|$kind|$cid"

    @Synchronized
    fun publish() {
        val sp = Space.current
        val live = docs.values.filter { it.space == sp && !it.deleted }
        fun <T> of(kind: String, f: (Doc) -> T) = live.filter { it.kind == kind }.mapNotNull { runCatching { f(it) }.getOrNull() }
        val prefsDoc = docs[key(sp, "prefs", "prefs")]
        _snap.value = Snapshot(
            txs = of("tx", Tx::from).sortedWith(compareByDescending<Tx> { it.date }.thenByDescending { it.created }),
            accounts = of("acc", Account::from).sortedBy { it.created },
            debts = of("debt", Debt::from).sortedBy { it.created },
            recs = of("rec", Recurring::from).sortedBy { it.created },
            goals = of("goal", Goal::from).sortedBy { it.created },
            prefs = prefsDoc?.let { SpacePrefs.from(it.data) } ?: SpacePrefs(),
        )
    }

    private fun persistSoon() {
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(300)
            val arr = synchronized(this@Store) {
                buildJsonArray {
                    docs.values.forEach { d ->
                        add(buildJsonObject {
                            put("cid", d.cid); put("kind", d.kind); put("data", d.data); put("deleted", d.deleted)
                            put("cts", d.cts); put("author", d.author); put("space", d.space); put("dirty", d.dirty)
                        })
                    }
                }
            }
            runCatching { file.writeText(arr.toString()) }
        }
    }

    // MARK: локальные изменения

    @Synchronized
    fun put(kind: String, cid: String, data: JsonObject) {
        val sp = Space.current
        val old = docs[key(sp, kind, cid)]
        docs[key(sp, kind, cid)] = Doc(cid, kind, data, false, System.currentTimeMillis().toDouble(),
            old?.author?.ifEmpty { null } ?: Settings.str("userID"), sp, true)
        publish(); persistSoon(); onLocalChange?.invoke()
    }

    @Synchronized
    fun delete(kind: String, cid: String) {
        val sp = Space.current
        val old = docs[key(sp, kind, cid)] ?: return
        docs[key(sp, kind, cid)] = old.copy(deleted = true, dirty = true, cts = System.currentTimeMillis().toDouble())
        publish(); persistSoon(); onLocalChange?.invoke()
    }

    @Synchronized
    fun restore(kind: String, cid: String) {
        val sp = Space.current
        val old = docs[key(sp, kind, cid)] ?: return
        docs[key(sp, kind, cid)] = old.copy(deleted = false, dirty = true, cts = System.currentTimeMillis().toDouble())
        publish(); persistSoon(); onLocalChange?.invoke()
    }

    /** Подсказки автоправил копилок («+30 ₽ в «Отпуск»»). */
    var onNote: ((String) -> Unit)? = null

    fun saveTx(t: Tx) {
        val old = synchronized(this) { docs[key(Space.current, "tx", t.id)] }
        put("tx", t.id, t.payload(old?.data ?: JsonObject(emptyMap())))
        if (old == null) {
            ru.koshelek.app.core.CompanionSound.tx()
            val notes = applyGoalRules(t)
            if (notes.isNotEmpty()) onNote?.invoke(notes.joinToString(" · "))
        }
    }

    /** Автоправила копилок: процент с дохода и «сдача» с трат — как на iPhone. */
    private fun applyGoalRules(t: Tx): List<String> {
        if (t.amount <= 0) return emptyList()
        val notes = mutableListOf<String>()
        val goals = _snap.value.goals.filter { it.target <= 0 || it.saved < it.target }
        for (g in goals) {
            var add = 0.0
            if (t.kind == TxKind.INC && t.cat != "debtback" && g.autoPercent > 0) {
                add = Math.round(t.amount * g.autoPercent / 100).toDouble()
                if (add > 0) notes += "${ru.koshelek.app.core.Fmt.rubU(add)} → «${g.name}»"
            } else if (t.kind == TxKind.EXP && t.cat != "savings" && t.cat != "loans" && g.roundUp > 0) {
                val step = g.roundUp.toDouble()
                add = Math.round(Math.ceil(t.amount / step) * step - t.amount).toDouble()
                if (add > 0) notes += "+${ru.koshelek.app.core.Fmt.rubU(add)} в «${g.name}»"
            }
            if (add > 0) saveGoal(g.copy(log = g.log + GoalEntry(t.date, add)))
        }
        return notes
    }
    fun saveAccount(a: Account) = put("acc", a.id, a.payload())
    fun saveDebt(d: Debt) = put("debt", d.id, d.payload())
    fun saveRec(r: Recurring) = put("rec", r.id, r.payload())
    fun saveGoal(g: Goal) = put("goal", g.id, g.payload())
    fun savePrefs(p: SpacePrefs) = put("prefs", "prefs", p.payload())

    // MARK: для синхронизации

    @Synchronized
    fun dirty(space: String): List<Doc> = docs.values.filter { it.space == space && it.dirty }

    @Synchronized
    fun markClean(sent: List<Doc>) {
        for (s in sent) {
            val k = key(s)
            val cur = docs[k] ?: continue
            if (cur.cts == s.cts) docs[k] = cur.copy(dirty = false)
        }
        persistSoon()
    }

    @Synchronized
    fun applyRemote(space: String, remote: List<JsonObject>) {
        for (o in remote) {
            val cid = o.str("cid"); val kind = o.str("kind")
            if (cid.isEmpty() || kind.isEmpty()) continue
            val k = key(space, kind, cid)
            val cts = o.num("cts")
            val cur = docs[k]
            if (cur != null && cur.dirty && cur.cts > cts) continue
            docs[k] = Doc(cid, kind, o["data"] as? JsonObject ?: JsonObject(emptyMap()), o.bool("deleted"), cts, o.str("author"), space, false)
        }
        publish(); persistSoon()
    }

    /** Записи, сделанные без входа, переезжают в личный бюджет. */
    @Synchronized
    fun adoptLocal(into: String) {
        val moving = docs.values.filter { it.space == Space.LOCAL }
        for (d in moving) {
            docs.remove(key(d))
            val nd = d.copy(space = into, dirty = true, cts = System.currentTimeMillis().toDouble())
            docs[key(nd)] = nd
        }
        persistSoon()
    }

    @Synchronized
    fun wipeSpace() {
        val sp = Space.current
        docs.values.filter { it.space == sp && !it.deleted && it.kind != "prefs" }.forEach {
            docs[key(it)] = it.copy(deleted = true, dirty = true, cts = System.currentTimeMillis().toDouble())
        }
        publish(); persistSoon(); onLocalChange?.invoke()
    }
}
