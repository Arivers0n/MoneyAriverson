#!/usr/bin/env bash
# Добавляет на уже работающий сервер маршруты и коллекции приложения «Вдвоём».
# Ничего не переустанавливает и не трогает файлы Кошелька и HabitFlow: только два новых файла.
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

say "Кладу два новых файла"
cat > "$DIR/pb_migrations/1762200000_vdvoem_init.js" <<'VDEOF'
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
cat > "$DIR/pb_hooks/vdvoem.pb.js" <<'VDEOF'
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

routerAdd("GET", "/api/vd/ping", (e) => {
    return e.json(200, { ok: true, app: "vdvoem", version: 1 })
})
VDEOF
chown -R kopilka:kopilka "$DIR/pb_hooks" "$DIR/pb_migrations" 2>/dev/null || true

rollback() {
  printf '\n\033[1;31mСервер не поднялся после добавления «Вдвоём». Откатываю.\033[0m\n'
  rm -f "$DIR/pb_hooks/vdvoem.pb.js" "$DIR/pb_migrations/1762200000_vdvoem_init.js"
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
