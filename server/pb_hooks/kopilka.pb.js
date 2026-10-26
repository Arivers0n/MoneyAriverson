/// <reference path="../pb_data/types.d.ts" />
// Маршруты синхронизации Копилки. Все требуют вход пользователя (коллекция users).

// Список пространств пользователя; личное создаётся автоматически.
routerAdd("POST", "/api/kp/spaces", (e) => {
    const u = require(`${__hooks}/kp_utils.js`)
    const uid = e.auth.id
    let list = u.userSpaces(e.app, uid)
    if (!list.some((r) => r.getBool("personal") && r.getString("owner") === uid)) {
        const col = e.app.findCollectionByNameOrId("kp_spaces")
        const rec = new Record(col)
        rec.set("name", "Личное")
        rec.set("owner", uid)
        rec.set("members", [uid])
        rec.set("personal", true)
        rec.set("code", u.newCode())
        e.app.save(rec)
        list = u.userSpaces(e.app, uid)
    }
    return e.json(200, { spaces: list.map((r) => u.spaceJSON(e.app, r)) })
}, $apis.requireAuth("users"))

// Создать общее пространство (например, «Семья»).
routerAdd("POST", "/api/kp/space/create", (e) => {
    const u = require(`${__hooks}/kp_utils.js`)
    const body = e.requestInfo().body || {}
    const name = String(body.name || "Семья").trim().slice(0, 80) || "Семья"
    const col = e.app.findCollectionByNameOrId("kp_spaces")
    const rec = new Record(col)
    rec.set("name", name)
    rec.set("owner", e.auth.id)
    rec.set("members", [e.auth.id])
    rec.set("personal", false)
    rec.set("code", u.newCode())
    e.app.save(rec)
    return e.json(200, { space: u.spaceJSON(e.app, rec) })
}, $apis.requireAuth("users"))

// Вступить по коду приглашения.
routerAdd("POST", "/api/kp/space/join", (e) => {
    const u = require(`${__hooks}/kp_utils.js`)
    const body = e.requestInfo().body || {}
    const code = String(body.code || "").trim().toUpperCase()
    if (code.length < 4) throw new BadRequestError("Введите код приглашения")
    let rec
    try { rec = e.app.findFirstRecordByFilter("kp_spaces", "code = {:c} && personal = false", { c: code }) }
    catch (_) { throw new NotFoundError("Код не найден. Проверьте его у владельца бюджета.") }
    const m = u.members(rec)
    if (m.indexOf(e.auth.id) < 0) { m.push(e.auth.id); rec.set("members", m); e.app.save(rec) }
    return e.json(200, { space: u.spaceJSON(e.app, rec) })
}, $apis.requireAuth("users"))

// Выйти из общего пространства (владелец передаёт права следующему участнику).
routerAdd("POST", "/api/kp/space/leave", (e) => {
    const u = require(`${__hooks}/kp_utils.js`)
    const body = e.requestInfo().body || {}
    const rec = u.requireSpace(e.app, String(body.space || ""), e.auth.id)
    if (rec.getBool("personal")) throw new BadRequestError("Из личного пространства выйти нельзя")
    const m = u.members(rec).filter((x) => x !== e.auth.id)
    rec.set("members", m)
    if (rec.getString("owner") === e.auth.id && m.length > 0) rec.set("owner", m[0])
    e.app.save(rec)
    return e.json(200, { ok: true })
}, $apis.requireAuth("users"))

// Переименовать, обновить код или удалить участника (только владелец).
routerAdd("POST", "/api/kp/space/update", (e) => {
    const u = require(`${__hooks}/kp_utils.js`)
    const body = e.requestInfo().body || {}
    const rec = u.requireSpace(e.app, String(body.space || ""), e.auth.id)
    if (rec.getString("owner") !== e.auth.id) throw new ForbiddenError("Это может только владелец")
    if (body.name) rec.set("name", String(body.name).trim().slice(0, 80))
    if (body.newCode) rec.set("code", u.newCode())
    if (body.kick && body.kick !== e.auth.id) rec.set("members", u.members(rec).filter((x) => x !== body.kick))
    e.app.save(rec)
    return e.json(200, { space: u.spaceJSON(e.app, rec) })
}, $apis.requireAuth("users"))

