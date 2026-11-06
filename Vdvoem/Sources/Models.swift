import SwiftUI

// MARK: - Базовые перечисления

enum Who: String, Codable, CaseIterable { case me, partner }
enum Scope: String, CaseIterable { case we, me, partner }

enum ThemeMode: String, Codable, CaseIterable {
    case system, dark, light
    var title: String {
        switch self {
        case .system: return "Авто"
        case .dark: return "Тёмная"
        case .light: return "Светлая"
        }
    }
}

enum DesignStyle: String, Codable, CaseIterable {
    case rounded, standard, serif, mono
    var title: String {
        switch self {
        case .rounded: return "Мягкий"
        case .standard: return "Строгий"
        case .serif: return "Книжный"
        case .mono: return "Техно"
        }
    }
    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .standard: return .default
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

enum Module: String, Codable, CaseIterable, Identifiable {
    case tasks, calendar, wishes, lists
    case chat, plans, files, cards, question, compat, games, capsule, vote, radar, notes
    case days, mood, dates
    case today, memories, places
    case signal, pet
    case movies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: return "Задачи"
        case .calendar: return "Календарь"
        case .wishes: return "Хотелки"
        case .lists: return "Списки"
        case .chat: return "Чат"
        case .plans: return "Планы"
        case .files: return "Файлы"
        case .cards: return "Карты"
        case .question: return "Вопрос дня"
        case .compat: return "Тест на совместимость"
        case .games: return "Игры"
        case .capsule: return "Капсула времени"
        case .vote: return "Голосование"
        case .radar: return "Подарочный радар"
        case .notes: return "Заметки"
        case .days: return "Наши даты"
        case .mood: return "Шарики по настроению"
        case .dates: return "Идеи свиданий"
        case .movies: return "Фильмы"
        case .today: return "Сегодня"
        case .memories: return "Фотолента"
        case .places: return "Карта"
        case .signal: return "Сигнал"
        case .pet: return "Питомец"
        }
    }

    var icon: String {
        switch self {
        case .tasks: return "checklist"
        case .calendar: return "calendar"
        case .wishes: return "gift"
        case .lists: return "list.bullet.clipboard"
        case .chat: return "bubble.left.and.bubble.right"
        case .plans: return "sparkles"
        case .files: return "lock.shield"
        case .cards: return "creditcard"
        case .question: return "questionmark.bubble"
        case .compat: return "heart.circle"
        case .games: return "gamecontroller"
        case .capsule: return "hourglass"
        case .vote: return "checkmark.seal"
        case .radar: return "binoculars"
        case .notes: return "note.text"
        case .days: return "heart.text.square"
        case .mood: return "face.smiling"
        case .dates: return "wineglass"
        case .movies: return "film"
        case .today: return "sun.max"
        case .memories: return "photo.on.rectangle.angled"
        case .places: return "map"
        case .signal: return "paperplane"
        case .pet: return "pawprint"
        }
    }

    /// Крупная картинка раздела (эмодзи рисуются системой в цвете и объёме).
    var art: String {
        switch self {
        case .tasks: return "✅"
        case .calendar: return "🗓️"
        case .wishes: return "🎁"
        case .lists: return "🛒"
        case .chat: return "💬"
        case .plans: return "🧭"
        case .files: return "🔐"
        case .cards: return "💳"
        case .question: return "🤔"
        case .compat: return "💞"
        case .games: return "🎮"
        case .capsule: return "⏳"
        case .vote: return "🗳️"
        case .radar: return "📡"
        case .notes: return "📝"
        case .days: return "💑"
        case .mood: return "🫙"
        case .dates: return "🍷"
        case .movies: return "🎬"
        case .today: return "🌤️"
        case .memories: return "📸"
        case .places: return "🗺️"
        case .signal: return "💌"
        case .pet: return "🐣"
        }
    }

    var subtitle: String {
        switch self {
        case .tasks: return "Дела на двоих"
        case .calendar: return "Даты и события"
        case .wishes: return "Что хочется получить"
        case .lists: return "Покупки и дела"
        case .chat: return "Сообщения друг другу"
        case .plans: return "Мечты и цели"
        case .files: return "Закрытые файлы"
        case .cards: return "Карты магазинов"
        case .question: return "Один вопрос в день"
        case .compat: return "Насколько вы подходите"
        case .games: return "Играйте по сети"
        case .capsule: return "Письмо в будущее"
        case .vote: return "Решите вместе"
        case .radar: return "Идеи для подарка"
        case .notes: return "Общие заметки"
        case .days: return "Годовщины и счётчики"
        case .mood: return "Шарики по настроению"
        case .dates: return "Куда сходить вдвоём"
        case .movies: return "Что смотрим и смотрели"
        case .today: return "Статус, сон, трекер"
        case .memories: return "Общие фото"
        case .places: return "Метки и расстояние"
        case .signal: return "Отправьте «скучаю»"
        case .pet: return "Растите вместе"
        }
    }

    var hex: String {
        switch self {
        case .tasks: return "4ADE80"
        case .calendar: return "0EA5E9"
        case .wishes: return "FF6FA3"
        case .lists: return "FB923C"
        case .chat: return "3B82F6"
        case .plans: return "8B5CF6"
        case .files: return "64748B"
        case .cards: return "2DD4BF"
        case .question: return "FBBF24"
        case .compat: return "D946EF"
        case .games: return "6366F1"
        case .capsule: return "C27C5A"
        case .vote: return "A3E635"
        case .radar: return "22D3EE"
        case .notes: return "9A8F6B"
        case .days: return "FF5A5F"
        case .mood: return "FDE047"
        case .dates: return "F43F5E"
        case .movies: return "A855F7"
        case .today: return "FF9F43"
        case .memories: return "C084FC"
        case .places: return "10B981"
        case .signal: return "FB7185"
        case .pet: return "E0A96D"
        }
    }

    var locked: Bool { self == .files || self == .cards }

    var isNew: Bool { self == .signal || self == .pet || self == .days || self == .mood || self == .dates || self == .today || self == .memories || self == .places }
}

