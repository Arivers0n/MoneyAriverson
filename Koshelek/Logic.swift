import Foundation
import SwiftData

// MARK: - Долги

enum InstStatus {
    case ok, late, overdue, due, covered
    var title: String {
        switch self {
        case .ok: return "В срок"
        case .late: return "С опозданием"
        case .overdue: return "Просрочен"
        case .due: return "Предстоит"
        case .covered: return "Не нужен"
        }
    }
}

struct Inst: Identifiable {
    let debt: Debt
    let i: Int
    let n: Int
    let due: Date
    let amount: Double
    let plan: Double
    let st: InstStatus
    let paid: Paid?
    var id: String { debt.uid.uuidString + "-\(i)" }
    var isOpen: Bool { st == .due || st == .overdue }
}

extension Debt {
    var paidSum: Double {
        payments.values.reduce(0) { $0 + $1.amount } + extras.reduce(0) { $0 + $1.amount }
    }
    var remaining: Double { max(0, ((total - paidSum) * 100).rounded() / 100) }
    var isClosed: Bool { remaining <= 0 }
    var progress: Double { total > 0 ? min(1, paidSum / total) : 0 }

    func schedule() -> [Inst] {
        let count = max(1, n)
        let pay = payment > 0 ? payment : total
        let rem = remaining
        let today = Date().day0
        let paidMap = payments
        var out: [Inst] = []
        for i in 0..<count {
            var amt = pay
            if i == count - 1 && count > 1 {
                let last = ((total - pay * Double(count - 1)) * 100).rounded() / 100
                if last > 0 && last <= pay * 2 { amt = last }
            }
            let due = first.addingMonths(i).noon
            let p = paidMap[i]
            let st: InstStatus
            if let p = p { st = p.late ? .late : .ok }
            else if rem <= 0 { st = .covered }
            else if due.day0 < today { st = .overdue }
            else { st = .due }
            out.append(Inst(debt: self, i: i, n: count, due: due, amount: p?.amount ?? amt, plan: amt, st: st, paid: p))
        }
        return out
    }
    var nextInst: Inst? { schedule().first { $0.isOpen } }
    var lastOpenDue: Date? { schedule().filter { $0.isOpen }.last?.due }
}

func allInstallments(_ debts: [Debt]) -> [Inst] {
    debts.flatMap { $0.schedule() }.filter { $0.st != .covered }
}

/// Сколько месяцев и сколько сэкономит доплата X в месяц.
func extraPaymentEffect(_ d: Debt, extra x: Double) -> (months: Int, left: Int, saved: Double?)? {
    let p = d.payment
    let left = d.schedule().filter { $0.isOpen }.count
    guard x > 0, p > 0, left > 0 else { return nil }
    let r = d.rate / 1200
    if r > 0 {
        var bal = p * (1 - pow(1 + r, -Double(left))) / r
        var paid = 0.0, m = 0
        while bal > 0.5 && m < 1200 {
            let i = bal * r
            let pay = min(p + x, bal + i)
            bal = bal + i - pay
            paid += pay
            m += 1
        }
        return (m, left, max(0, p * Double(left) - paid))
    }
    return (Int(ceil(d.remaining / (p + x))), left, nil)
}

// MARK: - Счета

func balance(of acc: Account, txs: [Tx]) -> Double {
    var b = acc.start
    for t in txs {
        if t.accID == acc.uid { b += t.kind == .inc ? t.amount : -t.amount }
        if t.kind == .tr && t.toID == acc.uid { b += t.amount }
    }
    return b
}

// MARK: - Регулярные платежи

extension Recurring {
    func due(in month: Date) -> Date? {
        if yearly && self.month != month.monthNum { return nil }
        let m = month.startOfMonth
        let d = min(max(1, day), m.daysInMonth)
        return cal.date(byAdding: .day, value: d - 1, to: m)?.noon
    }
    func isRecorded(in month: Date, txs: [Tx]) -> Bool {
        txs.contains { $0.recID == uid && $0.date.sameMonth(month) }
    }
    var perMonth: Double { kind == .inc ? 0 : (yearly ? amount / 12 : amount) }
}

func pendingRecurring(_ recs: [Recurring], txs: [Tx]) -> [Recurring] {
    let now = Date()
    return recs.filter { r in
        guard let d = r.due(in: now) else { return false }
        return d.day0 <= now.day0 && !r.isRecorded(in: now, txs: txs)
    }
}

// MARK: - Статистика

struct MonthTotals: Identifiable {
    let month: Date
    let inc: Double
    let exp: Double
    let items: [Tx]
    var id: Date { month }
    var net: Double { inc - exp }
}

func totals(for month: Date, _ txs: [Tx]) -> MonthTotals {
    let items = txs.filter { $0.date.sameMonth(month) }
    let inc = items.filter { $0.kind == .inc }.reduce(0) { $0 + $1.amount }
    let exp = items.filter { $0.kind == .exp }.reduce(0) { $0 + $1.amount }
    return MonthTotals(month: month.startOfMonth, inc: inc, exp: exp, items: items)
}

struct CatSum: Identifiable {
    let cat: Category
    let sum: Double
    var id: String { cat.id }
}