// Забрать изменения после курсора since (серверное время записи).
routerAdd("POST", "/api/kp/pull", (e) => {
    const u = require(`${__hooks}/kp_utils.js`)
    const body = e.requestInfo().body || {}
    const space = String(body.space || "")
    u.requireSpace(e.app, space, e.auth.id)
    const since = Number(body.since || 0)
    const limit = 500
    const recs = e.app.findRecordsByFilter("kp_docs", "space = {:s} && srv > {:since}", "srv", limit + 1, 0, { s: space, since: since })
    const more = recs.length > limit
    const out = []
    let cursor = since
    for (const r of recs.slice(0, limit)) {
        let data = {}
        try { data = JSON.parse(r.getString("data") || "{}") } catch (_) {}
        out.push({ cid: r.getString("cid"), kind: r.getString("kind"), data: data, deleted: r.getBool("deleted"),
                   cts: r.getFloat("cts"), srv: r.getFloat("srv"), author: r.getString("author") })
        cursor = r.getFloat("srv")
    }
    return e.json(200, { docs: out, cursor: cursor, more: more })
}, $apis.requireAuth("users"))

// Отправить изменения. Побеждает более свежая правка (по времени клиента).
routerAdd("POST", "/api/kp/push", (e) => {
    const u = require(`${__hooks}/kp_utils.js`)
    const body = e.requestInfo().body || {}
    const space = String(body.space || "")
    u.requireSpace(e.app, space, e.auth.id)
    const docs = Array.isArray(body.docs) ? body.docs.slice(0, 500) : []
    const col = e.app.findCollectionByNameOrId("kp_docs")
    const base = Date.now() * 1000
    let i = 0, saved = 0, skipped = 0
    for (const d of docs) {
        const cid = String(d.cid || "")
        if (!cid) continue
        let rec = null
        try { rec = e.app.findFirstRecordByFilter("kp_docs", "space = {:s} && cid = {:c}", { s: space, c: cid }) } catch (_) {}
        const cts = Number(d.cts || 0)
        if (rec && rec.getFloat("cts") > cts) { skipped++; continue }
        if (!rec) { rec = new Record(col); rec.set("space", space); rec.set("cid", cid) }
        rec.set("kind", String(d.kind || ""))
        rec.set("data", d.data || {})
        rec.set("deleted", !!d.deleted)
        rec.set("cts", cts)
        rec.set("srv", base + (i++))
        rec.set("author", d.author ? String(d.author) : e.auth.id)
        e.app.save(rec)
        saved++
    }
    return e.json(200, { saved: saved, skipped: skipped })
}, $apis.requireAuth("users"))

// Проверка, что сервер живой (для экрана настроек).
routerAdd("GET", "/api/kp/ping", (e) => {
    return e.json(200, { ok: true, app: "kopilka", version: 1 })
})

// Вход через Google, Яндекс и Apple: сервис возвращает пользователя сюда, а мы передаём код в приложение.
// Redirect URI во всех кабинетах: https://ВАШ-ДОМЕН/api/kp/oauth-callback
routerAdd("GET", "/api/kp/oauth-callback", (e) => {
    const q = e.request.url.rawQuery || ""
    return e.redirect(302, "koshelek://oauth?" + q)
})
// Apple присылает код POST-запросом (form_post).
routerAdd("POST", "/api/kp/oauth-callback", (e) => {
    const info = e.requestInfo()
    const b = info.body || {}
    const parts = []
    for (const k of ["code", "state", "error"]) {
        if (b[k]) parts.push(k + "=" + encodeURIComponent(String(b[k])))
    }
    return e.redirect(303, "koshelek://oauth?" + parts.join("&"))
})

// Провайдеры входа из /etc/kopilka.env: KP_GOOGLE_ID/KP_GOOGLE_SECRET, KP_YANDEX_ID/KP_YANDEX_SECRET, KP_APPLE_ID/KP_APPLE_SECRET.
onBootstrap((e) => {
    e.next()
    const list = []
    for (const [name, key] of [["google", "GOOGLE"], ["yandex", "YANDEX"], ["apple", "APPLE"]]) {
        const id = $os.getenv("KP_" + key + "_ID")
        const secret = $os.getenv("KP_" + key + "_SECRET")
        if (id && secret) list.push({ name: name, clientId: id, clientSecret: secret })
    }
    if (!list.length) return
    try {
        const c = e.app.findCollectionByNameOrId("users")
        unmarshal({ oauth2: { enabled: true, mappedFields: { name: "name", avatarURL: "" }, providers: list } }, c)
        e.app.save(c)
        console.log("Kopilka: вход через " + list.map((p) => p.name).join(", ") + " включён")
    } catch (err) {
        console.log("Kopilka: не удалось включить вход через сервисы:", err)
    }
})

