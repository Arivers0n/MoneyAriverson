import SwiftUI
import UIKit

// MARK: - Цвета

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(UIColor { tc in
            UIColor(Color(hex: tc.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

enum Theme {
    static var accent: Color { Appearance.shared.accentColor }
    static var onAccent: Color { Appearance.shared.onAccent }
    static let inc = Color.dynamic("17805A", "4CC995")
    static let exp = Color.dynamic("B8452A", "F0886B")
    static let warn = Color.dynamic("B7791F", "E8B04E")
    static let ink = Color.dynamic("16201C", "E8EEEA")
    static var bg: Color { Appearance.shared.background == "pure" ? Color(.systemBackground) : Color(.systemGroupedBackground) }
    static var card: Color { Appearance.shared.background == "pure" ? Color(.secondarySystemBackground) : Color(.secondarySystemGroupedBackground) }
    static let soft = Color(.tertiarySystemFill)
    static let palette = ["2B47C9", "17805A", "C2621F", "8A4FD0", "1A9BB0", "D04F6E", "9A8A1F", "4E5E9E"]
}

// MARK: - Даты

let ruLocale = Locale(identifier: "ru_RU")
var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.locale = ruLocale
    c.firstWeekday = 2
    return c
}()

extension Date {
    var noon: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: self) ?? self }
    var day0: Date { cal.startOfDay(for: self) }
    var startOfMonth: Date { cal.date(from: cal.dateComponents([.year, .month], from: self)) ?? self }
    func addingMonths(_ n: Int) -> Date { cal.date(byAdding: .month, value: n, to: self) ?? self }
    func addingDays(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: self) ?? self }
    func sameDay(_ o: Date) -> Bool { cal.isDate(self, inSameDayAs: o) }
    func sameMonth(_ o: Date) -> Bool { cal.isDate(self, equalTo: o, toGranularity: .month) }
    var dayNum: Int { cal.component(.day, from: self) }
    var monthNum: Int { cal.component(.month, from: self) }
    var daysInMonth: Int { cal.range(of: .day, in: .month, for: self)?.count ?? 30 }
}

func daysBetween(_ a: Date, _ b: Date) -> Int {
    cal.dateComponents([.day], from: a.day0, to: b.day0).day ?? 0
}
func monthsBetween(_ a: Date, _ b: Date) -> Int {
    cal.dateComponents([.month], from: a.day0, to: b.day0).month ?? 0
}

enum DF {
    private static var cache: [String: DateFormatter] = [:]
    static func f(_ format: String) -> DateFormatter {
        if let d = cache[format] { return d }
        let d = DateFormatter()
        d.locale = ruLocale
        d.dateFormat = format
        cache[format] = d
        return d
    }
    static func s(_ date: Date, _ format: String) -> String { f(format).string(from: date) }
    static func iso(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
    static func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)?.noon
    }
    static func month(_ d: Date) -> String { s(d, "LLLL yyyy").capitalizedFirst }
    static func monthShort(_ d: Date) -> String { s(d, "LLL").replacingOccurrences(of: ".", with: "").capitalizedFirst }
    static func short(_ d: Date) -> String { s(d, "d MMM").replacingOccurrences(of: ".", with: "") }
    static func long(_ d: Date) -> String { s(d, "d MMMM yyyy") }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    /// Заметка из голоса: «Купил кофе .» → «Купил кофе», лишние пробелы и хвостовые знаки убираются.
    var cleanedNote: String {
        var s = self.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " ([.,!?;:])", with: "$1", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, ".,;:-—".contains(last) { s.removeLast(); s = s.trimmingCharacters(in: .whitespaces) }
        return s
    }
}

extension View {
    /// Суммы никогда не обрезаются и не сжимаются — им отдаём место первыми.
    func amountFixed() -> some View { lineLimit(1).fixedSize(horizontal: true, vertical: false).layoutPriority(1) }
}

// MARK: - Деньги и слова

