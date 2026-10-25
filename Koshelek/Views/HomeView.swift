import SwiftUI
import SwiftData

/// Главный экран из настраиваемых блоков. Удержание — режим редактирования, как в Пункте управления.
struct HomeView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var sync: SyncEngine
    @ObservedObject private var layout = HomeLayout.shared
    @ObservedObject private var ap = Appearance.shared
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Tx.date, order: .reverse) private var qTxs: [Tx]
    private var allTxs: [Tx] { qTxs.live }
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }
    @Query private var qDebts: [Debt]
    private var debts: [Debt] { qDebts.live }
    @Query private var qRecs: [Recurring]
    private var recs: [Recurring] { qRecs.live }

    @State private var month = Date().startOfMonth
    @State private var pressStart: Date?
    @State private var micPressed = false
    @State private var reveal = false
    @State private var showAdd = false

    private var txs: [Tx] {
        guard let a = router.accFilter else { return allTxs }
        return allTxs.filter { $0.accID == a || $0.toID == a }
    }
    private var monthTxs: [Tx] { txs.filter { $0.date.sameMonth(month) } }
    private var masked: Bool { ap.hideAmounts && !reveal }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar.padding(.top, 4)
                VStack(spacing: layout.editing ? 18 : (ap.compact ? 16 : 22)) {
                    ForEach(layout.order, id: \.self) { id in
                        block(id)
                            .modifier(EditableBlock(editing: layout.editing, title: layout.block(id)?.title ?? "") { layout.remove(id) })
                    }
                    if layout.editing { editTail }
                }
                .padding(.top, 28)
                .animation(.snappy, value: layout.order)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .refreshable { await sync.sync(ctx: ctx) }
        .safeAreaInset(edge: .bottom) { layout.editing ? AnyView(editBar) : AnyView(bottomButtons) }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.7).onEnded { _ in
                guard !layout.editing else { return }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation(.snappy) { layout.editing = true }
            }
        )
        .sheet(isPresented: $showAdd) { AddBlockSheet() }
    }

    // MARK: Блоки

    @ViewBuilder private func block(_ id: String) -> some View {
        switch id {
        case "summary": hero
        case "insights": insightsButton
        case "attention": attention
        case "budgets": BudgetsBlock(txs: allTxs)
        case "goals": GoalsBlock()
        case "payments": PaymentsBlock(debts: debts, recs: recs, txs: allTxs)
        case "categories": CategoriesBlock(txs: monthTxs)
        case "accounts": AccountsBlock(accs: accs, txs: allTxs)
        case "feed": feed
        default: EmptyView()
        }
    }

    // MARK: Верхняя панель

    private var accountTitle: String {
        if let a = router.accFilter, let acc = accs.first(where: { $0.uid == a }) { return acc.name }
        if let s = sync.currentSpace, !s.personal { return s.name }
        return accs.isEmpty ? "Кошелёк" : "Все счета"
    }

    private var accountAmount: String {
        if masked { return "••••• ₽" }
        if let a = router.accFilter, let acc = accs.first(where: { $0.uid == a }) { return Fmt.rub(balance(of: acc, txs: allTxs)) }
        if !accs.isEmpty { return Fmt.rub(accs.reduce(0) { $0 + balance(of: $1, txs: allTxs) }) }
        return Fmt.rub(allTxs.reduce(0) { $0 + $1.signedAmount })
    }

    private var topBar: some View {
        let alert = allInstallments(debts).contains { $0.st == .overdue && $0.debt.isOut } || !pendingRecurring(recs, txs: allTxs).isEmpty
        let items: [GlassIconGroup.Item] = layout.top.compactMap { id in
            guard let b = HomeLayout.topButtons.first(where: { $0.id == id }) else { return nil }
            return .init(symbol: b.symbol, dot: id == "payments" && alert) { open(id) }
        }
        return HStack(spacing: 10) {
            AccountPill(title: accountTitle, amount: accountAmount) { router.show(.accounts) }
                .layoutPriority(1)
            Spacer(minLength: 0)
            if layout.editing {
                Button { router.show(.customize) } label: {
                    Label("Кнопки", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(height: 46).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glass(Capsule(), interactive: true)
            } else if !items.isEmpty {
                GlassIconGroup(items: items)
            }
            GlassCircle(symbol: "gearshape") { router.show(.settings) }
        }
    }

    private func open(_ id: String) {
        switch id {
        case "search": router.show(.search)
        case "stats": router.show(.stats)
        case "payments": router.show(.payments)
        case "budgets": router.show(.goals(0))
        case "goals": router.show(.goals(1))
        case "insights": router.show(.insights)
        case "export": router.show(.stats)
        default: break
        }
    }

    // MARK: Итог месяца

    private var hero: some View {
        let t = totals(for: month, txs)
        let (label, value): (String, Double) = {
            switch ap.bigNumber {
            case "exp": return ("Потрачено за", t.exp)
            case "inc": return ("Доход за", t.inc)
            default: return ("Итог за", t.net)
            }
        }()
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(label).foregroundStyle(.secondary)
                MonthPill(month: $month)
                if !month.sameMonth(Date()) {
                    Button { withAnimation(.snappy) { month = Date().startOfMonth } } label: {
                        Image(systemName: "arrow.uturn.backward.circle").font(.title3).foregroundStyle(.secondary)
                    }
                }
            }
            Text(masked ? "••••• ₽" : Fmt.rub(value))
                .font(.system(size: ap.compact ? 52 : 64, weight: .bold))
                .minimumScaleFactor(0.4).lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .onTapGesture { if ap.hideAmounts { withAnimation { reveal.toggle() } } }
            HStack(spacing: 22) {
                FlowChip(symbol: "arrow.down.left", color: Theme.inc, text: masked ? "•••" : Fmt.rubU(t.inc), textColor: Theme.inc)
                FlowChip(symbol: "arrow.up.right", color: Theme.warn, text: masked ? "•••" : Fmt.rubU(t.exp), textColor: .primary)
            }
        }
    }

    private var insightsButton: some View {
        Button { router.show(.insights) } label: {
            Label("Инсайты", systemImage: "sparkle")
                .font(.body.weight(.medium))
                .padding(.horizontal, 18).frame(height: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(Capsule(), interactive: true)
    }

    // MARK: Что требует внимания

    @ViewBuilder private var attention: some View {
        let soon = allInstallments(debts).filter { $0.debt.isOut && ($0.st == .overdue || ($0.st == .due && daysBetween(Date(), $0.due) <= 3)) }
            .sorted { $0.due < $1.due }
        let pend = pendingRecurring(recs, txs: allTxs)
        if let x = soon.first {
            AttentionPill(color: x.st == .overdue ? Theme.exp : Theme.warn,
                          text: "\(x.debt.name) · \(Fmt.rubU(x.amount)) · \(relDays(x.due).text)") { router.show(.payments) }
        } else if !pend.isEmpty {
            AttentionPill(color: Theme.accent,
                          text: pend.count == 1 ? "Записать «\(pend[0].name)» · \(Fmt.rubU(pend[0].amount))" : "Записать регулярные платежи · \(pend.count)") {
                let items = pend.map { r in
                    ParsedItem(type: r.kind == .inc ? .inc : .exp, cat: r.cat, amount: r.amount, amountText: Fmt.input(r.amount),
                               date: r.due(in: Date()) ?? Date().noon, note: r.name, recID: r.uid)
                }
                router.show(.review(ReviewPayload(items: items, subtitle: "Регулярные платежи этого месяца")))
            }
        } else if layout.editing {
            AttentionPill(color: Theme.inc, text: "Здесь появится ближайший платёж") {}
        }
    }

    // MARK: Лента

    @ViewBuilder private var feed: some View {
        if monthTxs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                Text(allTxs.isEmpty ? "Скажите, что купили" : "В этом месяце пусто").font(.headline)
                Text("Нажмите на микрофон и говорите как обычно: «кофе 250, такси 400». Удержите экран, чтобы настроить его под себя.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.top, 30)
        } else {
            TxGroupedList(txs: monthTxs, accounts: accs)
                .allowsHitTesting(!layout.editing)
        }
    }

    // MARK: Режим редактирования

    private var editTail: some View {
        Button { showAdd = true } label: {
            Label("Добавить элемент", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity).frame(height: 54)
                .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(.secondary.opacity(0.5)))
    }

    private var editBar: some View {
        HStack(spacing: 10) {
            Button { router.show(.customize) } label: {
                Label("Порядок и кнопки", systemImage: "arrow.up.arrow.down").font(.body.weight(.medium))
                    .padding(.horizontal, 18).frame(height: 52).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glass(Capsule(), interactive: true)
            Button { withAnimation(.snappy) { layout.editing = false } } label: {
                Text("Готово").font(.body.weight(.semibold)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 26).frame(height: 52)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 6)
    }

    // MARK: Кнопки снизу

    private var bottomButtons: some View {
        HStack(spacing: 18) {
            if layout.showScan { GlassCircle(symbol: "viewfinder", size: 60) { router.scanRequest += 1 } }
            ZStack {
                Image(systemName: "mic")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 78, height: 78)
                    .contentShape(Circle())
            }
            .glass(Circle(), interactive: true)
            .scaleEffect(micPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: micPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressStart == nil {
                            pressStart = Date(); micPressed = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            router.startVoice()
                        }
                    }
                    .onEnded { _ in
                        if let s = pressStart, Date().timeIntervalSince(s) > 0.45 { router.voiceRelease += 1 }
                        pressStart = nil; micPressed = false
                    }
            )
            .accessibilityLabel("Сказать голосом")
            .accessibilityAddTraits(.isButton)
            if layout.showPlus { GlassCircle(symbol: "plus", size: 60) { router.show(.newTx) } }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }
}

/// Блок в режиме редактирования: покачивается и показывает кнопку «−».
struct EditableBlock: ViewModifier {
    let editing: Bool
    let title: String
    let onRemove: () -> Void
    @State private var wobble = false
    func body(content: Content) -> some View {
        content
            .padding(editing ? 10 : 0)
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRemove()
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .glass(Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -8)
                    .accessibilityLabel("Убрать «\(title)»")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .rotationEffect(.degrees(editing ? (wobble ? 0.5 : -0.5) : 0))
            .onChange(of: editing) { _, on in
                if on {
                    withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { wobble = true }
                } else {
                    withAnimation(.default) { wobble = false }
                }
            }
            .onAppear {
                if editing { withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { wobble = true } }
            }
    }
}

struct FlowChip: View {
    let symbol: String
    let color: Color
    let text: String
    let textColor: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.2), in: Circle())
            Text(text).font(.title3.weight(.medium)).foregroundStyle(textColor)
                .contentTransition(.numericText())
        }
    }
}

struct AttentionPill: View {
    let color: Color
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).font(.footnote.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).frame(height: 34)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Добавление скрытых блоков.
struct AddBlockSheet: View {
    @ObservedObject private var layout = HomeLayout.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if layout.hidden.isEmpty {
                        EmptyState(symbol: "checkmark.circle", title: "Всё уже на экране", text: "Уберите блок кнопкой «−», чтобы он появился здесь.")
                    }
                    ForEach(layout.hidden) { b in
                        Button {
                            layout.add(b.id)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if layout.hidden.isEmpty { dismiss() }
                        } label: {
                            RowCard {
                                CategoryTile(symbol: b.symbol, color: Theme.accent, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.title).font(.body.weight(.semibold))
                                    Text(b.hint).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.inc)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Backdrop())
            .navigationTitle("Добавить элемент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
