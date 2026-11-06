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

module.exports = { vdCode, vdPairOf, vdPairJSON }
