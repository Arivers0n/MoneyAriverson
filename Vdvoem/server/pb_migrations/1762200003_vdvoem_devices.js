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
