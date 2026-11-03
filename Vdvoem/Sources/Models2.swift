import SwiftUI

// MARK: - Статус на 24 часа

struct StatusItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var who: Who
    var kind: String
    var title: String
    var note = ""
    var place = ""
    var started = Date()
    var expires = Date().addingTimeInterval(24 * 3600)
}

struct StatusKind: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let hex: String
}

let statusKinds: [StatusKind] = [
    StatusKind(id: "sleep", title: "Сплю", symbol: "moon.zzz.fill", hex: "4A5FA8"),
    StatusKind(id: "work", title: "Работаю", symbol: "briefcase.fill", hex: "5B8DEF"),
    StatusKind(id: "study", title: "Учусь", symbol: "book.fill", hex: "7C6BE0"),
    StatusKind(id: "eat", title: "Ем", symbol: "fork.knife", hex: "F59E0B"),
    StatusKind(id: "cook", title: "Готовлю", symbol: "frying.pan.fill", hex: "E8590C"),
    StatusKind(id: "coffee", title: "Пью кофе", symbol: "cup.and.saucer.fill", hex: "A0674B"),
    StatusKind(id: "commute", title: "В дороге", symbol: "car.fill", hex: "3B82C4"),
    StatusKind(id: "walk", title: "Гуляю", symbol: "figure.walk", hex: "2FA36B"),
    StatusKind(id: "gym", title: "Тренируюсь", symbol: "figure.run", hex: "E0457B"),
    StatusKind(id: "shop", title: "В магазине", symbol: "bag.fill", hex: "D946A8"),
    StatusKind(id: "relax", title: "Отдыхаю", symbol: "sofa.fill", hex: "36B5A0"),
    StatusKind(id: "movie", title: "Смотрю кино", symbol: "film.fill", hex: "6D5BD0"),
    StatusKind(id: "game", title: "Играю", symbol: "gamecontroller.fill", hex: "8B5CF6"),
    StatusKind(id: "call", title: "На звонке", symbol: "phone.fill", hex: "22A6B3"),
    StatusKind(id: "shower", title: "В душе", symbol: "shower.fill", hex: "38BDF8"),
    StatusKind(id: "tired", title: "Устал(а)", symbol: "battery.25", hex: "94A3B8"),
    StatusKind(id: "sick", title: "Болею", symbol: "thermometer.medium", hex: "EF4444"),
    StatusKind(id: "party", title: "На празднике", symbol: "party.popper.fill", hex: "F97316"),
    StatusKind(id: "miss", title: "Скучаю", symbol: "heart.fill", hex: "F43F5E"),
    StatusKind(id: "free", title: "Свободен(на)", symbol: "sparkles", hex: "10B981")
]

func statusKind(_ id: String) -> StatusKind {
    statusKinds.first { $0.id == id } ?? StatusKind(id: id, title: id, symbol: "circle.fill", hex: "94A3B8")
}

// MARK: - Сон

struct SleepEntry: Identifiable, Codable, Hashable {
    var id: String                 // день + who
    var day: String
    var who: Who
    var bedtime: Date
    var wake: Date
    var quality: Int               // 1...5
    var hours: Double { max(0, wake.timeIntervalSince(bedtime) / 3600) }
}

let sleepTitles = ["", "Бедный", "Плохой", "Средний", "Хороший", "Отличный"]
let sleepHexes = ["", "E5484D", "F2762E", "F5B83D", "7CC264", "2FA36B"]

func sleepQuality(forHours h: Double) -> Int {
    switch h {
    case ..<4: return 1
    case ..<5.5: return 2
    case ..<6.8: return 3
    case ..<8.8: return 4
    default: return 5
    }
}

// MARK: - Трекер

struct TrackerCounter: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var emoji: String
    var hex: String
}

struct TrackerEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var counter: UUID
    var who: Who
    var date = Date()
}

// MARK: - Банка настроения

struct JarBall: Identifiable, Codable, Hashable {
    var id = UUID()
    var who: Who
    var mood: Int                  // индекс в jarMoods
    var note = ""
    var date = Date()
}

struct JarMood: Identifiable, Hashable {
    let id: Int
    let title: String
    let emoji: String
    let hex: String
}

let jarMoods: [JarMood] = [
    JarMood(id: 0, title: "Отлично", emoji: "😄", hex: "FFB02E"),
    JarMood(id: 1, title: "Спокойно", emoji: "🙂", hex: "46C2A5"),
    JarMood(id: 2, title: "Грустно", emoji: "😢", hex: "5B8DEF"),
    JarMood(id: 3, title: "Злюсь", emoji: "😠", hex: "EF5350"),
    JarMood(id: 4, title: "Устал(а)", emoji: "😴", hex: "9B7BE8")
]

// MARK: - Фотолента и карта

struct PhotoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var who: Who
    var media: String              // id записи файла на сервере
    var file: String               // имя файла на сервере
    var caption = ""
    var date = Date()
    var pin: UUID? = nil
    var ratio: Double = 1          // ширина / высота
}

struct PhotoReaction: Identifiable, Codable, Hashable {
    var id: String                 // фото + who
    var photo: UUID
    var who: Who
    var emoji: String
}

let reactionEmojis = ["❤️", "😍", "😂", "🔥", "🥹", "👍"]

