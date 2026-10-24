/// <reference path="../pb_data/types.d.ts" />
// Коллекции Копилки. Доступ к ним только через свои маршруты /api/kp/* (правила API = null).

migrate((app) => {
    const spaces = new Collection({
        type: "base",
        name: "kp_spaces",
        listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
        fields: [
            { type: "text", name: "name", max: 80 },
            { type: "text", name: "code", max: 20 },
            { type: "text", name: "owner", max: 40 },
            { type: "json", name: "members", maxSize: 200000 },
            { type: "bool", name: "personal" },
            { type: "autodate", name: "created", onCreate: true, onUpdate: false },
            { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
        ],
        indexes: [
            "CREATE INDEX idx_kp_spaces_code ON kp_spaces (code)",
            "CREATE INDEX idx_kp_spaces_owner ON kp_spaces (owner)",
        ],
    })
    app.save(spaces)

    const docs = new Collection({
        type: "base",
        name: "kp_docs",
        listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
        fields: [
            { type: "text", name: "space", required: true, max: 40 },
            { type: "text", name: "cid", required: true, max: 64 },
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
            "CREATE UNIQUE INDEX idx_kp_docs_space_cid ON kp_docs (space, cid)",
            "CREATE INDEX idx_kp_docs_space_srv ON kp_docs (space, srv)",
        ],
    })
    app.save(docs)
}, (app) => {
    for (const n of ["kp_docs", "kp_spaces"]) {
        try { app.delete(app.findCollectionByNameOrId(n)) } catch (_) {}
    }
})
