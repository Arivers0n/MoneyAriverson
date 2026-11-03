/// <reference path="../pb_data/types.d.ts" />
// Маршруты «Вдвоём». Все требуют вход пользователя из коллекции vd_users.

const VD_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

function vdCode() {
    let s = ""
    for (let i = 0; i < 6; i++) s += VD_ALPHABET.charAt(Math.floor(Math.random() * VD_ALPHABET.length))
    return s
}

function vdPairOf(app, uid) {
    try { return app.findFirstRecordByFilter("vd_pairs", "members.id ?= {:u}", { u: uid }) }
    catch (_) { return null }
}

function vdPairJSON(app, rec) {
    const ids = rec.getStringSlice("members")
    const members = ids.map((id) => {
        let name = ""
        try { name = app.findRecordById("vd_users", id).getString("name") } catch (_) {}
        return { id: id, name: name }
    })
    return { id: rec.id, code: rec.getString("code"), creator: rec.getString("creator"), members: members }
}

// Моя пара (или null).
routerAdd("POST", "/api/vd/pair/me", (e) => {
    const rec = vdPairOf(e.app, e.auth.id)
    return e.json(200, { pair: rec ? vdPairJSON(e.app, rec) : null })
}, $apis.requireAuth("vd_users"))

// Создать пару и получить код приглашения.
routerAdd("POST", "/api/vd/pair/create", (e) => {
    let rec = vdPairOf(e.app, e.auth.id)
    if (!rec) {
        const col = e.app.findCollectionByNameOrId("vd_pairs")
        rec = new Record(col)
        let code = vdCode()
        for (let i = 0; i < 20; i++) {
            let busy = false
            try { e.app.findFirstRecordByFilter("vd_pairs", "code = {:c}", { c: code }); busy = true } catch (_) {}
            if (!busy) break
            code = vdCode()
        }
        rec.set("code", code)
        rec.set("creator", e.auth.id)
        rec.set("members", [e.auth.id])
        e.app.save(rec)
    }
    return e.json(200, { pair: vdPairJSON(e.app, rec) })
}, $apis.requireAuth("vd_users"))

// Присоединиться по коду партнёра (в паре — ровно двое).
routerAdd("POST", "/api/vd/pair/join", (e) => {
    const body = e.requestInfo().body || {}
    const code = String(body.code || "").trim().toUpperCase()
    if (code.length < 4) throw new BadRequestError("Введите код партнёра")
    const mine = vdPairOf(e.app, e.auth.id)
    let rec
    try { rec = e.app.findFirstRecordByFilter("vd_pairs", "code = {:c}", { c: code }) }
    catch (_) { throw new NotFoundError("Код не найден. Проверьте его у партнёра.") }
    if (mine && mine.id === rec.id) return e.json(200, { pair: vdPairJSON(e.app, rec) })
    if (mine && mine.getStringSlice("members").length > 1) throw new BadRequestError("Вы уже состоите в паре")
    const m = rec.getStringSlice("members")
    if (m.length >= 2) throw new BadRequestError("В этой паре уже двое")
    // Если человек успел создать пустую пару, а теперь вступает в чужую — пустую удаляем.
    if (mine) { try { e.app.delete(mine) } catch (_) {} }
    m.push(e.auth.id)
    rec.set("members", m)
    e.app.save(rec)
    return e.json(200, { pair: vdPairJSON(e.app, rec) })
}, $apis.requireAuth("vd_users"))

// Выйти из пары (данные пары остаются у второго).
routerAdd("POST", "/api/vd/pair/leave", (e) => {
    const rec = vdPairOf(e.app, e.auth.id)
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
    const pair = vdPairOf(e.app, e.auth.id)
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
    const pair = vdPairOf(e.app, e.auth.id)
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
    const pair = vdPairOf(e.app, e.auth.id)
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
    return e.json(200, { ok: true, app: "vdvoem", version: 2 })
})
