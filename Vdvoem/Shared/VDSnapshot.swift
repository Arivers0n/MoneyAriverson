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

    // Задачи, даты, планы и прочее для дополнительных виджетов
    var tasks: [WTask] = []
    var tasksDone = 0
    var events: [WEvent] = []
    var plans: [WPlan] = []
    var wishes: [String] = []
    var wishesTotal = 0
    var movies: [WMovie] = []
    var capsuleTitle = ""
    var capsuleOpens: Date?
    var capsuleCount = 0
    var poll: WPoll?
    var winsMe = 0
    var winsPartner = 0
    var myTurns = 0
    var petName = ""
    var petAgeDays = 0
    var petFedHours = 0
    var messagesToday = 0
    var lastMessage = ""

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        updated = v(.updated, Date()); myName = v(.myName, "Я"); partnerName = v(.partnerName, "Партнёр")
        myHex = v(.myHex, "4C9AF0"); partnerHex = v(.partnerHex, "D870A8")
        statusTitle = v(.statusTitle, ""); statusSymbol = v(.statusSymbol, ""); statusHex = v(.statusHex, ""); statusNote = v(.statusNote, "")
        statusStarted = v(.statusStarted, nil); statusExpires = v(.statusExpires, nil)
        partnerMoodEmoji = v(.partnerMoodEmoji, ""); partnerMoodTitle = v(.partnerMoodTitle, ""); myMoodEmoji = v(.myMoodEmoji, "")
        distanceText = v(.distanceText, ""); daysTogether = v(.daysTogether, 0)
        hasPhoto = v(.hasPhoto, false); photoCaption = v(.photoCaption, "")
        tasks = v(.tasks, []); tasksDone = v(.tasksDone, 0); events = v(.events, []); plans = v(.plans, [])
        wishes = v(.wishes, []); wishesTotal = v(.wishesTotal, 0); movies = v(.movies, [])
        capsuleTitle = v(.capsuleTitle, ""); capsuleOpens = v(.capsuleOpens, nil); capsuleCount = v(.capsuleCount, 0)
        poll = v(.poll, nil); winsMe = v(.winsMe, 0); winsPartner = v(.winsPartner, 0); myTurns = v(.myTurns, 0)
        petName = v(.petName, ""); petAgeDays = v(.petAgeDays, 0); petFedHours = v(.petFedHours, 0)
        messagesToday = v(.messagesToday, 0); lastMessage = v(.lastMessage, "")
    }

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
        let now = Date(), day: TimeInterval = 86400
        s.tasks = [WTask(title: "Купить хлеб", who: "partner", due: now, priority: 1),
                   WTask(title: "Забронировать столик", who: "me", due: now.addingTimeInterval(day), priority: 2),
                   WTask(title: "Позвонить маме", who: "", due: nil, priority: 0),
                   WTask(title: "Оплатить интернет", who: "me", due: now.addingTimeInterval(3 * day), priority: 0)]
        s.tasksDone = 7
        s.events = [WEvent(title: "Годовщина", emoji: "💍", date: now.addingTimeInterval(9 * day)),
                    WEvent(title: "День рождения", emoji: "🎂", date: now.addingTimeInterval(23 * day)),
                    WEvent(title: "Поездка в Сочи", emoji: "✈️", date: now.addingTimeInterval(41 * day)),
                    WEvent(title: "Кино", emoji: "🎬", date: now.addingTimeInterval(2 * day))]
        s.plans = [WPlan(title: "Отпуск", emoji: "🏝", done: 3, total: 8, target: now.addingTimeInterval(60 * day)),
                   WPlan(title: "Ремонт кухни", emoji: "🛠", done: 1, total: 5, target: nil)]
        s.wishes = ["Кофемашина", "Плед", "Билеты на концерт", "Книга"]
        s.wishesTotal = 6
        s.movies = [WMovie(title: "Интерстеллар", owner: "", state: 1, progress: "", kind: 0),
                    WMovie(title: "Тед Лассо", owner: "", state: 0, progress: "", kind: 1),
                    WMovie(title: "Дюна", owner: "partner", state: 1, progress: "", kind: 0)]
        s.capsuleTitle = "Письмо через год"
        s.capsuleOpens = now.addingTimeInterval(120 * day)
        s.capsuleCount = 2
        s.poll = WPoll(question: "Куда идём на выходных?", options: [WOpt(text: "Кино", votes: 1, mine: true), WOpt(text: "Прогулка", votes: 1, mine: false), WOpt(text: "Дома", votes: 0, mine: false)])
        s.winsMe = 5; s.winsPartner = 4; s.myTurns = 1
        s.petName = "Малыш"; s.petAgeDays = 120; s.petFedHours = 3
        s.messagesToday = 12; s.lastMessage = "Уже в магазине"
        return s
    }
}


struct WTask: Codable, Hashable { var title: String; var who: String; var due: Date?; var priority: Int }
struct WEvent: Codable, Hashable { var title: String; var emoji: String; var date: Date }
struct WPlan: Codable, Hashable { var title: String; var emoji: String; var done: Int; var total: Int; var target: Date? }
struct WMovie: Codable, Hashable { var title: String; var owner: String; var state: Int; var progress: String; var kind: Int }
struct WOpt: Codable, Hashable { var text: String; var votes: Int; var mine: Bool }
struct WPoll: Codable, Hashable { var question: String; var options: [WOpt] }
