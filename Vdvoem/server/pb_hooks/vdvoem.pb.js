/// <reference path="../pb_data/types.d.ts" />
// Маршруты «Вдвоём». Все требуют вход пользователя из коллекции vd_users.

// Моя пара (или null).
routerAdd("POST", "/api/vd/pair/me", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const rec = L.vdPairOf(e.app, e.auth.id)
    return e.json(200, { pair: rec ? L.vdPairJSON(e.app, rec) : null })
}, $apis.requireAuth("vd_users"))

// Создать пару и получить код приглашения.
routerAdd("POST", "/api/vd/pair/create", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    let rec = L.vdPairOf(e.app, e.auth.id)
    if (!rec) {
        const col = e.app.findCollectionByNameOrId("vd_pairs")
        rec = new Record(col)
        let code = L.vdCode()
        for (let i = 0; i < 20; i++) {
            let busy = false
            try { e.app.findFirstRecordByFilter("vd_pairs", "code = {:c}", { c: code }); busy = true } catch (_) {}
            if (!busy) break
            code = L.vdCode()
        }
        rec.set("code", code)
        rec.set("creator", e.auth.id)
        rec.set("members", [e.auth.id])
        e.app.save(rec)
    }
    return e.json(200, { pair: L.vdPairJSON(e.app, rec) })
}, $apis.requireAuth("vd_users"))

// Присоединиться по коду партнёра (в паре — ровно двое).
routerAdd("POST", "/api/vd/pair/join", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const body = e.requestInfo().body || {}
    const code = String(body.code || "").trim().toUpperCase()
    if (code.length < 4) throw new BadRequestError("Введите код партнёра")
    const mine = L.vdPairOf(e.app, e.auth.id)
    let rec
    try { rec = e.app.findFirstRecordByFilter("vd_pairs", "code = {:c}", { c: code }) }
    catch (_) { throw new NotFoundError("Код не найден. Проверьте его у партнёра.") }
    if (mine && mine.id === rec.id) return e.json(200, { pair: L.vdPairJSON(e.app, rec) })
    if (mine && mine.getStringSlice("members").length > 1) throw new BadRequestError("Вы уже состоите в паре")
    const m = rec.getStringSlice("members")
    if (m.length >= 2) throw new BadRequestError("В этой паре уже двое")
    // Если человек успел создать пустую пару, а теперь вступает в чужую — пустую удаляем.
    if (mine) { try { e.app.delete(mine) } catch (_) {} }
    m.push(e.auth.id)
    rec.set("members", m)
    e.app.save(rec)
    return e.json(200, { pair: L.vdPairJSON(e.app, rec) })
}, $apis.requireAuth("vd_users"))

// Выйти из пары (данные пары остаются у второго).
routerAdd("POST", "/api/vd/pair/leave", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const rec = L.vdPairOf(e.app, e.auth.id)
    if (!rec) return e.json(200, { ok: true })
    const m = rec.getStringSlice("members").filter((x) => x !== e.auth.id)
    if (m.length === 0) { e.app.delete(rec) }
    else {
        rec.set("members", m)
        if (rec.getString("creator") === e.auth.id) rec.set("creator", m[0])
        e.app.save(rec)
    }
    return e.json(200, { ok: true })
}, $apis.requireAuth("vd_users"))

// Забрать изменения после курсора srv (серверное время записи).
routerAdd("POST", "/api/vd/pull", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const pair = L.vdPairOf(e.app, e.auth.id)
    if (!pair) throw new BadRequestError("Сначала соединитесь с партнёром")
    const body = e.requestInfo().body || {}
    const since = Number(body.since || 0)
    const limit = 500
    const recs = e.app.findRecordsByFilter("vd_docs", "pair = {:p} && srv > {:s}", "srv", limit + 1, 0, { p: pair.id, s: since })
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
}, $apis.requireAuth("vd_users"))

// Отправить изменения. Побеждает более новая правка (cts в миллисекундах).
routerAdd("POST", "/api/vd/push", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const pair = L.vdPairOf(e.app, e.auth.id)
    if (!pair) throw new BadRequestError("Сначала соединитесь с партнёром")
    const body = e.requestInfo().body || {}
    const docs = Array.isArray(body.docs) ? body.docs.slice(0, 300) : []
    const col = e.app.findCollectionByNameOrId("vd_docs")
    const base = Date.now() * 1000
    let i = 0, saved = 0, skipped = 0
    for (const d of docs) {
        const cid = String(d.cid || "")
        if (!cid) continue
        let rec = null
        try { rec = e.app.findFirstRecordByFilter("vd_docs", "pair = {:p} && cid = {:c}", { p: pair.id, c: cid }) } catch (_) {}
        const cts = Number(d.cts || 0)
        if (rec && rec.getFloat("cts") >= cts) { skipped++; continue }
        if (!rec) { rec = new Record(col); rec.set("pair", pair.id); rec.set("cid", cid) }
        rec.set("kind", String(d.kind || ""))
        rec.set("data", d.data || {})
        rec.set("deleted", !!d.deleted)
        rec.set("cts", cts)
        rec.set("srv", base + (i++))
        rec.set("author", e.auth.id)
        e.app.save(rec)
        saved++
    }
    return e.json(200, { saved: saved, skipped: skipped })
}, $apis.requireAuth("vd_users"))

