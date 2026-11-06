#!/usr/bin/env bash
# Добавляет на уже работающий сервер маршруты и коллекции приложения «Вдвоём».
# Ничего не переустанавливает и не трогает файлы Кошелька и HabitFlow: только файлы vdvoem*.
# Можно запускать повторно — это безопасно.
# Запуск:  sudo bash /root/install-vd.sh
set -euo pipefail

DIR="/opt/kopilka"
say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запустите через sudo"
[ -x "$DIR/pocketbase" ] || die "не найден $DIR/pocketbase — сначала должен быть установлен сервер Кошелька"

say "Делаю копию базы на всякий случай"
mkdir -p "$DIR/backups"
BK="$DIR/backups/before-vdvoem-$(date +%F-%H%M).db"
sqlite3 "$DIR/pb_data/data.db" ".backup '$BK'"
echo "Копия: $BK"

NEW=""
put() { # put <путь>  (содержимое со stdin)
  [ -e "$1" ] || NEW="$NEW $1"
  cat > "$1"
}

say "Кладу файлы «Вдвоём»"

put "$DIR/pb_migrations/1762200000_vdvoem_init.js" <<'VDEOF'
/// <reference path="../pb_data/types.d.ts" />
// Коллекции приложения «Вдвоём». Свои аккаунты (vd_users) — с Кошельком и HabitFlow ничего не пересекается.
// Запись данных — только через /api/vd/push; чтение и подписка (real-time) — только участникам своей пары.

