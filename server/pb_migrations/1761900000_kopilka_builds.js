/// <reference path="../pb_data/types.d.ts" />
// Сборки Android-приложения: GitHub Actions загружает сюда APK, приложение само проверяет обновления.
// Читать может кто угодно (это просто файл приложения), загружать — только сборщик с ключом.

migrate((app) => {
    const c = new Collection({
        type: "base",
        name: "kp_builds",
        listRule: "", viewRule: "",
        createRule: '@request.headers.x_kp_upload = "d0e5ad0614dc1beb6893c73086e152fc8d57f80c"',
        updateRule: null, deleteRule: null,
        fields: [
            { type: "number", name: "version", required: true, onlyInt: true },
            { type: "text", name: "name", max: 40 },
            { type: "text", name: "notes", max: 500 },
            { type: "file", name: "apk", maxSelect: 1, maxSize: 157286400 },
            { type: "autodate", name: "created", onCreate: true, onUpdate: false },
        ],
        indexes: ["CREATE INDEX idx_kp_builds_version ON kp_builds (version)"],
    })
    app.save(c)
}, (app) => {
    try { app.delete(app.findCollectionByNameOrId("kp_builds")) } catch (_) {}
})
