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
