// Общие функции для маршрутов Копилки. Подключаются через require() внутри каждого обработчика.

function members(rec) {
    try {
        const raw = rec.getString("members")
        const arr = JSON.parse(raw || "[]")
        return Array.isArray(arr) ? arr : []
    } catch (_) { return [] }
}

function isMember(rec, uid) {
    return members(rec).indexOf(uid) >= 0
}

function spaceJSON(app, rec) {
    const ids = members(rec)
    const people = []
    for (const id of ids) {
        try {
            const u = app.findRecordById("users", id)
            people.push({ id: id, name: u.getString("name"), email: u.getString("email") })
        } catch (_) {
            people.push({ id: id, name: "", email: "" })
        }
    }
    return {
        id: rec.id,
        name: rec.getString("name"),
        code: rec.getBool("personal") ? "" : rec.getString("code"),
        owner: rec.getString("owner"),
        personal: rec.getBool("personal"),
        members: people,
    }
}

function userSpaces(app, uid) {
    const found = app.findRecordsByFilter("kp_spaces", "members ~ {:q}", "created", 200, 0, { q: '"' + uid + '"' })
    return found.filter((r) => isMember(r, uid))
}

function requireSpace(app, spaceId, uid) {
    let rec
    try { rec = app.findRecordById("kp_spaces", spaceId) } catch (_) { throw new NotFoundError("Пространство не найдено") }
    if (!isMember(rec, uid)) throw new ForbiddenError("Нет доступа к этому пространству")
    return rec
}

function newCode() {
    return $security.randomStringWithAlphabet(6, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
}

module.exports = { members, isMember, spaceJSON, userSpaces, requireSpace, newCode }
