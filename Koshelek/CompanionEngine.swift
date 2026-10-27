import Foundation

/// Операция в упрощённом виде — движок не зависит от SwiftData и считается одинаково на iOS и Android.
struct CompanionOp {
    let date: Date
    let isExpense: Bool
    let cat: String
    let amount: Double
    let counts: Bool
}

struct CompanionState {
    var mood: CompanionMood = .calm
    var level: Int = 1
    var xpInLevel: Int = 0
    var xpNeed: Int = 60
    var totalXP: Int = 0
    var treats: Int = 0
    var fed: Int = 0
    var phrase: String = ""
    var progress: Double { xpNeed > 0 ? min(1, Double(xpInLevel) / Double(xpNeed)) : 0 }
}

/// Настроение, опыт, уровни и угощения выводятся из операций — их не нужно синхронизировать отдельно.
enum CompanionEngine {
    static let epoch: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 27
        return cal.date(from: c)!.day0
    }()
    static let fallbackDailyLimit = 1500.0

    // Хранилище выбора на этом устройстве
    static var petID: String {
        get { let s = UserDefaults.standard.string(forKey: "pet.id") ?? ""; return CompanionCatalog.all.contains { $0.id == s } ? s : CompanionCatalog.defaultID }
        set { UserDefaults.standard.set(newValue, forKey: "pet.id") }
    }
    static var fedCount: Int {
        get { UserDefaults.standard.integer(forKey: "pet.fed") }
        set { UserDefaults.standard.set(newValue, forKey: "pet.fed") }
    }
    static var fedDay: Int {
        get { UserDefaults.standard.object(forKey: "pet.fedDay") as? Int ?? -1 }
        set { UserDefaults.standard.set(newValue, forKey: "pet.fedDay") }
    }

    static func dayIndex(_ d: Date) -> Int { daysBetween(epoch, d) }

    static func compute(ops: [CompanionOp], budget: Double, now: Date = Date(), pet: CompanionDef,
                        fed: Int = CompanionEngine.fedCount, fedDay: Int = CompanionEngine.fedDay) -> CompanionState {
        let today = dayIndex(now)
        let mine = ops.filter { dayIndex($0.date) >= 0 && dayIndex($0.date) <= today }
        let daysInMonth = max(1, now.daysInMonth)
        let dailyLimit = budget > 0 ? budget / Double(daysInMonth) : fallbackDailyLimit

        var spendByDay: [Int: Double] = [:]
        var catDays: [Int: Set<String>] = [:]
        for o in mine where o.isExpense && o.counts {
            let i = dayIndex(o.date)
            spendByDay[i, default: 0] += o.amount
            catDays[i, default: []].insert(o.cat)
        }

        // Опыт
        var xp = mine.count * 10 + fed * 15
        let closed = max(0, today)                      // закрытые дни: 0 ..< today
        var noSpend = 0, cafeFree = 0, funFree = 0
        let funCats: Set<String> = ["fun", "clothes", "gifts", "other"]
        for i in 0..<closed {
            if (spendByDay[i] ?? 0) == 0 { noSpend += 1 }
            let cs = catDays[i] ?? []
            if !cs.contains("cafe") { cafeFree += 1 }
            if cs.isDisjoint(with: funCats) { funFree += 1 }
        }
        xp += noSpend * 30
        var w = 0
        while (w + 1) * 7 <= closed {
            let sum = (w * 7..<(w + 1) * 7).reduce(0.0) { $0 + (spendByDay[$1] ?? 0) }
            if sum <= dailyLimit * 7 { xp += 50 }
            w += 1
        }

        // Уровень: на уровень N нужно 60·N опыта
        var level = 1, left = xp
        while left >= 60 * level { left -= 60 * level; level += 1 }

        // Угощения
        let earned = cafeFree / 3 + funFree / 7
        let treats = max(0, earned - fed)

        // Настроение
        let todaySpend = spendByDay[today] ?? 0
        let monthExp = mine.filter { $0.isExpense && $0.counts && $0.date.sameMonth(now) }.reduce(0.0) { $0 + $1.amount }
        let hour = cal.component(.hour, from: now)
        let opsToday = mine.contains { dayIndex($0.date) == today }
        let elapsed = max(1, closed)
        let ratio = Double(noSpend) / Double(elapsed)
        var mood: CompanionMood
        if (hour >= 23 || hour < 6) && !opsToday { mood = .sleepy }
        else if (budget > 0 && monthExp > budget) || todaySpend > dailyLimit * 2 { mood = .sad }
        else if todaySpend <= dailyLimit && closed >= 3 && ratio >= 0.35 { mood = .happy }
        else { mood = .calm }
        if fedDay == today {
            if mood == .sad { mood = .calm } else if mood == .calm { mood = .happy }
        }

        var st = CompanionState()
        st.mood = mood; st.level = level; st.xpInLevel = left; st.xpNeed = 60 * level
        st.totalXP = xp; st.treats = treats; st.fed = fed
        st.phrase = phrase(pet: pet, mood: mood, seed: today)
        return st
    }

    static func phrase(pet: CompanionDef, mood: CompanionMood, seed: Int) -> String {
        if mood == .sad && pet.id == "iskorka" { return "Ой, кажется, мы тратим слишком быстро. Давай поаккуратнее!" }
        let arr = pet.lines[mood] ?? []
        guard !arr.isEmpty else { return "" }
        return arr[abs(seed) % arr.count]
    }

    /// Угостить: нужен хотя бы один гостинец.
    @discardableResult
    static func feed(state: CompanionState, now: Date = Date()) -> Bool {
        guard state.treats > 0 else { return false }
        fedCount += 1
        fedDay = dayIndex(now)
        return true
    }
}

/// Голос питомца для ИИ.
enum AICoach {
    static func persona(pet: CompanionDef, mood: CompanionMood) -> String {
        if pet.id == CompanionCatalog.defaultID { return Advisor.persona }
        return Advisor.persona + "\n\nНа время этого разговора ты — питомец-напарник. \(pet.voice) Настроение сейчас: \(mood.title.lowercased()). Оставайся в образе, но цифры и советы давай точно и по делу; отвечай коротко."
    }
}