migrate((app) => {
    const users = new Collection({
        type: "auth",
        name: "vd_users",
        listRule: "id = @request.auth.id",
        viewRule: "id = @request.auth.id",
        createRule: "",
        updateRule: "id = @request.auth.id",
        deleteRule: "id = @request.auth.id",
        passwordAuth: { enabled: true, identityFields: ["email"] },
        fields: [
            { type: "text", name: "name", max: 40 },
        ],
    })
    app.save(users)

    const pairs = new Collection({
        type: "base",
        name: "vd_pairs",
        listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
        fields: [
            { type: "text", name: "code", required: true, max: 12 },
            { type: "text", name: "creator", max: 40 },
            { type: "relation", name: "members", collectionId: users.id, maxSelect: 2, cascadeDelete: false },
            { type: "autodate", name: "created", onCreate: true, onUpdate: false },
        ],
        indexes: ["CREATE UNIQUE INDEX idx_vd_pairs_code ON vd_pairs (code)"],
    })
    app.save(pairs)

    const docs = new Collection({
        type: "base",
        name: "vd_docs",
        listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
        fields: [
            { type: "relation", name: "pair", collectionId: pairs.id, maxSelect: 1, required: true, cascadeDelete: true },
            { type: "text", name: "cid", required: true, max: 80 },
            { type: "text", name: "kind", max: 30 },
            { type: "json", name: "data", maxSize: 1000000 },
            { type: "bool", name: "deleted" },
            { type: "number", name: "cts" },
            { type: "number", name: "srv" },
            { type: "text", name: "author", max: 40 },
            { type: "autodate", name: "created", onCreate: true, onUpdate: false },
            { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
        ],
        indexes: [
            "CREATE UNIQUE INDEX idx_vd_docs_pair_cid ON vd_docs (pair, cid)",
            "CREATE INDEX idx_vd_docs_pair_srv ON vd_docs (pair, srv)",
        ],
    })
    app.save(docs)

    // Права на чтение/подписку включаем отдельно: если синтаксис правил не подойдёт — коллекции всё равно
    // создадутся (доступ закрыт), а приложение будет работать через опрос /api/vd/pull.
    try {
        const d = app.findCollectionByNameOrId("vd_docs")
        d.listRule = "pair.members.id ?= @request.auth.id"
        d.viewRule = "pair.members.id ?= @request.auth.id"
        app.save(d)
    } catch (_) {}
}, (app) => {
    for (const n of ["vd_docs", "vd_pairs", "vd_users"]) {
        try { app.delete(app.findCollectionByNameOrId(n)) } catch (_) {}
    }
})
VDEOF

put "$DIR/pb_migrations/1762200001_vdvoem_media.js" <<'VDEOF'
/// <reference path="../pb_data/types.d.ts" />
// Фото «Вдвоём»: файлы хранятся в vd_media. Загрузка — только через /api/vd/media (проверяется пара).
// Файлы отдаются по адресу /api/files/vd_media/<id>/<имя> — имя случайное и не угадывается.

migrate((app) => {
    const pairs = app.findCollectionByNameOrId("vd_pairs")
    const media = new Collection({
        type: "base",
        name: "vd_media",
        listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
        fields: [
            { type: "relation", name: "pair", collectionId: pairs.id, maxSelect: 1, required: true, cascadeDelete: true },
            { type: "text", name: "author", max: 40 },
            {
                type: "file", name: "file", maxSelect: 1, maxSize: 15 * 1024 * 1024,
                mimeTypes: ["image/jpeg", "image/png", "image/heic", "image/webp"],
                thumbs: ["480x0", "1080x0"], protected: false,
            },
            { type: "autodate", name: "created", onCreate: true, onUpdate: false },
        ],
    })
    app.save(media)
}, (app) => {
    try { app.delete(app.findCollectionByNameOrId("vd_media")) } catch (_) {}
})
VDEOF

put "$DIR/pb_migrations/1762200002_vdvoem_media_av.js" <<'VDEOF'
/// <reference path="../pb_data/types.d.ts" />
// Голосовые и «кружки» в чате: разрешаем звук и видео в vd_media.

migrate((app) => {
    const col = app.findCollectionByNameOrId("vd_media")
    const f = col.fields.getByName("file")
    f.maxSize = 60 * 1024 * 1024
    f.mimeTypes = [
        "image/jpeg", "image/png", "image/heic", "image/webp",
        "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac", "audio/mpeg", "audio/wav", "audio/x-wav",
        "video/mp4", "video/quicktime", "video/x-m4v",
    ]
    app.save(col)
}, (app) => {})
VDEOF

put "$DIR/pb_migrations/1762200003_vdvoem_devices.js" <<'VDEOF'
/// <reference path="../pb_data/types.d.ts" />
// Устройства для пуш-уведомлений: токен Apple на каждого пользователя.

migrate((app) => {
    const users = app.findCollectionByNameOrId("vd_users")
    const col = new Collection({
        type: "base",
        name: "vd_devices",
        listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
        fields: [
            { type: "relation", name: "user", collectionId: users.id, maxSelect: 1, required: true, cascadeDelete: true },
            { type: "text", name: "token", required: true, max: 200 },
            { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
        ],
        indexes: ["CREATE UNIQUE INDEX idx_vd_devices_token ON vd_devices (token)"],
    })
    app.save(col)
}, (app) => {
    try { app.delete(app.findCollectionByNameOrId("vd_devices")) } catch (_) {}
})
VDEOF

put "$DIR/pb_hooks/vdlib.js" <<'VDEOF'
/// Помощники «Вдвоём». Обычный модуль (не .pb.js): подключается из обработчиков через require.

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

// ---------- Пуш-уведомления ----------
// Отправку делает маленькая служба vd-push на этом же сервере (127.0.0.1:8788): подпись для Apple (ES256) в JS-хуках PocketBase недоступна.

function vdSend(app, userId, title, body, thread, data) {
    let recs = []
    try { recs = app.findRecordsByFilter("vd_devices", "user = {:u}", "", 0, 0, { u: userId }) } catch (_) { return }
    if (!recs.length) return
    try {
        const res = $http.send({
            url: "http://127.0.0.1:8788/send",
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ tokens: recs.map((r) => r.getString("token")), title: title, body: body, thread: thread || "", data: data || {} }),
            timeout: 6,
        })
        const dead = (res.json && res.json.dead) || []
        for (const t of dead) {
            for (const r of recs) if (r.getString("token") === t) { try { app.delete(r) } catch (_) {} }
        }
    } catch (err) {
        console.log("Vdvoem: пуш не отправлен:", err)
    }
}

