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