func byCategory(_ items: [Tx]) -> [CatSum] {
    var d: [String: Double] = [:]
    for t in items where t.kind == .exp { d[t.cat, default: 0] += t.amount }
    return d.map { CatSum(cat: Catalog.cat($0.key), sum: $0.value) }.sorted { $0.sum > $1.sum }
}

func averageIncome(_ txs: [Tx]) -> Double {
    let now = Date()
    let vals = (0..<3).map { k -> Double in
        let m = now.addingMonths(-k)
        return txs.filter { $0.kind == .inc && $0.cat != "debtback" && $0.date.sameMonth(m) }.reduce(0) { $0 + $1.amount }
    }.filter { $0 > 0 }
    return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
}

func onTimeStreak(_ debts: [Debt]) -> Int {
    var done: [Inst] = []
    for d in debts where d.isOut {
        for x in d.schedule() {
            let counted: Bool = x.st == InstStatus.ok || x.st == InstStatus.late || x.st == InstStatus.overdue
            if counted { done.append(x) }
        }
    }
    done.sort { (a: Inst, b: Inst) -> Bool in a.due > b.due }
    var s = 0
    for x in done {
        if x.st == InstStatus.ok { s += 1 } else { break }
    }
    return s
}

// MARK: - Распознанные записи и сохранение

struct ParsedItem: Identifiable {
    enum Kind { case tx, debt, goal, rec, task, shop, habit }
    var isMoney: Bool { kind == .tx || kind == .debt || kind == .goal || kind == .rec }
    var id = UUID()
    var kind: Kind = .tx
    var type: TxKind = .exp
    var cat: String = "other"
    var amount: Double = 0
    var amountText: String = ""
    var date: Date = Date().noon
    var note: String = ""
    var debtID: UUID? = nil
    var goalID: UUID? = nil
    var sign: Double = 1
    var recID: UUID? = nil
    var on: Bool = true
    var accID: UUID? = nil
    var recDay: Int = 1
    var recYearly: Bool = false
    var recMonth: Int = 1
    var dueTime: Bool = false
    var hasDue: Bool = false
    var habitID: UUID? = nil
}

struct SaveResult {
    var count = 0
    var closedDebt: String? = nil
    var goalDone: String? = nil
    var firstTxDate: Date? = nil
    var summary: [String] = []
}

@MainActor
enum Saver {
    static func apply(_ items: [ParsedItem], account: UUID?, ctx: ModelContext) -> SaveResult {
        var res = SaveResult()
        let debts = ctx.live(Debt.self)
        let goals = ctx.live(Goal.self)
        for x in items where x.on && (x.amount > 0 || !x.isMoney) {
            let acc = x.accID ?? account
            switch x.kind {
            case .task, .shop, .habit:
                continue
            case .rec:
                let name = x.note.trimmingCharacters(in: .whitespaces).isEmpty ? Catalog.cat(x.cat).name : x.note
                ctx.insert(Recurring(name: name, amount: x.amount, kind: x.type, cat: Catalog.valid(x.cat, for: x.type),
                                     day: min(31, max(1, x.recDay)), yearly: x.recYearly, month: min(12, max(1, x.recMonth))))
                res.summary.append("регулярный «\(name)» \(Fmt.rubU(x.amount))")
            case .debt:
                guard let id = x.debtID, let d = debts.first(where: { $0.uid == id }) else { continue }
                let before = d.remaining
                if let ni = d.nextInst {
                    var p = d.payments
                    p[ni.i] = Paid(date: x.date.noon, amount: x.amount, late: x.date.day0 > ni.due.day0)
                    d.payments = p
                } else {
                    var e = d.extras
                    e.append(ExtraPay(date: x.date.noon, amount: x.amount))
                    d.extras = e
                }
                ctx.insert(Tx(kind: d.isOut ? .exp : .inc, amount: x.amount, cat: d.isOut ? "loans" : "debtback", note: d.name, date: x.date, accID: acc))
                if before > 0 && d.remaining <= 0 { res.closedDebt = d.name }
                res.summary.append("\(d.name) \(Fmt.rubU(x.amount))")
            case .goal:
                guard let id = x.goalID, let g = goals.first(where: { $0.uid == id }) else { continue }
                let before = g.saved
                var l = g.log
                l.append(GoalEntry(date: x.date.noon, amount: x.sign * x.amount))
                g.log = l
                if before < g.target && g.saved >= g.target { res.goalDone = g.name }
                res.summary.append("\(x.sign < 0 ? "из" : "в") копилку «\(g.name)» \(Fmt.rubU(x.amount))")
            case .tx:
                let t = Tx(kind: x.type, amount: x.amount, cat: Catalog.valid(x.cat, for: x.type), note: x.note.trimmingCharacters(in: .whitespaces), date: x.date, accID: acc, recID: x.recID)
                ctx.insert(t)
                if res.firstTxDate == nil { res.firstTxDate = x.date }
                let label = x.note.isEmpty ? Catalog.cat(x.cat).name : x.note
                res.summary.append("\(label) \(Fmt.rubU(x.amount))")
            }
            res.count += 1
        }
        ctx.commit()
        Notifier.reschedule(ctx: ctx)
        return res
    }
}