// Ссылка-приглашение: https://ДОМЕН/api/kp/invite?code=XXXXXX — открывает приложение с уже указанным сервером.
routerAdd("GET", "/api/kp/invite", (e) => {
    const code = String(e.request.url.query().get("code") || "").replace(/[^A-Za-z0-9]/g, "").slice(0, 12)
    const proto = e.request.header.get("X-Forwarded-Proto") || "https"
    const server = proto + "://" + e.request.host
    const link = "koshelek://connect?server=" + encodeURIComponent(server) + (code ? "&code=" + code : "")
    const html = `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Копилка — приглашение</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#f2f3f5;color:#16201c;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
.c{background:#fff;border-radius:24px;padding:28px 24px;max-width:340px;margin:16px;text-align:center;box-shadow:0 8px 30px rgba(0,0,0,.08)}
a.b{display:block;background:#0E9F7E;color:#fff;text-decoration:none;font-weight:600;padding:15px;border-radius:14px;margin:18px 0 10px}
code{font-size:22px;letter-spacing:3px;font-weight:700}p{color:#5b6660;line-height:1.45}</style></head>
<body><div class="c"><h2>Копилка</h2><p>Вас пригласили в общий бюджет.</p>${code ? "<p>Код приглашения<br><code>" + code + "</code></p>" : ""}
<a class="b" href="${link}">Открыть в Копилке</a>
<p style="font-size:13px">Если ничего не происходит — сначала установите приложение Копилка, затем нажмите кнопку ещё раз. Сервер: ${e.request.host}</p></div>
<script>setTimeout(function(){location.href=${JSON.stringify(link)}},400)</script></body></html>`
    return e.html(200, html)
})

// ИИ для всех вошедших: ключ хранится только на сервере (/etc/kopilka.env), в приложение не попадает.
// KP_AI_KEY — ключ, KP_AI_BASE — адрес API (по умолчанию https://api.anthropic.com), KP_AI_MODEL — модель по умолчанию.
routerAdd("GET", "/api/kp/ai/status", (e) => {
    const on = !!$os.getenv("KP_AI_KEY")
    return e.json(200, { enabled: on, model: $os.getenv("KP_AI_MODEL") || "" })
}, $apis.requireAuth("users"))

routerAdd("POST", "/api/kp/ai", (e) => {
    const key = $os.getenv("KP_AI_KEY")
    if (!key) return e.json(503, { error: { message: "ИИ на сервере не настроен" } })
    // лимит: 400 запросов на человека в сутки
    const day = new Date().toISOString().slice(0, 10)
    const sk = "kpai:" + e.auth.id + ":" + day
    const n = (e.app.store().get(sk) || 0) + 1
    if (n > 400) return e.json(429, { error: { message: "Лимит ИИ на сегодня исчерпан" } })
    e.app.store().set(sk, n)

    const body = e.requestInfo().body || {}
    const model = $os.getenv("KP_AI_MODEL")
    if (model) body.model = model   // модель с сервера важнее — шлюз может поддерживать не все
    if (!body.model) body.model = "claude-haiku-5-5"
    if (!body.max_tokens || body.max_tokens > 4000) body.max_tokens = Math.min(body.max_tokens || 2048, 4000)

    let base = ($os.getenv("KP_AI_BASE") || "https://api.anthropic.com").replace(/\/+$/, "")
    if (!/\/v1\/messages$/.test(base)) base = /\/v1$/.test(base) ? base + "/messages" : base + "/v1/messages"
    let res
    try {
        res = $http.send({
            url: base,
            method: "POST",
            body: JSON.stringify(body),
            headers: {
                "content-type": "application/json",
                "x-api-key": key,
                "authorization": "Bearer " + key,
                "anthropic-version": "2023-06-01",
            },
            timeout: 120,
        })
    } catch (err) {
        return e.json(502, { error: { message: "Нет связи с ИИ: " + err } })
    }
    let out = res.json
    if (!out) { try { out = JSON.parse(toString(res.body)) } catch (_) { out = { error: { message: "Пустой ответ ИИ" } } } }
    return e.json(res.statusCode, out)
}, $apis.requireAuth("users"), $apis.bodyLimit(25 << 20))
