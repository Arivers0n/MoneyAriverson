import Foundation

/// Снимок данных для виджетов. Пишется приложением, читается расширением.
struct VDSnapshot: Codable {
    var updated = Date()
    var myName = "Я"
    var partnerName = "Партнёр"
    var myHex = "4C9AF0"
    var partnerHex = "D870A8"

    // Статус партнёра (на 24 часа)
    var statusTitle = ""
    var statusSymbol = ""
    var statusHex = ""
    var statusNote = ""
    var statusStarted: Date?
    var statusExpires: Date?

    // Настроение
    var partnerMoodEmoji = ""
    var partnerMoodTitle = ""
    var myMoodEmoji = ""

    // Расстояние
    var distanceText = ""

    // Вместе
    var daysTogether = 0

    // Фото
    var hasPhoto = false
    var photoCaption = ""

    static func sample() -> VDSnapshot {
        var s = VDSnapshot()
        s.myName = "Аня"
        s.partnerName = "Андрей"
        s.statusTitle = "Готовлю"
        s.statusSymbol = "frying.pan.fill"
        s.statusHex = "E8590C"
        s.statusNote = "Ужин для нас"
        s.statusStarted = Date().addingTimeInterval(-1800)
        s.statusExpires = Date().addingTimeInterval(20000)
        s.partnerMoodEmoji = "😄"
        s.partnerMoodTitle = "Отлично"
        s.myMoodEmoji = "🙂"
        s.distanceText = "12 км"
        s.daysTogether = 412
        return s
    }
}
