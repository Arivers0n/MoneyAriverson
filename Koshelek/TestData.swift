import SwiftUI
import SwiftData

/// Режим проверки интерфейса на худших данных.
/// Данные живут в отдельной базе в памяти: настоящие операции не трогаются,
/// синхронизация и уведомления в этом режиме выключены.
@MainActor
final class TestData: ObservableObject {
    static let shared = TestData()
    /// Флаг для кода вне главного потока (уведомления, синхронизация).
    nonisolated(unsafe) static var isActive = false

    enum Mode: String, CaseIterable, Identifiable {
        case worst, empty, one, huge
        var id: String { rawValue }
        var title: String {
            switch self {
            case .worst: return "Худший"
            case .empty: return "Пусто"
            case .one: return "Один"
            case .huge: return "1500"
            }
        }
    }

    /// Показывать ли переключатель (включается 5 нажатиями на версию в настройках).
    @Published var unlocked = UserDefaults.standard.bool(forKey: "dev.unlocked") {
        didSet { UserDefaults.standard.set(unlocked, forKey: "dev.unlocked") }
    }
    @Published private(set) var mode: Mode?
    private(set) var container: ModelContainer?

    var active: Bool { mode != nil }
    var context: ModelContext { (container ?? Store.container).mainContext }

    func set(_ m: Mode?) {
        guard m != mode else { return }
        if let m {
            let schema = Schema([Tx.self, Account.self, Debt.self, Recurring.self, Goal.self,
                                 ShopItem.self, Habit.self, LifeGoal.self, LoyaltyCard.self])
            let cfg = ModelConfiguration("KoshelekTest", schema: schema, isStoredInMemoryOnly: true)
            guard let c = try? ModelContainer(for: schema, configurations: [cfg]) else { return }
            Self.fill(c.mainContext, m)
            container = c
        } else {
            container = nil
        }
        RollingAmount.counted = false
        TestData.isActive = m != nil
        mode = m
    }

    // MARK: Наборы данных

