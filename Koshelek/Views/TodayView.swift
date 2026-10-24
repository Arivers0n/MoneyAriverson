import SwiftUI
import SwiftData

struct TodayView: View {
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var tasks = TaskStore.shared
    @Query(sort: \Tx.date, order: .reverse) private var txs: [Tx]
    @Query private var debts: [Debt]
    @Query private var recs: [Recurring]
    @Query(sort: \Habit.created) private var habits: [Habit]
    @Query private var shop: [ShopItem]
    @AppStorage("budget") private var budget: Double = 0

    @State private var tip: String? = Advisor.cachedTip()
    @State private var tipLoading = false
    @State private var showChat = false
    @State private var showScan = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    moneyBlock
                    adviceBlock
                    paymentsBlock
                    tasksBlock
                    if !habits.isEmpty { habitsBlock }
                    shopBlock
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showChat) { AdvisorChat() }
            .task {
                tasks.refresh()
                await loadTip(force: false)
            }
            .refreshable {
                tasks.refresh()
                await loadTip(force: true)
            }
        }
    }

    // MARK: Шапка

    private var greeting: String {
        let h = cal.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DF.s(Date(), "EEEE, d MMMM").capitalizedFirst).font(.subheadline).foregroundStyle(.secondary)
                Text(greeting).font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Spacer()
            Button { router.show(.settings) } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 36, height: 36)
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: Деньги

    private var moneyBlock: some View {
        let todaySpent = txs.filter { $0.kind == .exp && $0.date.sameDay(Date()) }.reduce(0) { $0 + $1.amount }
        let month = totals(for: Date(), txs)
        let perDay: Double? = budget > 0 ? max(0, budget - month.exp) / Double(max(1, Date().daysInMonth - Date().dayNum + 1)) : nil
        return Button { router.tab = 1; router.wallet = 0 } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Сегодня потрачено").font(.subheadline).foregroundStyle(.secondary)
                    Text(Fmt.rubU(todaySpent)).font(.system(size: 40, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(perDay.map { "Можно ещё \(Fmt.rubU($0)) в день · за месяц \(Fmt.rubU(month.exp))" } ?? "За месяц \(Fmt.rubU(month.exp))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Советник

    private var adviceBlock: some View {
        let local = Advisor.insights(txs: txs, debts: debts, recs: recs, budget: budget)
        return VStack(alignment: .leading, spacing: 12) {
            BlockTitle(text: "Советник", symbol: "sparkles")
            if let tip {
                Text(tip).font(.body).fixedSize(horizontal: false, vertical: true)
            } else if tipLoading {
                HStack(spacing: 8) { ProgressView(); Text("Смотрю на ваши цифры…").foregroundStyle(.secondary) }
            } else if !Keychain.hasKey {
                Text("Добавьте ключ Claude API в настройках — и советник будет каждый день подсказывать, где вы теряете деньги и как быстрее закрыть долги.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(local.prefix(3)) { i in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: i.symbol).font(.subheadline).foregroundStyle(i.color).frame(width: 20)
                    Text(i.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { showChat = true } label: {
                HStack {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                    Text("Спросить советника")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    private func loadTip(force: Bool) async {
        guard Keychain.hasKey, !tipLoading else { return }
        if !force, tip != nil { return }
        tipLoading = true
        defer { tipLoading = false }
        if let t = try? await Advisor.dailyTip(ctx: ctx, force: force) { tip = t }
    }

    // MARK: Платежи

    @ViewBuilder private var paymentsBlock: some View {
        let soon = allInstallments(debts).filter { $0.isOpen && daysBetween(Date(), $0.due) <= 7 }.sorted { $0.due < $1.due }
        let pend = pendingRecurring(recs, txs: txs)
        if !soon.isEmpty || !pend.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                BlockTitle(text: "Платежи на неделе", symbol: "calendar")
                ForEach(soon.prefix(4)) { x in
                    Button { router.tab = 1; router.wallet = 1 } label: {
                        HStack {
                            Circle().fill(statusColor(x.st)).frame(width: 8, height: 8)
                            Text(x.debt.name).lineLimit(1)
                            Spacer()
                            Text(relDays(x.due).text).font(.footnote).foregroundStyle(x.st == .overdue ? Theme.exp : Color.secondary)
                            Text(Fmt.rubU(x.amount)).fontWeight(.medium)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(pend.prefix(3)) { r in
                    HStack {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8)
                        Text(r.name).lineLimit(1)
                        Spacer()
                        Text("пора записать").font(.footnote).foregroundStyle(.secondary)
                        Text(Fmt.rubU(r.amount)).fontWeight(.medium)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Задачи

    private var tasksBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            BlockTitle(text: "Дела на сегодня", symbol: "checklist")
            if !tasks.authorized {
                Button {
                    Task { await tasks.requestAccess() }
                } label: {
                    Text(tasks.denied ? "Доступ к Напоминаниям выключен: Настройки → Лад → Напоминания" : "Показывать задачи из «Напоминаний»")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(tasks.denied)
            } else if tasks.today.isEmpty {
                Text("На сегодня дел нет. Скажите, например: «завтра в 10 позвонить в банк».")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(tasks.today.prefix(6)) { t in TaskRow(item: t) }
                if tasks.today.count > 6 {
                    Button("Ещё \(tasks.today.count - 6)") { router.tab = 2 }.font(.subheadline)
                }
            }
        }
    }

    // MARK: Привычки

    private var habitsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlockTitle(text: "Привычки", symbol: "flame")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(habits) { h in HabitBubble(habit: h) }
                }
            }
        }
    }

    // MARK: Покупки

    @ViewBuilder private var shopBlock: some View {
        let left = shop.filter { !$0.done }
        if !left.isEmpty {
            Button { router.tab = 2; router.life = 1 } label: {
                HStack {
                    BlockTitle(text: "Купить", symbol: "cart")
                    Spacer()
                    Text(left.prefix(3).map { $0.name }.joined(separator: ", ") + (left.count > 3 ? " и ещё \(left.count - 3)" : ""))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Скан

    private func startScan() {
        guard Keychain.hasKey else { router.say("Для скана нужен ключ Claude API"); router.show(.settings); return }
        showScan = true
    }

    private func scan(_ imgs: [Data]) {
        router.busy = "Claude читает чек…"
        Task {
            defer { router.busy = nil }
            do {
                let items = try await Brain.parseReceipts(imgs, ctx: ctx)
                if items.isEmpty { router.say("Не нашёл операций на изображении"); return }
                router.show(.review(ReviewPayload(items: items, subtitle: "Найдено \(items.count) — проверьте перед добавлением")))
            } catch { router.say(error.localizedDescription) }
        }
    }
}

// MARK: - Общие элементы

struct BlockTitle: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(TightLabel())
    }
}

struct TaskRow: View {
    let item: TaskStore.Item
    @State private var checked = false
    var body: some View {
        Button {
            withAnimation(.snappy) { checked = true }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { TaskStore.shared.complete(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Theme.inc : (item.listColor.map { Color(cgColor: $0) } ?? .secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
                    if let d = item.due {
                        Text(dueText(d)).font(.footnote).foregroundStyle(item.isOverdue ? Theme.exp : Color.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    func dueText(_ d: Date) -> String {
        let day: String
        let n = daysBetween(Date(), d)
        if n == 0 { day = "сегодня" } else if n == 1 { day = "завтра" } else if n == -1 { day = "вчера" } else { day = DF.short(d) }
        return item.hasTime ? "\(day), \(DF.s(d, "HH:mm"))" : day
    }
}

struct HabitBubble: View {
    @Environment(\.modelContext) private var ctx
    let habit: Habit
    var body: some View {
        let done = habit.isDone(Date())
        let color = Color(hex: habit.hex)
        Button {
            withAnimation(.snappy) { habit.toggle(Date()) }
            try? ctx.save()
            UIImpactFeedbackGenerator(style: done ? .light : .medium).impactOccurred()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(done ? color : color.opacity(0.12)).frame(width: 58, height: 58)
                    Image(systemName: habit.symbol).font(.title3.weight(.semibold)).foregroundStyle(done ? .white : color)
                }
                Text(habit.name).font(.caption).lineLimit(1).frame(maxWidth: 70)
                Text(habit.streak > 0 ? "\(habit.streak) дн." : " ").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
