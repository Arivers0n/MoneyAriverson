import Foundation
import SwiftData
import UIKit
import WidgetKit

/// Хозяин дизайнов виджетов в приложении: хранит конфиги, отдаёт их расширению через общий контейнер
/// и обновляет снимок данных (бюджет, баланс, копилки, платёж, напарник) после изменений.
/// Выбор чисел — в WidgetSnapshotBuilder (чистый Swift), здесь только сбор данных, хранение и доставка.
/// Дизайны виджетов лежат на устройстве (как оформление) и в синхронизацию не попадают.
@MainActor
final class WidgetStore: ObservableObject {
    static let shared = WidgetStore()

    private static let key = "widgets.configs"
    private static let petKey = "widgets.petID"

    @Published private(set) var configs: WidgetConfigSet
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastSnapshot: WidgetSnapshot?

    private var task: Task<Void, Never>?

    /// Подпись дала право на общую группу: без неё виджет не увидит ни дизайн, ни данные.
    var hasAccess: Bool { WidgetShared.hasAccess }

    private init() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: Self.key), let set = try? JSONDecoder().decode(WidgetConfigSet.self, from: data) {
            configs = set.validated()
        } else {
            let fresh = WidgetConfigSet.makeDefault()
            configs = fresh
            if let data = try? JSONEncoder().encode(fresh) { ud.set(data, forKey: Self.key) }
        }
        deliverConfigs()
    }

    // MARK: - Правки из конструктора

    func design(slot id: Int, family: WidgetFamilyKind) -> WidgetDesign {
        configs.slot(id)?.design(for: family) ?? WidgetPresets.make(.kopilka, for: family)
    }

    func update(_ design: WidgetDesign, inSlot id: Int) {
        var next = configs
        next.update(design, inSlot: id)
        store(next)
    }

    func rename(slot id: Int, to name: String) {
        var next = configs
        guard let i = next.slots.firstIndex(where: { $0.id == id }) else { return }
        next.slots[i].name = name
        store(next.validated())
    }

    private func store(_ set: WidgetConfigSet) {
        configs = set
        if let data = try? JSONEncoder().encode(set) { UserDefaults.standard.set(data, forKey: Self.key) }
        deliverConfigs()
    }

    private func deliverConfigs() {
        WidgetShared.writeConfigs(configs)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Снимок данных

    /// Откладывает пересчёт на секунду: серия операций подряд даёт один снимок.
    func scheduleRefresh() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh(now: Date = Date()) {
        let ctx = Store.container.mainContext
        let txs = ctx.live(Tx.self)
        let accounts = ctx.live(Account.self)
        let goals = ctx.live(Goal.self)
        let debts = ctx.live(Debt.self)
        let recs = ctx.live(Recurring.self)

        let ud = UserDefaults.standard
        let budget = ud.double(forKey: "budget")
        let ap = Appearance.shared

        // Напарник: те же правила, что на главном экране
        let pet = CompanionCatalog.def(CompanionEngine.petID)
        let ops = txs.filter { $0.kind != .tr }.map {
            CompanionOp(date: $0.date, isExpense: $0.kind == .exp, cat: $0.cat, amount: $0.amount, counts: countsInTotals($0))
        }
        let state = CompanionEngine.compute(ops: ops, budget: budget, pet: pet, fed: CompanionEngine.fedCount,
                                            fedDay: CompanionEngine.fedDay)

        let lite = txs.filter { $0.kind != .tr }.map {
            WidgetTxLite(date: $0.date, isExpense: $0.kind == .exp, isIncome: $0.kind == .inc,
                         amount: $0.amount, cat: $0.cat, counts: countsInTotals($0))
        }
        let total: Double? = accounts.isEmpty ? nil : accounts.reduce(0) { $0 + balance(of: $1, txs: txs) }
        let firstName = SyncEngine.shared.userName.split(separator: " ").first.map(String.init) ?? ""

        var builder = WidgetSnapshotBuilder()
        builder.firstWeekday = ap.firstWeekday
        var snap = builder.make(
            txs: lite, budget: budget, balance: total, saved: Savings.totalSaved(goals), goal: pickGoal(goals),
            payment: nextPayment(debts: debts, recs: recs, txs: txs, now: now),
            level: state.level, levelFraction: state.progress, mood: state.mood.rawValue,
            userName: firstName, petName: pet.name, phrase: state.phrase, hideAmounts: ap.hideAmounts,
            catName: { Catalog.cat($0).name }, now: now)
        snap.hasPetImage = syncPetImage(pet)

        lastSnapshot = snap
        lastRefresh = now
        guard WidgetShared.hasAccess else { return }
        WidgetShared.writeSnapshot(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Самая «близкая к цели» из незавершённых копилок; если таких нет — первая.
    private func pickGoal(_ goals: [Goal]) -> WidgetGoal? {
        func fraction(_ g: Goal) -> Double { g.target > 0 ? min(1, g.saved / g.target) : 0 }
        let open = goals.filter { $0.target > 0 && $0.saved < $0.target }
        guard let g = open.max(by: { fraction($0) < fraction($1) }) ?? goals.first else { return nil }
        return WidgetGoal(name: g.name, fraction: fraction(g))
    }

    /// Ближайший платёж: открытая выплата по кредиту или регулярный платёж этого месяца.
    private func nextPayment(debts: [Debt], recs: [Recurring], txs: [Tx], now: Date) -> WidgetPayment? {
        var best: WidgetPayment?
        func consider(_ p: WidgetPayment) {
            if let b = best, b.due <= p.due { return }
            best = p
        }
        for i in allInstallments(debts) where i.isOpen && i.debt.isOut {
            consider(WidgetPayment(name: i.debt.name, amount: i.amount, due: i.due.day0))
        }
        for r in recs where r.kind == .exp {
            guard let d = r.due(in: now), !r.isRecorded(in: now, txs: txs) else { continue }
            consider(WidgetPayment(name: r.name, amount: r.amount, due: d.day0))
        }
        return best
    }

    /// Кладёт уменьшенную картинку питомца в общий канал (расширению не нужен весь каталог картинок).
    private func syncPetImage(_ pet: CompanionDef) -> Bool {
        guard WidgetShared.hasAccess else { return false }
        let ud = UserDefaults.standard
        if ud.string(forKey: Self.petKey) == pet.id, WidgetShared.readPet() != nil { return true }
        guard let image = UIImage(named: pet.asset) else {
            WidgetShared.removePet()
            return false
        }
        let longest = max(image.size.width, image.size.height)
        let k = min(1, 320 / max(longest, 1))
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = scaled.pngData(), WidgetShared.writePet(png) else { return false }
        ud.set(pet.id, forKey: Self.petKey)
        return true
    }
}