function vdTrim(s, n) {
    s = String(s || "").replace(/\s+/g, " ").trim()
    return s.length > n ? s.slice(0, n - 1) + "…" : s
}

// Что показать партнёру о новых документах. fresh = [{kind, data, isNew}], authorId — кто сохранил.
function vdNotify(app, pair, authorId, fresh) {
    const members = pair.getStringSlice("members")
    const to = members.find((m) => m !== authorId)
    if (!to) return
    let name = "Партнёр"
    try { name = app.findRecordById("vd_users", authorId).getString("name") || name } catch (_) {}
    const authorIsCreator = pair.getString("creator") === authorId
    const out = []

    const msgs = fresh.filter((d) => d.kind === "messages" && d.isNew)
    if (msgs.length) {
        const last = msgs[msgs.length - 1].data || {}
        let text = last.kind === "voice" ? "🎤 Голосовое сообщение" : vdTrim(last.text, 120)
        if (msgs.length > 1) text = msgs.length + " новых сообщения · " + text
        out.push([name, text, "chat", { open: "chat" }])
    }
    const games = fresh.filter((d) => d.kind === "matches")
    if (games.length) {
        const g = games[games.length - 1].data || {}
        const names = { ttt: "Крестики-нолики", four: "4 в ряд", reversi: "Реверси", checkers: "Шашки", dots: "Точки", battleship: "Морской бой", durak: "Дурак", memory: "Память", rps: "Камень-ножницы-бумага", hangman: "Виселица" }
        const t = names[g.kind] || "Игра"
        if (g.state === "won") out.push([t, name + " завершил(а) партию — загляните узнать, кто победил", "game", { open: "games" }])
        else if (g.state === "draw") out.push([t, "Партия закончилась вничью", "game", { open: "games" }])
        else {
            // данные хранятся глазами создателя пары: «моё» = создатель
            const recipientIsCreator = !authorIsCreator
            const myTurn = recipientIsCreator ? g.turn === "me" : g.turn === "partner"
            if (myTurn) out.push([t, "Ваш ход — " + name + " сходил(а)", "game", { open: "games" }])
        }
    }
    const sig = fresh.filter((d) => d.kind === "signals" && d.isNew)
    if (sig.length) {
        const titles = { miss: "Скучаю по тебе 💗", hug: "Обнимаю 🤗", kiss: "Целую 😘", think: "Думаю о тебе 💭", hi: "Привет! 👋", love: "Люблю 😍" }
        const k = (sig[sig.length - 1].data || {}).kind
        out.push([name, titles[k] || "Отправил(а) вам сигнал", "signal", { open: "signal" }])
    }
    const simple = [
        ["answers", "Ответ на вопрос дня", "ответил(а) на вопрос дня", "question"],
        ["capsules", "Капсула времени", "оставил(а) вам капсулу времени", "capsule"],
        ["polls", "Новое голосование", "предлагает выбрать вместе", "vote"],
        ["photos", "Новое фото", "добавил(а) фото в вашу ленту", "memories"],
        ["tasks", "Новая задача", "добавил(а) задачу для вас", "tasks"],
        ["wishes", "Новое желание", "добавил(а) желание в список", "wishes"],
        ["events", "Новое событие", "добавил(а) событие в календарь", "calendar"],
        ["statuses", "Статус", "обновил(а) статус", "today"],
    ]
    for (const s of simple) {
        const f = fresh.filter((d) => d.kind === s[0] && d.isNew)
        if (f.length) out.push([s[1], name + " " + s[2], s[0], { open: s[3] }])
    }
    for (const n of out.slice(0, 4)) vdSend(app, to, n[0], n[1], n[2], n[3])
}