// MARK: - Данные

struct Profile: Codable {
    var myName = ""
    var partnerName = ""
    var start = Date()
    var myHex = "0593C6"
    var partnerHex = "DB3996"
    var theme: ThemeMode = .system
    var radius: Double = 20
    var design: DesignStyle = .standard
    var haptics = true
    var order: [Module] = Module.defaultOrder
    var disabled: [Module] = []
    var onboarded = false
    var pairCode = ""
    var partnerCode = ""
    var lockApp = false
    var notifications = false
    var themeID = "lagoon"
    var wallpaper = "none"
    var iconID = ""
    var shareLocation = false
    var bubbleStyle = 0
    var cardStyle = 0              // 0 — мягкие с тенью, 1 — плоские, 2 — контур
    var bgStyle = 0                // 0 — тон верха, 1 — аврора (движется), 2 — однотонный
    var iconStyle = 0              // 0 — мягкие, 1 — цветные, 2 — тонкие
    var bgPattern = 0              // 0 — без узора, 1 — точки, 2 — сердечки, 3 — волны
    var sound = true               // звуки приложения
    var glassMode = 0              // стекло: 0 прозрачное, 1 матовое, 2 цветное

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? d }
        myName = v(.myName, "")
        partnerName = v(.partnerName, "")
        start = v(.start, Date())
        myHex = v(.myHex, "0593C6")
        partnerHex = v(.partnerHex, "DB3996")
        theme = v(.theme, .system)
        radius = v(.radius, 20)
        design = v(.design, .standard)
        haptics = v(.haptics, true)
        var ord: [Module] = v(.order, Module.defaultOrder)
        for m in Module.defaultOrder where !ord.contains(m) { if m == .today { ord.insert(m, at: 0) } else { ord.append(m) } }
        order = ord
        disabled = v(.disabled, [])
        onboarded = v(.onboarded, false)
        pairCode = v(.pairCode, "")
        partnerCode = v(.partnerCode, "")
        lockApp = v(.lockApp, false)
        notifications = v(.notifications, false)
        themeID = v(.themeID, "lagoon")
        wallpaper = v(.wallpaper, "none")
        iconID = v(.iconID, "")
        shareLocation = v(.shareLocation, false)
        bubbleStyle = v(.bubbleStyle, 0)
        cardStyle = v(.cardStyle, 0)
        bgStyle = v(.bgStyle, 0)
        iconStyle = v(.iconStyle, 0)
        bgPattern = v(.bgPattern, 0)
        sound = v(.sound, true)
        glassMode = v(.glassMode, 0)
    }
}

extension Module {
    static let defaultOrder: [Module] = [.today, .chat, .memories, .places, .signal, .pet, .tasks, .calendar, .wishes, .lists,
                                         .plans, .files, .cards, .question, .compat, .games, .capsule, .vote,
                                         .radar, .notes, .days, .mood, .dates, .movies]
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var note = ""
    var owner: Who? = nil          // nil — свободная задача
    var createdBy: Who = .me
    var due: Date? = nil
    var done = false
    var priority = 0               // 0...2
}

struct EventItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var emoji = "📌"
    var yearly = false
}

struct Wish: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var owner: Who = .me
    var price = ""
    var link = ""
    var note = ""
    var priority = 1
    var reserved = false           // тайно забронировано второй половинкой
    var got = false
}