enum Fmt {
    static let nf: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = "\u{00A0}"
        f.locale = ruLocale
        return f
    }()
    static let nf2: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.groupingSeparator = ""
        f.decimalSeparator = ","
        f.locale = ruLocale
        return f
    }()
    /// «1 234 ₽», со знаком минус для отрицательных
    static let nfKop: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.groupingSeparator = "\u{00A0}"
        f.decimalSeparator = ","
        f.locale = ruLocale
        return f
    }()
    static func rub(_ v: Double) -> String {
        if Appearance.shared.showKopecks {
            return (v < 0 ? "−" : "") + (nfKop.string(from: NSNumber(value: (abs(v) * 100).rounded() / 100)) ?? "0") + "\u{00A0}₽"
        }
        return (v < 0 ? "−" : "") + (nf.string(from: NSNumber(value: abs(v.rounded()))) ?? "0") + "\u{00A0}₽"
    }
    static func rubU(_ v: Double) -> String { rub(abs(v)) }
    static func signed(_ v: Double) -> String { (v >= 0 ? "+" : "−") + rubU(v) }
    static func input(_ v: Double) -> String { v == 0 ? "" : (nf2.string(from: NSNumber(value: v)) ?? "") }
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 { return String(format: "%.1fм", a / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if a >= 1000 { return "\(Int((a / 1000).rounded()))к" }
        return "\(Int(a))"
    }
}

func parseAmount(_ s: String) -> Double? {
    let t = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: ",", with: ".")
    guard let v = Double(t), v.isFinite else { return nil }
    return v
}

func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let n = abs(n) % 100, k = n % 10
    if n > 10 && n < 20 { return many }
    if k == 1 { return one }
    if k >= 2 && k <= 4 { return few }
    return many
}

func relDays(_ due: Date) -> (text: String, bad: Bool) {
    let n = daysBetween(Date(), due)
    if n == 0 { return ("сегодня", false) }
    if n == 1 { return ("завтра", false) }
    if n > 0 { return ("через \(n) \(plural(n, "день", "дня", "дней"))", false) }
    return ("просрочен на \(-n) \(plural(-n, "день", "дня", "дней"))", true)
}

func spanText(to d: Date) -> String {
    let m = monthsBetween(Date(), d)
    if m < 1 {
        let n = daysBetween(Date(), d)
        return n <= 0 ? "уже скоро" : "через \(n) \(plural(n, "день", "дня", "дней"))"
    }
    let y = m / 12, mm = m % 12
    var parts: [String] = []
    if y > 0 { parts.append("\(y) \(plural(y, "год", "года", "лет"))") }
    if mm > 0 { parts.append("\(mm) мес.") }
    return "через " + parts.joined(separator: " ")
}

// MARK: - Категории

enum TxKind: String, Codable, CaseIterable {
    case exp, inc, tr
}

struct Category: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: String
    let kind: TxKind
    var symbol: String = ""
    var color: Color { Color(hex: hex) }
}

enum Catalog {
    static let baseExpense: [Category] = [
        .init(id: "food", name: "Продукты", hex: "2E8B57", kind: .exp),
        .init(id: "cafe", name: "Кафе", hex: "D9822B", kind: .exp),
        .init(id: "transport", name: "Транспорт", hex: "3B6FD8", kind: .exp),
        .init(id: "home", name: "Жильё и ЖКУ", hex: "7B5CC4", kind: .exp),
        .init(id: "loans", name: "Кредиты и долги", hex: "4E5E9E", kind: .exp),
        .init(id: "subs", name: "Подписки", hex: "8A4FD0", kind: .exp),
        .init(id: "phone", name: "Связь и интернет", hex: "1A9BB0", kind: .exp),
        .init(id: "health", name: "Здоровье", hex: "D04F6E", kind: .exp),
        .init(id: "clothes", name: "Одежда", hex: "A4703A", kind: .exp),
        .init(id: "fun", name: "Развлечения", hex: "C04FB0", kind: .exp),
        .init(id: "gifts", name: "Подарки", hex: "E0A21A", kind: .exp),
        .init(id: "savings", name: "Накопления", hex: "2F7D8C", kind: .exp),
        .init(id: "other", name: "Другое", hex: "7A8580", kind: .exp),
    ]
    static let baseIncome: [Category] = [
        .init(id: "salary", name: "Зарплата", hex: "17805A", kind: .inc),
        .init(id: "side", name: "Подработка", hex: "2F9E8F", kind: .inc),
        .init(id: "debtback", name: "Возврат долга", hex: "3E7FA8", kind: .inc),
        .init(id: "cashback", name: "Кэшбэк", hex: "9A8A1F", kind: .inc),
        .init(id: "gift", name: "Подарок", hex: "E0A21A", kind: .inc),
        .init(id: "iother", name: "Другое", hex: "7A8580", kind: .inc),
    ]
    static let symbols: [String: String] = [
        "food": "cart.fill", "cafe": "cup.and.saucer.fill", "transport": "car.fill", "home": "house.fill",
        "loans": "building.columns.fill", "subs": "play.rectangle.fill", "phone": "wifi", "health": "cross.case.fill",
        "clothes": "tshirt.fill", "fun": "gamecontroller.fill", "gifts": "gift.fill", "savings": "banknote.fill",
        "other": "ellipsis", "salary": "briefcase.fill", "side": "hammer.fill", "debtback": "arrow.uturn.backward",
        "cashback": "percent", "gift": "gift.fill", "iother": "ellipsis",
    ]
    /// Служебные категории нельзя скрыть: на них опираются долги, копилки и «Другое».
    static let locked: Set<String> = ["loans", "savings", "other", "debtback", "iother"]

