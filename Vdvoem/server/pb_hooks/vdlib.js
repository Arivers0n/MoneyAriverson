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
