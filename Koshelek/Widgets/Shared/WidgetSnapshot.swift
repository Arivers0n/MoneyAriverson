import Foundation

// Данные для виджетов. Приложение собирает снимок из операций и кладёт его в общий контейнер,
// расширение только читает снимок и показывает блоки через WidgetContent. Числа считаются теми же
// правилами, что и на главном экране (итоги месяца, лимит, напарник), поэтому виджет не расходится с приложением.
// Тексты и правила — те же, что в core/WidgetSnapshot.kt на Android.

// MARK: - Календарь

enum WidgetCalendar {
    /// Григорианский календарь с русской локалью; первый день недели — как в настройках приложения.
    static func make(firstWeekday: Int = 2) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = (firstWeekday == 1) ? 1 : 2
        return c
    }

    static func days(from a: Date, to b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func daysInMonth(_ date: Date, calendar: Calendar) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func sameMonth(_ a: Date, _ b: Date, calendar: Calendar) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }
}

// MARK: - Деньги

enum WidgetMoney {
    /// «12 340 ₽» с неразрывными пробелами; «−» для отрицательных. Скрытые суммы — «•••• ₽».
    static func rub(_ v: Double, hidden: Bool = false) -> String {
        if hidden { return "••••\u{00A0}₽" }
        guard v.isFinite else { return "0\u{00A0}₽" }
        let n = Int(min(abs(v), 1e15).rounded())
        let digits = Array(String(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out += "\u{00A0}" }
            out.append(ch)
        }
        return (v < 0 && n > 0 ? "−" : "") + out + "\u{00A0}₽"
    }
}

// MARK: - Снимок

/// Состояние одного дня недели в блоке «Неделя».
enum WidgetDot: Int, Codable, Sendable {
    case none = 0      // нет данных
    case future        // ещё не наступил
    case missed        // сильно превысили дневной лимит
    case partial       // немного превысили
    case done          // уложились в дневной лимит
    case today         // сегодня, трат пока нет
}

struct WidgetStat: Codable, Equatable, Sendable {
    var name: String
    var value: Double
}

struct WidgetGoal: Codable, Equatable, Sendable {
    var name: String
    var fraction: Double
}

struct WidgetPayment: Codable, Equatable, Sendable {
    var name: String
    var amount: Double
    var due: Date
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date
    /// Начало суток, для которых посчитано «сегодня».
    var dayStart: Date
    /// Лимит расходов на месяц; 0 — не задан.
    var budget: Double
    var monthExpense: Double
    var monthIncome: Double
    var todaySpend: Double
    /// Сумма по счетам; nil — счетов нет.
    var balance: Double?
    var saved: Double
    var goal: WidgetGoal?
    var nextPayment: WidgetPayment?
    /// Категории расходов месяца по убыванию, не больше трёх.
    var topCats: [WidgetStat]
    var level: Int
    var levelFraction: Double
    /// Rawvalue CompanionMood.
    var mood: String
    var userName: String
    var petName: String
    var phrase: String
    /// Семь дней текущей недели.
    var week: [WidgetDot]
    /// Есть ли в общем контейнере картинка питомца.
    var hasPetImage: Bool
    /// Включено «скрыть суммы».
    var hideAmounts: Bool
    /// 2 — понедельник, 1 — воскресенье.
    var firstWeekday: Int

    /// Снимок посчитан для сегодняшних суток.
    func isFresh(now: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: now) == calendar.startOfDay(for: dayStart)
    }

    /// Снимок посчитан для текущего месяца.
    func isFreshMonth(now: Date, calendar: Calendar) -> Bool {
        WidgetCalendar.sameMonth(now, dayStart, calendar: calendar)
    }

    /// Пример для галереи виджетов, предпросмотра в конструкторе и случая «данных ещё нет».
    static func sample(now: Date = Date()) -> WidgetSnapshot {
        let cal = WidgetCalendar.make()
        let today = cal.startOfDay(for: now)
        let due = cal.date(byAdding: .day, value: 4, to: today) ?? today
        return WidgetSnapshot(
            generatedAt: now, dayStart: today,
            budget: 60000, monthExpense: 37200, monthIncome: 85000, todaySpend: 640,
            balance: 45300, saved: 28500,
            goal: WidgetGoal(name: "Отпуск", fraction: 0.24),
            nextPayment: WidgetPayment(name: "Кредит на машину", amount: 12000, due: due),
            topCats: [WidgetStat(name: "Продукты", value: 12840), WidgetStat(name: "Кафе и рестораны", value: 4560),
                      WidgetStat(name: "Транспорт", value: 3210)],
            level: 4, levelFraction: 0.38, mood: "happy", userName: "", petName: "Искорка",
            phrase: "Ура! Ты отлично держишься в лимите — так и продолжай!",
            week: [.done, .done, .partial, .missed, .today, .future, .future],
            hasPetImage: false, hideAmounts: false, firstWeekday: 2)
    }
}