    // Кэш итогового каталога с учётом настроек пользователя
    private static var cacheKey = -1
    private static var cacheAll: [Category] = []

    /// Все категории (включая скрытые) — для отображения старых операций.
    static var all: [Category] {
        let p = CategoryPrefs.shared
        if cacheKey == p.version { return cacheAll }
        func apply(_ c: Category) -> Category {
            let o = p.overrides[c.id]
            return Category(id: c.id, name: (o?.name).flatMap { $0.isEmpty ? nil : $0 } ?? c.name,
                            hex: o?.hex ?? c.hex, kind: c.kind, symbol: o?.symbol ?? symbols[c.id] ?? "circle.fill")
        }
        var out = (baseExpense + baseIncome).map(apply)
        for c in p.custom {
            out.append(Category(id: c.id, name: c.name, hex: c.hex, kind: c.kind == "inc" ? .inc : .exp, symbol: c.symbol))
        }
        cacheAll = out
        cacheKey = p.version
        return out
    }
    static var expense: [Category] { all.filter { $0.kind == .exp && !CategoryPrefs.shared.hidden.contains($0.id) } }
    static var income: [Category] { all.filter { $0.kind == .inc && !CategoryPrefs.shared.hidden.contains($0.id) } }

    static func list(_ k: TxKind) -> [Category] { k == .inc ? income : expense }
    static func cat(_ id: String) -> Category {
        all.first { $0.id == id } ?? all.first { $0.id == "other" }!
    }
    static func valid(_ id: String, for kind: TxKind) -> String {
        if all.contains(where: { $0.id == id && $0.kind == kind }) { return id }
        return kind == .inc ? "iother" : "other"
    }
    static func byName(_ name: String, kind: TxKind) -> String {
        all.first { $0.kind == kind && $0.name.lowercased() == name.lowercased() }?.id ?? (kind == .inc ? "iother" : "other")
    }
    static func describe() -> String {
        "Категории расходов (type \"exp\"): " + expense.map { "\($0.id)=\($0.name)" }.joined(separator: ", ") +
        ".\nКатегории доходов (type \"inc\"): " + income.map { "\($0.id)=\($0.name)" }.joined(separator: ", ") + "."
    }
}

enum DebtType: String, CaseIterable, Identifiable {
    case credit, card, micro, person
    var id: String { rawValue }
    var name: String {
        switch self {
        case .credit: return "Кредит"
        case .card: return "Кредитка"
        case .micro: return "Микрозайм"
        case .person: return "Человек"
        }
    }
    var longName: String { self == .person ? "Долг человеку" : name }
    var hex: String {
        switch self {
        case .credit: return "2B47C9"
        case .card: return "7B5CC4"
        case .micro: return "C2621F"
        case .person: return "1A8F86"
        }
    }
    var color: Color { Color(hex: hex) }
    var lenderLabel: String {
        switch self {
        case .credit, .card: return "Банк"
        case .micro: return "МФО"
        case .person: return "Кто"
        }
    }
    var placeholder: String {
        switch self {
        case .credit: return "Сбер"
        case .card: return "Т-Банк"
        case .micro: return "Займер"
        case .person: return "Андрей"
        }
    }
}