struct MapPin: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var note = ""
    var lat: Double
    var lon: Double
    var emoji = "📍"
    var who: Who
    var date = Date()
}

struct PlacePoint: Identifiable, Codable, Hashable {
    var id: String                 // who.rawValue
    var who: Who
    var lat: Double
    var lon: Double
    var updated: Date
}

// MARK: - Сетевые игры

enum GameKind: String, Codable, CaseIterable, Identifiable {
    case ttt, four, reversi, checkers, dots, battleship, durak, memory, rps, hangman
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ttt: return "Крестики-нолики"
        case .four: return "4 в ряд"
        case .reversi: return "Реверси"
        case .checkers: return "Шашки"
        case .dots: return "Точки и квадратики"
        case .battleship: return "Морской бой"
        case .durak: return "Дурак"
        case .memory: return "Найди пару"
        case .rps: return "Камень-ножницы-бумага"
        case .hangman: return "Виселица"
        }
    }

    var icon: String {
        switch self {
        case .ttt: return "number"
        case .four: return "square.grid.3x3.square"
        case .reversi: return "circle.lefthalf.filled"
        case .checkers: return "circle.circle"
        case .dots: return "circle.grid.3x3.fill"
        case .battleship: return "sailboat"
        case .durak: return "suit.spade"
        case .memory: return "brain.head.profile"
        case .rps: return "hand.raised"
        case .hangman: return "textformat.abc"
        }
    }

    var art: String {
        switch self {
        case .ttt: return "❌"
        case .four: return "🔴"
        case .reversi: return "⚫️"
        case .checkers: return "♟️"
        case .dots: return "🔲"
        case .battleship: return "🚢"
        case .durak: return "🃏"
        case .memory: return "🧠"
        case .rps: return "✊"
        case .hangman: return "🔤"
        }
    }

    var blurb: String {
        switch self {
        case .ttt: return "Три в ряд, быстро"
        case .four: return "Соберите четыре в линию"
        case .reversi: return "Захватывайте фишки"
        case .checkers: return "Классические русские шашки"
        case .dots: return "Замыкайте квадраты"
        case .battleship: return "Тайные флоты 10×10"
        case .durak: return "Подкидной, колода 36"
        case .memory: return "Откройте все пары"
        case .rps: return "До двух побед"
        case .hangman: return "Загадайте слово любимому"
        }
    }

    var hex: String {
        switch self {
        case .ttt: return "FF9AA8"
        case .four: return "FFB86B"
        case .reversi: return "9AA7C7"
        case .checkers: return "D9B38C"
        case .dots: return "8EC5FF"
        case .battleship: return "6FD0E8"
        case .durak: return "C9A7FF"
        case .memory: return "FFD36E"
        case .rps: return "9BE7C4"
        case .hangman: return "FFA8D0"
        }
    }

    /// Игры со скрытой информацией (руки, флот, выбор) нельзя играть вдвоём на одном телефоне.
    var needsPair: Bool { [.battleship, .durak, .rps, .hangman].contains(self) }

    var size: (rows: Int, cols: Int) {
        switch self {
        case .ttt: return (3, 3)
        case .four: return (6, 7)
        case .reversi, .checkers: return (8, 8)
        default: return (1, 1)
        }
    }
}

enum MatchState: String, Codable { case playing, won, draw }

struct GameMatch: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: GameKind
    var board: [Int]               // правила — в GamesCore.swift; 1 — «моё», 2 — «партнёра»
    var turn: Who
    var starter: Who
    var state: MatchState = .playing
    var winner: Who? = nil
    var moves = 0
    var last = -1
    var updated = Date()
    // Дополнительные поля для сложных игр (необязательные — старые версии не ломаются)
    var aux: Int? = nil
    var extra: [Int]? = nil
    var table: [Int]? = nil
    var word: String? = nil
    var guesses: String? = nil
}

// MARK: - Сигналы, питомец, батарея

struct SignalKind: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
    let hex: String
}

let signalKinds: [SignalKind] = [
    SignalKind(id: "miss", emoji: "💗", title: "Скучаю по тебе", hex: "FF5C8A"),
    SignalKind(id: "hug", emoji: "🤗", title: "Обнимаю", hex: "FFB02E"),
    SignalKind(id: "kiss", emoji: "😘", title: "Целую", hex: "FF7A9C"),
    SignalKind(id: "think", emoji: "💭", title: "Думаю о тебе", hex: "8C7BF2"),
    SignalKind(id: "hi", emoji: "👋", title: "Привет!", hex: "34C38F"),
    SignalKind(id: "love", emoji: "😍", title: "Люблю", hex: "F43F5E")
]

func signalKind(_ id: String) -> SignalKind { signalKinds.first { $0.id == id } ?? signalKinds[0] }

struct SignalItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var who: Who
    var kind: String
    var date = Date()
}

/// Общий питомец пары. Один документ на пару (id «pet»).
struct PetState: Identifiable, Codable, Hashable {
    var id = "pet"
    var name = "Малыш"
    var born = Date()
    var lastFed = Date()
    var lastPlayed = Date()
    var lastCuddled = Date.distantPast
    var fedBy: Who = .me
    var colorIndex = 0
}

struct BatteryInfo: Identifiable, Codable, Hashable {
    var id: String                 // who.rawValue
    var who: Who
    var level: Double              // 0...1
    var charging: Bool
    var updated: Date
}
