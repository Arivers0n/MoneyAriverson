import Foundation
import SwiftData

@Model
final class Tx {
    var uid: UUID = UUID()
    var kindRaw: String = "exp"
    var amount: Double = 0
    var cat: String = "other"
    var note: String = ""
    var date: Date = Date()
    var created: Date = Date()
    var accID: UUID? = nil
    var toID: UUID? = nil
    var recID: UUID? = nil

    init(kind: TxKind, amount: Double, cat: String, note: String, date: Date,
         accID: UUID? = nil, toID: UUID? = nil, recID: UUID? = nil) {
        self.uid = UUID()
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.cat = cat
        self.note = note
        self.date = date.noon
        self.created = Date()
        self.accID = accID
        self.toID = toID
        self.recID = recID
    }

    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .exp }
        set { kindRaw = newValue.rawValue }
    }
    /// + для дохода, − для расхода, 0 для перевода
    var signedAmount: Double {
        switch kind {
        case .inc: return amount
        case .exp: return -amount
        case .tr: return 0
        }
    }
}

@Model
final class Account {
    var uid: UUID = UUID()
    var name: String = ""
    var start: Double = 0
    var hex: String = "2B47C9"
    var created: Date = Date()

    init(name: String, start: Double, hex: String) {
        self.uid = UUID()
        self.name = name
        self.start = start
        self.hex = hex
        self.created = Date()
    }
}

struct Paid: Codable, Hashable {
    var date: Date
    var amount: Double
    var late: Bool
}

struct ExtraPay: Codable, Hashable {
    var date: Date
    var amount: Double
}

@Model
final class Debt {
    var uid: UUID = UUID()
    var typeRaw: String = "credit"
    var dirIn: Bool = false
    var name: String = ""
    var lender: String = ""
    var total: Double = 0
    var payment: Double = 0
    var n: Int = 1
    var first: Date = Date()
    var rate: Double = 0
    var paymentsData: Data = Data()
    var extraData: Data = Data()
    var created: Date = Date()

    init(type: DebtType, dirIn: Bool, name: String, lender: String, total: Double, payment: Double, n: Int, first: Date, rate: Double) {
        self.uid = UUID()
        self.typeRaw = type.rawValue
        self.dirIn = dirIn
        self.name = name
        self.lender = lender
        self.total = total
        self.payment = payment
        self.n = n
        self.first = first.noon
        self.rate = rate
        self.created = Date()
    }

    var type: DebtType {
        get { DebtType(rawValue: typeRaw) ?? .credit }
        set { typeRaw = newValue.rawValue }
    }
    var isOut: Bool { !dirIn }

    var payments: [Int: Paid] {
        get { (try? JSONDecoder().decode([Int: Paid].self, from: paymentsData)) ?? [:] }
        set { paymentsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var extras: [ExtraPay] {
        get { (try? JSONDecoder().decode([ExtraPay].self, from: extraData)) ?? [] }
        set { extraData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model
final class Recurring {
    var uid: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var kindRaw: String = "exp"
    var cat: String = "subs"
    var day: Int = 1
    var yearly: Bool = false
    var month: Int = 1
    var created: Date = Date()

    init(name: String, amount: Double, kind: TxKind, cat: String, day: Int, yearly: Bool, month: Int) {
        self.uid = UUID()
        self.name = name
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.cat = cat
        self.day = day
        self.yearly = yearly
        self.month = month
        self.created = Date()
    }
    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .exp }
        set { kindRaw = newValue.rawValue }
    }
}

struct GoalEntry: Codable, Hashable {
    var date: Date
    var amount: Double
}

@Model
final class Goal {
    var uid: UUID = UUID()
    var name: String = ""
    var target: Double = 0
    var deadline: Date? = nil
    var hex: String = "2B47C9"
    var logData: Data = Data()
    var created: Date = Date()

    init(name: String, target: Double, deadline: Date?, hex: String) {
        self.uid = UUID()
        self.name = name
        self.target = target
        self.deadline = deadline
        self.hex = hex
        self.created = Date()
    }
    var log: [GoalEntry] {
        get { (try? JSONDecoder().decode([GoalEntry].self, from: logData)) ?? [] }
        set { logData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var saved: Double { log.reduce(0) { $0 + $1.amount } }
}

// MARK: - Жизнь

@Model
final class ShopItem {
    var uid: UUID = UUID()
    var name: String = ""
    var done: Bool = false
    var created: Date = Date()
    init(name: String) {
        self.uid = UUID()
        self.name = name
        self.created = Date()
    }
}

@Model
final class Habit {
    var uid: UUID = UUID()
    var name: String = ""
    var symbol: String = "star.fill"
    var hex: String = "2B47C9"
    var daysData: Data = Data()
    var created: Date = Date()
    init(name: String, symbol: String, hex: String) {
        self.uid = UUID()
        self.name = name
        self.symbol = symbol
        self.hex = hex
        self.created = Date()
    }
    /// Дни, когда привычка выполнена, в формате yyyy-MM-dd
    var days: Set<String> {
        get { Set((try? JSONDecoder().decode([String].self, from: daysData)) ?? []) }
        set { daysData = (try? JSONEncoder().encode(Array(newValue).sorted())) ?? Data() }
    }
    func isDone(_ d: Date) -> Bool { days.contains(DF.iso(d)) }
    func toggle(_ d: Date) {
        var s = days
        let k = DF.iso(d)
        if s.contains(k) { s.remove(k) } else { s.insert(k) }
        days = s
    }
    var streak: Int {
        let s = days
        var n = 0
        var d = Date()
        if !s.contains(DF.iso(d)) { d = d.addingDays(-1) }
        while s.contains(DF.iso(d)) { n += 1; d = d.addingDays(-1) }
        return n
    }
}

struct GoalStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var done: Bool = false
}

@Model
final class LifeGoal {
    var uid: UUID = UUID()
    var name: String = ""
    var note: String = ""
    var deadline: Date? = nil
    var stepsData: Data = Data()
    var hex: String = "2B47C9"
    var created: Date = Date()
    init(name: String, deadline: Date?, hex: String) {
        self.uid = UUID()
        self.name = name
        self.deadline = deadline
        self.hex = hex
        self.created = Date()
    }
    var steps: [GoalStep] {
        get { (try? JSONDecoder().decode([GoalStep].self, from: stepsData)) ?? [] }
        set { stepsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var progress: Double {
        let s = steps
        return s.isEmpty ? 0 : Double(s.filter { $0.done }.count) / Double(s.count)
    }
}

@Model
final class LoyaltyCard {
    var uid: UUID = UUID()
    var name: String = ""
    var code: String = ""
    var format: String = "code128"
    var hex: String = "2B47C9"
    var note: String = ""
    var uses: Int = 0
    var created: Date = Date()
    init(name: String, code: String, format: String, hex: String) {
        self.uid = UUID()
        self.name = name
        self.code = code
        self.format = format
        self.hex = hex
        self.created = Date()
    }
}

enum Store {
    static let container: ModelContainer = {
        let schema = Schema([Tx.self, Account.self, Debt.self, Recurring.self, Goal.self,
                             ShopItem.self, Habit.self, LifeGoal.self, LoyaltyCard.self])
        let config = ModelConfiguration("Koshelek", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Не удалось открыть базу: \(error)")
        }
    }()
}