module.exports = { vdCode, vdPairOf, vdPairJSON, vdSend, vdNotify }
VDEOF

put "$DIR/pb_hooks/vdvoem.pb.js" <<'VDEOF'
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
    const fresh = []
    for (const d of docs) {
        const cid = String(d.cid || "")
        if (!cid) continue
        let rec = null
        try { rec = e.app.findFirstRecordByFilter("vd_docs", "pair = {:p} && cid = {:c}", { p: pair.id, c: cid }) } catch (_) {}
        const cts = Number(d.cts || 0)
        if (rec && rec.getFloat("cts") >= cts) { skipped++; continue }
        const isNew = !rec
        if (!rec) { rec = new Record(col); rec.set("pair", pair.id); rec.set("cid", cid) }
        rec.set("kind", String(d.kind || ""))
        rec.set("data", d.data || {})
        rec.set("deleted", !!d.deleted)
        rec.set("cts", cts)
        rec.set("srv", base + (i++))
        rec.set("author", e.auth.id)
        e.app.save(rec)
        saved++
        if (!d.deleted && Date.now() - cts < 180000) fresh.push({ kind: String(d.kind || ""), data: d.data || {}, isNew: isNew })
    }
    // Уведомление партнёру: сбой отправки не должен ломать синхронизацию
    try { if (fresh.length) L.vdNotify(e.app, pair, e.auth.id, fresh) } catch (err) { console.log("Vdvoem: уведомления:", err) }
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

// Токен для пуш-уведомлений от Apple: один токен — один пользователь (при смене аккаунта переезжает).
routerAdd("POST", "/api/vd/device", (e) => {
    const L = require(`${__hooks}/vdlib.js`)
    const token = String((e.requestInfo().body || {}).token || "").trim()
    if (!/^[0-9a-fA-F]{32,200}$/.test(token)) throw new BadRequestError("Неверный токен")
    let rec = null
    try { rec = e.app.findFirstRecordByFilter("vd_devices", "token = {:t}", { t: token }) } catch (_) {}
    if (!rec) { rec = new Record(e.app.findCollectionByNameOrId("vd_devices")); rec.set("token", token) }
    rec.set("user", e.auth.id)
    e.app.save(rec)
    return e.json(200, { ok: true })
}, $apis.requireAuth("vd_users"))

routerAdd("POST", "/api/vd/device/remove", (e) => {
    const token = String((e.requestInfo().body || {}).token || "")
    try {
        const rec = e.app.findFirstRecordByFilter("vd_devices", "token = {:t} && user = {:u}", { t: token, u: e.auth.id })
        e.app.delete(rec)
    } catch (_) {}
    return e.json(200, { ok: true })
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
VDEOF

chown -R kopilka:kopilka "$DIR/pb_hooks" "$DIR/pb_migrations" 2>/dev/null || true

rollback() {
  printf '\n\033[1;31mСервер не поднялся после добавления «Вдвоём». Откатываю.\033[0m\n'
  for f in $NEW; do rm -f "$f"; done
  systemctl stop kopilka || true
  cp "$BK" "$DIR/pb_data/data.db"
  systemctl start kopilka || true
  die "изменения отменены, Кошелёк работает как раньше. Пришлите вывод: journalctl -u kopilka -n 50"
}

say "Перезапускаю сервер"
systemctl restart kopilka
ok=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 2
  if curl -fsS http://127.0.0.1:8090/api/kp/ping >/dev/null 2>&1 && curl -fsS http://127.0.0.1:8090/api/vd/ping >/dev/null 2>&1; then ok=1; break; fi
done
[ "$ok" = 1 ] || rollback

say "Готово"
echo "Кошелёк и «Вдвоём» отвечают. Можно открывать приложение «Вдвоём»."
