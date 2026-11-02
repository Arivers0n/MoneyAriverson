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
        case .mood: return "Настроение"
        case .dates: return "Идеи свиданий"
        }
    }

    var icon: String {
        switch self {
        case .tasks: return "checklist"
        case .calendar: return "calendar"
        case .wishes: return "gift"
        case .lists: return "list.bullet.rectangle"
        case .chat: return "bubble.left.and.bubble.right"
        case .plans: return "flag"
        case .files: return "folder"
        case .cards: return "creditcard"
        case .question: return "questionmark.circle"
        case .compat: return "heart.circle"
        case .games: return "gamecontroller"
        case .capsule: return "envelope"
        case .vote: return "checkmark.circle"
        case .radar: return "dot.radiowaves.left.and.right"
        case .notes: return "note.text"
        case .days: return "heart.text.square"
        case .mood: return "face.smiling"
        case .dates: return "sparkles"
        }
    }

    var locked: Bool { self == .files || self == .cards }

    var isNew: Bool { self == .days || self == .mood || self == .dates }
}

// MARK: - Данные

struct Profile: Codable {
    var myName = ""
    var partnerName = ""
    var start = Date()
    var myHex = "4C9AF0"
    var partnerHex = "D870A8"
    var theme: ThemeMode = .dark
    var radius: Double = 22
    var design: DesignStyle = .rounded
    var haptics = true
    var order: [Module] = [.tasks, .calendar, .wishes, .lists, .chat, .plans, .files, .cards,
                           .question, .compat, .games, .capsule, .vote, .radar, .notes,
                           .days, .mood, .dates]
    var disabled: [Module] = []
    var onboarded = false
    var pairCode = ""
    var partnerCode = ""
    var lockApp = false
    var notifications = false
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
}

extension Date {
    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}
