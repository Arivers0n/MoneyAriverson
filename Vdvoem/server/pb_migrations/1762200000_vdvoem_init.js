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
