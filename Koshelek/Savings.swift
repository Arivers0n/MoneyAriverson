import Foundation
import SwiftData

@MainActor
enum Savings {
    /// Автоправила копилок: процент с дохода и округление трат. Возвращает короткие подписи для подсказки.
    static func applyRules(to t: Tx, ctx: ModelContext) -> [String] {
        guard t.amount > 0 else { return [] }
        var notes: [String] = []
        let goals = ctx.live(Goal.self).filter { $0.target <= 0 || $0.saved < $0.target }
        if t.kind == .inc && t.cat != "debtback" {
            for g in goals where g.autoPercent > 0 {
                let v = (t.amount * g.autoPercent / 100).rounded()
                guard v > 0 else { continue }
                var l = g.log
                l.append(GoalEntry(date: t.date, amount: v))
                g.log = l
                notes.append("\(Fmt.rubU(v)) → «\(g.name)»")
            }
        }
        if t.kind == .exp && !["savings", "loans"].contains(t.cat) {
            for g in goals where g.roundUp > 0 {
                let step = Double(g.roundUp)
                let diff = (ceil(t.amount / step) * step - t.amount).rounded()
                guard diff > 0 else { continue }
                var l = g.log
                l.append(GoalEntry(date: t.date, amount: diff))
                g.log = l
                notes.append("+\(Fmt.rubU(diff)) в «\(g.name)»")
            }
        }
        return notes
    }

    /// Сколько в среднем откладывается в копилку в месяц (за последние 90 дней).
    static func monthlyPace(_ g: Goal) -> Double {
        let from = Date().addingDays(-90)
        let sum = g.log.filter { $0.date >= from }.reduce(0) { $0 + $1.amount }
        let span = max(1.0, min(3.0, Date().timeIntervalSince(max(from, g.created)) / (30 * 86400)))
        return max(0, sum / span)
    }

    struct Forecast {
        let text: String
        let good: Bool
    }

    static func forecast(_ g: Goal) -> Forecast? {
        let left = g.target - g.saved
        guard g.target > 0, left > 0 else { return nil }
        let pace = monthlyPace(g)
        if let dl = g.deadline {
            let months = max(1, monthsBetween(Date(), dl) + 1)
            let need = left / Double(months)
            if dl.day0 < Date().day0 { return Forecast(text: "Срок прошёл — осталось \(Fmt.rubU(left))", good: false) }
            if pace >= need * 0.95 { return Forecast(text: "Успеваете к \(DF.short(dl)): откладываете ~\(Fmt.rubU(pace)) в месяц", good: true) }
            return Forecast(text: "Чтобы успеть к \(DF.short(dl)), нужно \(Fmt.rubU(need)) в месяц" + (pace > 0 ? " (сейчас ~\(Fmt.rubU(pace)))" : ""), good: false)
        }
        guard pace > 0 else { return Forecast(text: "Пополните копилку — и я посчитаю, когда наберётся сумма", good: true) }
        let months = Int(ceil(left / pace))
        let date = Date().addingMonths(months)
        return Forecast(text: "При текущем темпе — к \(DF.s(date, "LLLL yyyy")) (~\(Fmt.rubU(pace)) в месяц)", good: true)
    }

    /// Рекомендуемая подушка безопасности: 3 месяца средних расходов.
    static func cushionTarget(_ txs: [Tx]) -> Double {
        let now = Date()
        let vals = (1...3).map { k -> Double in totals(for: now.addingMonths(-k), txs).exp }.filter { $0 > 0 }
        let avg = vals.isEmpty ? totals(for: now, txs).exp : vals.reduce(0, +) / Double(vals.count)
        let t = avg * 3
        return t > 0 ? (t / 1000).rounded(.up) * 1000 : 0
    }

    static func totalSaved(_ goals: [Goal]) -> Double { goals.reduce(0) { $0 + $1.saved } }

    static func savedThisMonth(_ goals: [Goal]) -> Double {
        goals.flatMap { $0.log }.filter { $0.date.sameMonth(Date()) }.reduce(0) { $0 + $1.amount }
    }
}