// MARK: - Сборка снимка

/// Операция в упрощённом виде — сборщик не зависит от SwiftData.
struct WidgetTxLite: Sendable {
    var date: Date
    var isExpense: Bool
    var isIncome: Bool
    var amount: Double
    var cat: String
    /// Учитывается в итогах (настройка «Долги в итогах»).
    var counts: Bool
}

struct WidgetSnapshotBuilder {
    var firstWeekday: Int = 2
    static let fallbackDailyLimit = 1500.0

    func make(txs: [WidgetTxLite], budget: Double, balance: Double?, saved: Double, goal: WidgetGoal?,
              payment: WidgetPayment?, level: Int, levelFraction: Double, mood: String,
              userName: String, petName: String, phrase: String, hideAmounts: Bool,
              catName: (String) -> String, now: Date = Date()) -> WidgetSnapshot {
        let cal = WidgetCalendar.make(firstWeekday: firstWeekday)
        let today = cal.startOfDay(for: now)

        var exp = 0.0, inc = 0.0, todaySum = 0.0
        var byCat: [String: Double] = [:]
        var spendByDay: [Date: Double] = [:]
        for t in txs where t.counts {
            let day = cal.startOfDay(for: t.date)
            if t.isExpense {
                spendByDay[day, default: 0] += t.amount
                if WidgetCalendar.sameMonth(t.date, now, calendar: cal) {
                    exp += t.amount
                    byCat[t.cat, default: 0] += t.amount
                }
                if day == today { todaySum += t.amount }
            } else if t.isIncome, WidgetCalendar.sameMonth(t.date, now, calendar: cal) {
                inc += t.amount
            }
        }

        let top = byCat.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map { WidgetStat(name: catName($0.key), value: $0.value) }

        let weekStart = WidgetCalendar.startOfWeek(now, calendar: cal)
        var week: [WidgetDot] = []
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: weekStart) ?? weekStart
            week.append(dot(day: day, today: today, spend: spendByDay[day] ?? 0, budget: budget, calendar: cal))
        }

        return WidgetSnapshot(
            generatedAt: now, dayStart: today, budget: max(0, budget), monthExpense: exp, monthIncome: inc,
            todaySpend: todaySum, balance: balance, saved: saved, goal: goal, nextPayment: payment,
            topCats: Array(top), level: level, levelFraction: levelFraction.clamped(to: 0...1), mood: mood,
            userName: userName, petName: petName, phrase: phrase, week: week, hasPetImage: false,
            hideAmounts: hideAmounts, firstWeekday: firstWeekday == 1 ? 1 : 2)
    }

    private func dot(day: Date, today: Date, spend: Double, budget: Double, calendar: Calendar) -> WidgetDot {
        if day > today { return .future }
        if day == today && spend == 0 { return .today }
        let limit = budget > 0 ? budget / Double(WidgetCalendar.daysInMonth(day, calendar: calendar)) : Self.fallbackDailyLimit
        if spend <= limit { return .done }
        if spend <= limit * 2 { return .partial }
        return .missed
    }
}

// MARK: - Что показывает блок

/// Готовое к показу содержимое блока. Рендерер только рисует его — выбирать числа и тексты ему не нужно.
enum WidgetValue: Equatable, Sendable {
    case text(String)
    case stat(value: String, caption: String)
    case ring(fraction: Double, center: String, caption: String)
    case bar(fraction: Double, label: String)
    case dots([WidgetDot], first: Int)
    case lines([String])
    case pet(mood: String, name: String)
}