    private static func fill(_ ctx: ModelContext, _ m: Mode) {
        let space = Space.current
        func put<T: Synced>(_ x: T) { x.space = space; x.dirty = false; ctx.insert(x) }
        let now = Date()
        func day(_ n: Int) -> Date { now.addingDays(-n) }

        switch m {
        case .empty:
            break

        case .one:
            let a = Account(name: "Карта", start: 1, hex: "2E8B57"); put(a)
            put(Tx(kind: .exp, amount: 1, cat: "other", note: "", date: now, accID: a.uid))
            let g = Goal(name: "Цель", target: 1, deadline: nil, hex: "2B47C9")
            g.log = [GoalEntry(date: now, amount: 1)]; put(g)

        case .worst:
            // Реалистичные, но неудобные значения: длинные названия, огромные и крошечные суммы, копейки, эмодзи
            let a1 = Account(name: "Сбербанк · Кредитная СберКарта Gold с кэшбэком", start: 2_480_350.55, hex: "2E8B57"); put(a1)
            let a2 = Account(name: "Т-Банк Black", start: -184_920.4, hex: "16201C"); put(a2)
            let a3 = Account(name: "Наличные", start: 0, hex: "D9822B"); put(a3)
            put(Tx(kind: .exp, amount: 1_249_990, cat: "home", note: "Ремонт квартиры на Красном проспекте — плитка, ламинат, межкомнатные двери и сантехника", date: day(0), accID: a1.uid))
            put(Tx(kind: .exp, amount: 12_345.67, cat: "food", note: "Ашан", date: day(0), accID: a2.uid))
            put(Tx(kind: .exp, amount: 1, cat: "other", note: "😀🎉 Подарок коллеге", date: day(0), accID: a3.uid))
            put(Tx(kind: .tr, amount: 50_000, cat: "other", note: "", date: day(1), accID: a1.uid, toID: a2.uid))
            put(Tx(kind: .inc, amount: 150_000, cat: "salary", note: "Зарплата за сентябрь (аванс + окончательный расчёт)", date: day(2), accID: a1.uid))
            put(Tx(kind: .exp, amount: 99_999_999, cat: "fun", note: "Ошибка ввода: лишние девятки", date: day(3), accID: a1.uid))
            put(Tx(kind: .exp, amount: 3_400, cat: "transport", note: "Такси", date: day(3), accID: a3.uid))
            put(Tx(kind: .exp, amount: 0.01, cat: "subs", note: "Проверка карты", date: day(4), accID: a2.uid))
            for k in 0..<20 where cal.component(.weekday, from: day(k)) != 1 {
                put(Tx(kind: .inc, amount: 500, cat: "side", note: "Суточные", date: day(k), accID: a3.uid))
            }
            for k in [0, 1, 2, 5, 6] { put(Tx(kind: .exp, amount: 250, cat: "cafe", note: "Кофе", date: day(k), accID: a2.uid)) }
            let d1 = Debt(type: .credit, dirIn: false, name: "Ипотека ВТБ — квартира в ЖК «Новые Черёмушки», 2-комнатная",
                          lender: "Банк ВТБ (публичное акционерное общество)", total: 8_750_000, payment: 48_760.13, n: 240,
                          first: now.addingMonths(-14).addingDays(-1), rate: 17.9)
            put(d1)
            let d2 = Debt(type: .person, dirIn: true, name: "Jo", lender: "", total: 300, payment: 300, n: 1, first: day(40), rate: 0)
            put(d2)
            let g1 = Goal(name: "Отпуск на Алтае всей семьёй летом 2027 года", target: 12_500_000, deadline: now.addingMonths(20), hex: "8E5BD8")
            g1.log = [GoalEntry(date: day(10), amount: 13_100_000)]; put(g1)
            let g2 = Goal(name: "Ж", target: 0, deadline: nil, hex: "D9822B"); put(g2)
            put(Recurring(name: "Подписка Яндекс Плюс Мульти с Амедиатекой и Букмейтом", amount: 1_199, kind: .exp, cat: "subs", day: 31, yearly: false, month: 1))
            put(Recurring(name: "Зарплата", amount: 150_000, kind: .inc, cat: "salary", day: cal.component(.day, from: now), yearly: false, month: 1))

        case .huge:
            let a = Account(name: "Основная карта", start: 0, hex: "2E8B57"); put(a)
            let cats = ["food", "cafe", "transport", "home", "subs", "phone", "health", "clothes", "fun", "gifts", "other"]
            let notes = ["", "Пятёрочка", "Кофе", "Такси", "Аптека", "Обед", "Wildberries", "Ozon", "Бензин", "Кино"]
            var rng = SystemRandomNumberGenerator()
            for i in 0..<1500 {
                let d = now.addingDays(-Int.random(in: 0..<180, using: &rng))
                let c = cats[i % cats.count]
                put(Tx(kind: .exp, amount: Double(Int.random(in: 50...4000, using: &rng)), cat: c, note: notes[i % notes.count], date: d, accID: a.uid))
            }
            for k in 0..<6 { put(Tx(kind: .inc, amount: 150_000, cat: "salary", note: "Зарплата", date: now.startOfMonth.addingMonths(-k).addingDays(9), accID: a.uid)) }
        }
        try? ctx.save()
    }
}

/// Плашка внизу экрана: «Демо / Худший / Пусто / Один / 1500». Только для проверки, в обычной работе не видна.
struct TestDataSwitch: View {
    @ObservedObject var td = TestData.shared
    var body: some View {
        if td.unlocked {
            HStack(spacing: 2) {
                seg("Мои", td.mode == nil) { td.set(nil) }
                ForEach(TestData.Mode.allCases) { m in seg(m.title, td.mode == m) { td.set(m) } }
                Button { td.set(nil); td.unlocked = false } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).frame(width: 26, height: 28)
                }
                .foregroundStyle(.secondary)
            }
            .padding(3)
            .background(Color(.systemGray5), in: Capsule())
            .font(.system(size: 12, weight: .semibold))
            .padding(.bottom, 2)
        }
    }
    private func seg(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).padding(.horizontal, 9).frame(height: 28)
                .background(on ? Color(.systemBackground) : .clear, in: Capsule())
                .foregroundStyle(on ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
