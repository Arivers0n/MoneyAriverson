package ru.koshelek.app.data

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class ApiError(message: String, val status: Int = 0) : Exception(message)

data class Member(val id: String, val name: String, val email: String) {
    val display get() = name.ifEmpty { email.substringBefore("@") }
}
data class SpaceInfo(val id: String, val name: String, val code: String, val owner: String, val personal: Boolean, val members: List<Member>)

enum class SyncState { OFF, IDLE, SYNCING, ERROR }

object Server {
    const val DEFAULT = "https://2-27-25-140.sslip.io:8443"
    val json = Json { ignoreUnknownKeys = true }
    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS).readTimeout(130, TimeUnit.SECONDS).writeTimeout(60, TimeUnit.SECONDS).build()
    private val JSON_TYPE = "application/json".toMediaType()

    var url: String
        get() = Settings.str("server").ifEmpty { DEFAULT }
        set(v) = Settings.setStr("server", normalize(v))
    val token: String? get() = Settings.str("token").ifEmpty { null }
    val loggedIn get() = token != null
    val userId get() = Settings.str("userID")

    fun normalize(s: String): String {
        var u = s.trim()
        if (u.isEmpty()) return u
        if (!u.lowercase().startsWith("http")) u = "https://$u"
        return u.trimEnd('/')
    }

    /** Вызов API PocketBase. body == null → GET. */
    suspend fun call(path: String, body: JsonObject? = null, auth: Boolean = true, retry: Boolean = true, base: String = url): JsonObject =
        withContext(Dispatchers.IO) {
            val rb = Request.Builder().url(base + path)
            if (auth) token?.let { rb.header("Authorization", it) }
            if (body != null) rb.post(body.toString().toRequestBody(JSON_TYPE)) else rb.get()
            val resp = try { http.newCall(rb.build()).execute() } catch (e: Exception) { throw ApiError("Нет связи с сервером", 0) }
            resp.use { r ->
                val text = r.body?.string() ?: ""
                val obj = runCatching { json.parseToJsonElement(text).jsonObject }.getOrDefault(JsonObject(emptyMap()))
                if (r.code == 401 && auth && retry) {
                    if (refresh()) return@withContext call(path, body, auth, false, base)
                    logout()
                    throw ApiError("Сессия истекла — войдите снова", 401)
                }
                if (r.code !in 200..299) {
                    var msg = obj.str("message")
                    (obj["data"] as? JsonObject)?.forEach { (k, v) ->
                        val vo = v as? JsonObject ?: return@forEach
                        if (vo.str("code") == "validation_not_unique" && k == "email") msg = "Этот email уже зарегистрирован — войдите"
                        else if (vo.str("message").isNotEmpty()) msg = "$k: ${vo.str("message")}"
                    }
                    if (r.code == 400 && path.contains("auth-with-password")) msg = "Неверная почта или пароль"
                    throw ApiError(msg.ifEmpty { "Ошибка сервера (${r.code})" }, r.code)
                }
                obj
            }
        }

    private suspend fun refresh(): Boolean = runCatching {
        val o = call("/api/collections/users/auth-refresh", JsonObject(emptyMap()), auth = true, retry = false)
        o.str("token").takeIf { it.isNotEmpty() }?.let { Settings.setStr("token", it); true } ?: false
    }.getOrDefault(false)

    suspend fun ping(address: String): Boolean = runCatching {
        call("/api/kp/ping", auth = false, base = normalize(address)).str("app") == "kopilka"
    }.getOrDefault(false)

    // MARK: Вход

    suspend fun login(email: String, password: String) {
        val o = call("/api/collections/users/auth-with-password", buildJsonObject { put("identity", email); put("password", password) }, auth = false)
        finishLogin(o)
    }

    suspend fun register(name: String, email: String, password: String) {
        call("/api/collections/users/records", buildJsonObject {
            put("email", email); put("password", password); put("passwordConfirm", password); put("name", name); put("emailVisibility", true)
        }, auth = false)
        login(email, password)
    }

    data class OAuthProvider(val name: String, val authUrl: String, val verifier: String, val state: String)

    suspend fun oauthProviders(): List<OAuthProvider> = runCatching {
        val o = call("/api/collections/users/auth-methods", auth = false)
        val list = ((o["oauth2"] as? JsonObject)?.get("providers") as? JsonArray) ?: (o["authProviders"] as? JsonArray) ?: JsonArray(emptyList())
        list.mapNotNull { e ->
            val p = e as? JsonObject ?: return@mapNotNull null
            OAuthProvider(p.str("name"), p.str("authURL").ifEmpty { p.str("authUrl") }, p.str("codeVerifier"), p.str("state"))
        }
    }.getOrDefault(emptyList())

    val redirect get() = "$url/api/kp/oauth-callback"

    /** Адрес для открытия в браузере; верификатор запоминаем до возврата в приложение. */
    fun beginOAuth(p: OAuthProvider): String {
        Settings.setStr("oauth.provider", p.name); Settings.setStr("oauth.verifier", p.verifier); Settings.setStr("oauth.state", p.state)
        return p.authUrl + URLEncoder.encode(redirect, "UTF-8")
    }

    suspend fun completeOAuth(code: String, state: String) {
        if (state != Settings.str("oauth.state")) throw ApiError("Вход устарел — попробуйте ещё раз")
        val o = call("/api/collections/users/auth-with-oauth2", buildJsonObject {
            put("provider", Settings.str("oauth.provider")); put("code", code)
            put("codeVerifier", Settings.str("oauth.verifier")); put("redirectURL", redirect)
        }, auth = false)
        finishLogin(o)
    }

    private suspend fun finishLogin(o: JsonObject) {
        val t = o.str("token"); val rec = o["record"] as? JsonObject ?: throw ApiError("Сервер вернул неожиданный ответ")
        Settings.setStr("token", t)
        Settings.setStr("userID", rec.str("id"))
        val name = rec.str("name").ifEmpty { (o["meta"] as? JsonObject)?.str("name") ?: "" }
        Settings.setStr("userName", name); Settings.setStr("userEmail", rec.str("email"))
        SyncEngine.afterLogin()
    }

    fun logout() {
        Settings.setStr("token", null)
        Settings.setBool("serverAI", false)
        SyncEngine.state.value = SyncState.OFF
        SyncEngine.loginVersion.value++
    }

    // MARK: Пространства

    fun parseSpace(o: JsonObject) = SpaceInfo(o.str("id"), o.str("name"), o.str("code"), o.str("owner"), o.bool("personal"),
        (o["members"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let { m -> Member(m.str("id"), m.str("name"), m.str("email")) } } ?: emptyList())

    suspend fun loadSpaces(): List<SpaceInfo> {
        val o = call("/api/kp/spaces", JsonObject(emptyMap()))
        val list = (o["spaces"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(::parseSpace) } ?: emptyList()
        Settings.setStr("spaces", (o["spaces"] ?: JsonArray(emptyList())).toString())
        SyncEngine.spaces.value = list
        if (list.none { it.id == Space.current }) list.firstOrNull { it.personal }?.let { SyncEngine.switchTo(it.id) }
        return list
    }

    suspend fun createSpace(name: String) { call("/api/kp/space/create", buildJsonObject { put("name", name) }); loadSpaces() }
    suspend fun join(code: String) {
        val o = call("/api/kp/space/join", buildJsonObject { put("code", code) })
        loadSpaces()
        (o["space"] as? JsonObject)?.let { SyncEngine.switchTo(parseSpace(it).id) }
        SyncEngine.sync()
    }
    suspend fun leave(id: String) { call("/api/kp/space/leave", buildJsonObject { put("space", id) }); loadSpaces() }
    suspend fun updateSpace(id: String, name: String? = null, newCode: Boolean = false, kick: String? = null) {
        call("/api/kp/space/update", buildJsonObject {
            put("space", id); name?.let { put("name", it) }; if (newCode) put("newCode", true); kick?.let { put("kick", it) }
        }); loadSpaces()
    }

    suspend fun refreshAI() = runCatching {
        val o = call("/api/kp/ai/status")
        Settings.setBool("serverAI", o.bool("enabled"))
        SyncEngine.loginVersion.value++
    }
}

object SyncEngine {
    val state = MutableStateFlow(if (Server.loggedIn) SyncState.IDLE else SyncState.OFF)
    val spaces = MutableStateFlow<List<SpaceInfo>>(emptyList())
    val lastError = MutableStateFlow<String?>(null)
    val spaceVersion = MutableStateFlow(0)
    val loginVersion = MutableStateFlow(0)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pushJob: Job? = null
    @Volatile private var running = false

    fun init() {
        runCatching {
            val arr = Server.json.parseToJsonElement(Settings.str("spaces").ifEmpty { "[]" }).jsonArray
            spaces.value = arr.mapNotNull { (it as? JsonObject)?.let(Server::parseSpace) }
        }
        Store.onLocalChange = { schedulePush() }
    }

    val currentSpace: SpaceInfo? get() = spaces.value.firstOrNull { it.id == Space.current }

    fun memberName(id: String): String? =
        if (id.isEmpty() || id == Server.userId) null else currentSpace?.members?.firstOrNull { it.id == id }?.display

    fun switchTo(id: String) {
        Space.current = id
        Store.publish()
        spaceVersion.value++
    }

    suspend fun afterLogin() {
        state.value = SyncState.IDLE
        val list = Server.loadSpaces()
        list.firstOrNull { it.personal && it.owner == Server.userId }?.let { p ->
            Store.adoptLocal(p.id)
            switchTo(p.id)
        }
        Server.refreshAI()
        sync()
        joinPending()
        loginVersion.value++
    }

    suspend fun joinPending() {
        val code = Settings.str("pendingJoin")
        if (code.isEmpty() || !Server.loggedIn) return
        Settings.setStr("pendingJoin", null)
        if (spaces.value.any { it.code.equals(code, true) }) return
        runCatching { Server.join(code) }
    }

    fun schedulePush() {
        if (!Server.loggedIn) return
        pushJob?.cancel()
        pushJob = scope.launch { delay(1200); sync() }
    }

    suspend fun sync() {
        if (!Server.loggedIn || running) return
        val space = Space.current
        if (space == Space.LOCAL) return
        running = true
        state.value = SyncState.SYNCING
        try {
            push(space); pull(space)
            Settings.setDbl("lastSync", System.currentTimeMillis() / 1000.0)
            state.value = SyncState.IDLE
            lastError.value = null
            if (spaces.value.isEmpty() || (0..9).random() == 0) runCatching { Server.loadSpaces() }
            if (System.currentTimeMillis() / 1000.0 - Settings.dbl("serverAICheck") > 1800) {
                Server.refreshAI(); Settings.setDbl("serverAICheck", System.currentTimeMillis() / 1000.0)
            }
        } catch (e: Exception) {
            state.value = if (Server.loggedIn) SyncState.ERROR else SyncState.OFF
            lastError.value = e.message
        } finally { running = false }
    }

    private suspend fun push(space: String) {
        val dirty = Store.dirty(space)
        if (dirty.isEmpty()) return
        for (chunk in dirty.chunked(400)) {
            Server.call("/api/kp/push", buildJsonObject {
                put("space", space)
                put("docs", buildJsonArray {
                    chunk.forEach { d ->
                        add(buildJsonObject {
                            put("cid", d.cid); put("kind", d.kind); put("data", d.data); put("deleted", d.deleted)
                            put("cts", d.cts); put("author", d.author)
                        })
                    }
                })
            })
            Store.markClean(chunk)
        }
    }

    private suspend fun pull(space: String) {
        val key = "cursor:$space"
        var cursor = Settings.dbl(key)
        while (true) {
            val o = Server.call("/api/kp/pull", buildJsonObject { put("space", space); put("since", cursor) })
            val docs = (o["docs"] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
            if (docs.isNotEmpty()) Store.applyRemote(space, docs)
            cursor = o.num("cursor"); Settings.setDbl(key, cursor)
            if (!o.bool("more")) break
        }
    }
}