enum WidgetContent {
    static func value(for block: WidgetBlock, snapshot s: WidgetSnapshot, now: Date = Date()) -> WidgetValue {
        let cal = WidgetCalendar.make(firstWeekday: s.firstWeekday)
        let dayFresh = s.isFresh(now: now, calendar: cal)
        let monthFresh = s.isFreshMonth(now: now, calendar: cal)
        func money(_ v: Double) -> String { WidgetMoney.rub(v, hidden: s.hideAmounts) }
        let reopen = "Откройте приложение"

        switch block.kind {
        case .budgetRing:
            guard monthFresh else { return .ring(fraction: 0, center: "—", caption: reopen) }
            guard s.budget > 0 else { return .ring(fraction: 0, center: "—", caption: "Нет лимита") }
            let f = s.monthExpense / s.budget
            return .ring(fraction: f, center: "\(Int((f * 100).rounded()))%", caption: f > 1 ? "перерасход" : "лимита")

        case .percentText:
            guard monthFresh, s.budget > 0 else { return .text("—") }
            return .text("\(Int((s.monthExpense / s.budget * 100).rounded()))%")

        case .todaySpend:
            guard dayFresh else { return .stat(value: "—", caption: reopen) }
            return .stat(value: money(s.todaySpend), caption: "сегодня")

        case .dailyLeft:
            guard monthFresh else { return .stat(value: "—", caption: reopen) }
            guard s.budget > 0 else { return .stat(value: "—", caption: "Нет лимита") }
            let left = s.budget - s.monthExpense
            if left <= 0 { return .stat(value: money(0), caption: "лимит исчерпан") }
            let day = cal.component(.day, from: now)
            let daysLeft = max(1, WidgetCalendar.daysInMonth(now, calendar: cal) - day + 1)
            return .stat(value: money(left / Double(daysLeft)), caption: "можно в день")

        case .monthExpense:
            guard monthFresh else { return .stat(value: "—", caption: reopen) }
            return .stat(value: money(s.monthExpense), caption: "расходы за месяц")

        case .monthIncome:
            guard monthFresh else { return .stat(value: "—", caption: reopen) }
            return .stat(value: money(s.monthIncome), caption: "доходы за месяц")

        case .balance:
            guard let b = s.balance else { return .stat(value: "—", caption: "Нет счетов") }
            return .stat(value: money(b), caption: "на счетах")

        case .savings:
            if s.goal == nil && s.saved == 0 { return .stat(value: "—", caption: "Нет копилок") }
            return .stat(value: money(s.saved), caption: "в копилках")

        case .goalBar:
            guard let g = s.goal else { return .bar(fraction: 0, label: "Нет копилок") }
            let f = g.fraction.clamped(to: 0...1)
            return .bar(fraction: f, label: "\(g.name) · \(Int((f * 100).rounded()))%")

        case .nextPayment:
            guard let p = s.nextPayment else { return .stat(value: "Платежей нет", caption: "Ближайший платёж") }
            let days = WidgetCalendar.days(from: now, to: p.due, calendar: cal)
            let when: String
            if days < 0 { when = "просрочен" }
            else if days == 0 { when = "сегодня" }
            else if days == 1 { when = "завтра" }
            else { when = "через \(days) дн." }
            return .stat(value: p.name, caption: "\(when) · \(money(p.amount))")

        case .topCategories:
            guard monthFresh, !s.topCats.isEmpty else { return .lines(["Нет трат"]) }
            return .lines(s.topCats.map { "\($0.name) · \(money($0.value))" })

        case .level:
            return .bar(fraction: s.levelFraction, label: "Уровень \(s.level)")

        case .phrase:
            return .text(s.phrase.isEmpty ? "Я рядом" : s.phrase)

        case .weekDots:
            return .dots(s.week.count == 7 ? s.week : Array(repeating: .none, count: 7), first: s.firstWeekday)

        case .date:
            return .text(russianDate(now, calendar: cal))

        case .greeting:
            let hour = cal.component(.hour, from: now)
            let base: String
            switch hour {
            case 5..<12: base = "Доброе утро"
            case 12..<18: base = "Добрый день"
            case 18..<23: base = "Добрый вечер"
            default: base = "Доброй ночи"
            }
            let name = s.userName.trimmingCharacters(in: .whitespaces)
            return .text(name.isEmpty ? base : "\(base), \(name)")

        case .petImage:
            return .pet(mood: s.mood, name: s.petName)

        case .customText:
            return .text(block.text.isEmpty ? "Мой текст" : block.text)
        }
    }

    /// «пн, 26 октября». Названия заданы явно, чтобы результат не зависел от платформы и локали.
    static func russianDate(_ date: Date, calendar: Calendar) -> String {
        let weekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня",
                      "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        let w = weekdays[(((c.weekday ?? 1) - 1) % 7 + 7) % 7]
        let m = months[(((c.month ?? 1) - 1) % 12 + 12) % 12]
        return "\(w), \(c.day ?? 1) \(m)"
    }

    /// Краткая строка для мест, где форме нет места (строка на экране блокировки, круг без кольца).
    static func plainText(_ v: WidgetValue, withCaption: Bool = false) -> String {
        switch v {
        case .text(let t): return t
        case .stat(let value, let caption): return withCaption ? "\(caption) \(value)" : value
        case .ring(_, let center, _): return center
        case .bar(_, let label): return label
        case .dots(let d, _): return d.map { $0 == .done ? "●" : "○" }.joined()
        case .lines(let l): return l.first ?? ""
        case .pet(_, let name): return name
        }
    }
}