/// Фильм, сериал или аниме: у каждого свой список (owner), у общих owner = nil.
struct MovieItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var year = ""
    var kind = 0               // 0 фильм, 1 сериал, 2 мультфильм, 3 аниме
    var owner: Who? = nil      // nil — смотрим вместе
    var state = 0              // 0 хочу посмотреть, 1 смотрю, 2 посмотрел
    var rating = 0             // 0 — без оценки, 1…5
    var progress = ""          // «2 сезон, 5 серия»
    var note = ""
    var date = Date()
}

struct ListEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done = false
}

struct UserList: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var emoji = "🛒"
    var items: [ListEntry] = []
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var from: Who
    var date = Date()
}

struct Plan: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var emoji = "✈️"
    var target: Date? = nil
    var steps: [ListEntry] = []
}

struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var body = ""
    var pinned = false
    var date = Date()
}

struct PollOption: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var voters: [Who] = []
}

struct Poll: Identifiable, Codable, Hashable {
    var id = UUID()
    var question: String
    var options: [PollOption]
}

struct TimeCapsule: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var text: String
    var opens: Date
    var from: Who = .me
}

struct SecureCard: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var number = ""
    var note = ""
    var symbology = "code128"      // code128, ean13, qr, pdf417, aztec
    var hex = "34C38F"

    init(name: String, number: String = "", note: String = "", symbology: String = "code128", hex: String = "34C38F") {
        self.name = name; self.number = number; self.note = note; self.symbology = symbology; self.hex = hex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Карта"
        number = (try? c.decodeIfPresent(String.self, forKey: .number)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        symbology = (try? c.decodeIfPresent(String.self, forKey: .symbology)) ?? "code128"
        hex = (try? c.decodeIfPresent(String.self, forKey: .hex)) ?? "34C38F"
    }
}

struct FileItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var stored: String
    var date = Date()
}

struct GiftIdea: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var occasion = ""
    var price = ""
    var bought = false
}

struct DayAnswer: Identifiable, Codable, Hashable {
    var id: String                 // yyyy-MM-dd
    var me = ""
    var partner = ""
}

struct MoodEntry: Identifiable, Codable, Hashable {
    var id: String                 // день + who
    var day: String
    var who: Who
    var mood: Int
}

struct CompatResult: Codable, Hashable {
    var percent: Int
    var date: Date
}

struct AppData: Codable {
    var profile = Profile()
    var tasks: [TaskItem] = []
    var events: [EventItem] = []
    var wishes: [Wish] = []
    var lists: [UserList] = []
    var messages: [ChatMessage] = []
    var plans: [Plan] = []
    var notes: [Note] = []
    var polls: [Poll] = []
    var capsules: [TimeCapsule] = []
    var cards: [SecureCard] = []
    var files: [FileItem] = []
    var gifts: [GiftIdea] = []
    var answers: [DayAnswer] = []
    var moods: [MoodEntry] = []
    var compat: CompatResult? = nil
    var pointsMe = 0
    var pointsPartner = 0
    var statuses: [StatusItem] = []
    var sleeps: [SleepEntry] = []
    var counters: [TrackerCounter] = []
    var tracks: [TrackerEvent] = []
    var jar: [JarBall] = []
    var photos: [PhotoItem] = []
    var reactions: [PhotoReaction] = []
    var pins: [MapPin] = []
    var places: [PlacePoint] = []
    var matches: [GameMatch] = []
    var signals: [SignalItem] = []
    var pets: [PetState] = []
    var batteries: [BatteryInfo] = []
    var movies: [MovieItem] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? d }
        profile = v(.profile, Profile())
        tasks = v(.tasks, [])
        events = v(.events, [])
        wishes = v(.wishes, [])
        lists = v(.lists, [])
        messages = v(.messages, [])
        plans = v(.plans, [])
        notes = v(.notes, [])
        polls = v(.polls, [])
        capsules = v(.capsules, [])
        cards = v(.cards, [])
        files = v(.files, [])
        gifts = v(.gifts, [])
        answers = v(.answers, [])
        moods = v(.moods, [])
        compat = try? c.decodeIfPresent(CompatResult.self, forKey: .compat)
        pointsMe = v(.pointsMe, 0)
        pointsPartner = v(.pointsPartner, 0)
        statuses = v(.statuses, [])
        sleeps = v(.sleeps, [])
        counters = v(.counters, [])
        tracks = v(.tracks, [])
        jar = v(.jar, [])
        photos = v(.photos, [])
        reactions = v(.reactions, [])
        pins = v(.pins, [])
        places = v(.places, [])
        matches = v(.matches, [])
        signals = v(.signals, [])
        pets = v(.pets, [])
        batteries = v(.batteries, [])
        movies = v(.movies, [])
    }
}

extension Date {
    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}