// Загрузка фото в пару: multipart, поле "file". Ответ: { id, file }.
routerAdd("POST", "/api/vd/media", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const pair = L.vdPairOf(e.app, e.auth.id)
    if (!pair) throw new BadRequestError("Сначала соединитесь с партнёром")
    const files = e.findUploadedFiles("file")
    if (!files || files.length === 0) throw new BadRequestError("Нет файла")
    const col = e.app.findCollectionByNameOrId("vd_media")
    const rec = new Record(col)
    rec.set("pair", pair.id)
    rec.set("author", e.auth.id)
    rec.set("file", files[0])
    e.app.save(rec)
    return e.json(200, { id: rec.id, file: rec.getString("file") })
}, $apis.requireAuth("vd_users"))

routerAdd("GET", "/api/vd/ping", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    return e.json(200, { ok: true, app: "vdvoem", version: 2 })
})


// ---------- Аккаунт: вход через Яндекс и почту ----------

// Яндекс возвращает пользователя сюда, а мы передаём код обратно в приложение.
// Redirect URI в кабинете Яндекса: https://ВАШ-ДОМЕН/api/vd/oauth-callback
routerAdd("GET", "/api/vd/oauth-callback", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const q = e.request.url.rawQuery || ""
    return e.redirect(302, "vdvoem://oauth?" + q)
})

// Пароль устройства для аккаунта, созданного через Яндекс: по нему приложение тихо перезаходит, когда токен устарел.
routerAdd("POST", "/api/vd/account/setpass", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const body = e.requestInfo().body || {}
    const pw = String(body.password || "")
    if (pw.length < 8) throw new BadRequestError("Слишком короткий пароль")
    try {
        const rec = e.app.findRecordById("vd_users", e.auth.id)
        if (!rec.getString("email")) rec.setEmail(rec.id + "@oauth.vdvoem.app")
        rec.setPassword(pw)
        e.app.save(rec)
        return e.json(200, { email: rec.getString("email"), name: rec.getString("name") })
    } catch (err) {
        console.log("Vdvoem: setpass не удался:", err)
        throw new BadRequestError("Не удалось задать пароль устройства")
    }
}, $apis.requireAuth("vd_users"))

// Перенос пары с «безымянного» аккаунта телефона на настоящий (при входе). Старый аккаунт удаляется, если опустел.
routerAdd("POST", "/api/vd/account/adopt", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const b = e.requestInfo().body || {}
    const email = String(b.email || "").toLowerCase()
    const pw = String(b.password || "")
    if (!email.endsWith("@vdvoem.app")) return e.json(200, { adopted: false })
    let old
    try { old = e.app.findAuthRecordByEmail("vd_users", email) } catch (_) { return e.json(200, { adopted: false }) }
    if (old.id === e.auth.id || !old.validatePassword(pw)) return e.json(200, { adopted: false })
    let adopted = false
    const op = L.vdPairOf(e.app, old.id)
    if (op && !L.vdPairOf(e.app, e.auth.id)) {
        op.set("members", op.getStringSlice("members").map((x) => (x === old.id ? e.auth.id : x)))
        if (op.getString("creator") === old.id) op.set("creator", e.auth.id)
        e.app.save(op)
        const docs = e.app.findRecordsByFilter("vd_docs", "pair = {:p} && author = {:a}", "", 0, 0, { p: op.id, a: old.id })
        for (const d of docs) { d.set("author", e.auth.id); e.app.save(d) }
        adopted = true
    }
    if (!L.vdPairOf(e.app, old.id)) { try { e.app.delete(old) } catch (_) {} }
    return e.json(200, { adopted: adopted })
}, $apis.requireAuth("vd_users"))

// Вход через Яндекс в коллекции vd_users. Ключи в /etc/kopilka.env: VD_YANDEX_ID / VD_YANDEX_SECRET (если их нет — берутся KP_YANDEX_* от «Копилки»).
onBootstrap((e) => {
    e.next()
    const id = $os.getenv("VD_YANDEX_ID") || $os.getenv("KP_YANDEX_ID")
    const secret = $os.getenv("VD_YANDEX_SECRET") || $os.getenv("KP_YANDEX_SECRET")
    if (!id || !secret) return
    try {
        const c = e.app.findCollectionByNameOrId("vd_users")
        unmarshal({ oauth2: { enabled: true, mappedFields: { name: "name", avatarURL: "" }, providers: [{ name: "yandex", clientId: id, clientSecret: secret }] } }, c)
        e.app.save(c)
        console.log("Vdvoem: вход через Яндекс включён")
    } catch (err) {
        console.log("Vdvoem: не удалось включить вход через Яндекс:", err)
    }
})
