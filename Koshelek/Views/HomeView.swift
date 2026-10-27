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

    @State private var pull: CGFloat = 0
    @State private var pullState: PullState = .idle
    @State private var pullTick = 0
    @State private var heroBump = false
    @State private var refreshStart = Date.distantPast

    /// Шапка (итог месяца) закреплена, если блок «Итог» есть на экране и не идёт редактирование.
    private var pinHero: Bool { !layout.editing && layout.order.contains("summary") }
    private var scrollOrder: [String] { pinHero ? layout.order.filter { $0 != "summary" } : layout.order }

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geo in
            // iPad в ширину — две колонки: лента слева, обзор месяца справа.
            let wide = sizeClass == .regular && geo.size.width > 900 && !layout.editing
            let colW = wide ? min(600, geo.size.width * 0.48) : min(geo.size.width, 720)
            VStack(spacing: 0) {
                topBar.padding(.top, 4).padding(.horizontal, wide ? 24 : 16)
                    .frame(maxWidth: wide ? .infinity : 720)
                HStack(alignment: .top, spacing: 0) {
                    ZStack(alignment: .bottom) {
                        mainColumn
                        Group { if layout.editing { editBar } else { bottomButtons } }
                            .transition(.opacity)
                    }
                    .frame(width: colW)
                    if wide {
                        SidePanel(txs: allTxs, month: $month, debts: debts, recs: recs)
                            .frame(maxWidth: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .animation(Motion.spring, value: wide)
        }
        .background(Backdrop())
        .background(shortcuts)
        .sheet(isPresented: $showAdd) { AddBlockSheet() }
    }

    /// Сочетания клавиш для клавиатуры iPad.
    private var shortcuts: some View {
        Group {
            Button("") { router.show(.newTx) }.keyboardShortcut("n", modifiers: .command)
            Button("") { router.show(.search) }.keyboardShortcut("f", modifiers: .command)
            Button("") { router.startVoice() }.keyboardShortcut("r", modifiers: .command)
            Button("") { router.show(.stats) }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("") { router.show(.settings) }.keyboardShortcut(",", modifiers: .command)
            Button("") { withAnimation(Motion.snappy) { month = month.addingMonths(-1) } }.keyboardShortcut(.leftArrow, modifiers: .command)
            Button("") { withAnimation(Motion.snappy) { month = month.addingMonths(1) } }.keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            if pinHero {
                hero
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .scaleEffect(heroBump ? 1.02 : 1)
                    .contentShape(Rectangle())
                    .simultaneousGesture(editPress)
                    .zIndex(1)
            }
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("homeScroll")).minY } action: { legacyPull($0) }
                    if !layout.editing && !layout.order.contains("insights") {
                        PullPill(title: "Обновить", symbol: "arrow.down", pull: pull, state: pullState, since: refreshStart, hideWhenIdle: true) {}
                    }
                    VStack(spacing: layout.editing ? 18 : (ap.compact ? 16 : 22)) {
                        ForEach(scrollOrder, id: \.self) { id in
                            block(id)
                                .modifier(EditableBlock(editing: layout.editing, title: layout.block(id)?.title ?? "") { layout.remove(id) })
                        }
                        if layout.editing { editTail }
                    }
                    .padding(.top, pinHero ? 16 : 28)
                    .animation(Motion.snappy, value: layout.order)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                // удержание на пустом месте — режим редактирования (на строках — их меню)
                .background(Color.clear.contentShape(Rectangle()).gesture(editPress))
            }
            .coordinateSpace(name: "homeScroll")
            .modifier(OverscrollReader { onPull($0) })
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always)
            // список уходит под кнопки и плавно растворяется — без отдельной плашки
            .contentMargins(.bottom, 120, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: pinHero ? 18 : 0)
                    Color.black
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.35), location: 0.6), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var editPress: some Gesture {
        LongPressGesture(minimumDuration: 0.7).onEnded { _ in
            guard !layout.editing else { return }
            Haptic.heavy()
            withAnimation(Motion.snappy) { layout.editing = true }
        }
    }

    // MARK: Своё «потяните, чтобы обновить» без колёсика

    static let pullThreshold: CGFloat = 86

    @State private var restY: CGFloat?
    /// Для iOS 17: считаем от положения покоя, которое запоминаем при первом замере.
    private func legacyPull(_ y: CGFloat) {
        if #available(iOS 18.0, *) { return }
        if restY == nil { restY = y }
        onPull(y - (restY ?? y))
    }

    private func onPull(_ y: CGFloat) {
        let p = max(0, y)
        guard abs(p - pull) > 0.5 || p == 0 else { return }
        pull = p
        guard !layout.editing else { return }
        switch pullState {
        case .idle, .pulling:
            pullState = p > 4 ? .pulling : .idle
            let tick = Int(min(p, Self.pullThreshold) / (Self.pullThreshold / 4))
            if tick > pullTick, tick < 4 { Haptic.select() }
            pullTick = tick
            if p >= Self.pullThreshold {
                Haptic.press()
                withAnimation(Motion.spring) { pullState = .armed }
            }
        case .armed:
            // палец отпустили — список поехал обратно
            if p < Self.pullThreshold * 0.6 { startRefresh() }
        case .refreshing, .done:
            break
        }
    }

    private func startRefresh() {
        refreshStart = Date()
        withAnimation(Motion.spring) { pullState = .refreshing }
        pullTick = 0
        Task {
            let started = Date()
            if sync.loggedIn { await sync.sync(ctx: ctx) }
            Notifier.reschedule(ctx: ctx)
            let left = 0.9 - Date().timeIntervalSince(started)
            if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
            if case .error = sync.state { Haptic.warning() } else { Haptic.success() }
            withAnimation(Motion.spring) { pullState = .done }
            if Motion.moves {
                withAnimation(Motion.pressDown) { heroBump = true }
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(Motion.pop) { heroBump = false }
            }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(Motion.spring) { pullState = .idle }
        }
    }

    private var doneText: String {
        if case .error(let e) = sync.state { return e.count > 26 ? "Нет связи" : e }
        return sync.loggedIn ? "Синхронизировано" : "Всё актуально"
    }

    // MARK: Блоки

    @ViewBuilder private func block(_ id: String) -> some View {
        switch id {
        case "summary": hero
        case "companion": CompanionBlock(txs: allTxs)
        case "insights": insightsButton
        case "attention": attention
        case "budgets": BudgetsBlock(txs: allTxs)
        case "goals": GoalsBlock()
        case "payments": PaymentsBlock(debts: debts, recs: recs, txs: allTxs)
        case "categories": CategoriesBlock(txs: monthTxs)
        case "accounts": AccountsBlock(accs: accs, txs: allTxs)
        case "quick": QuickBlock(txs: allTxs)
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
                .frame(minWidth: 130, alignment: .leading)
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
                // на узких экранах (iPhone SE, mini, крупный шрифт) кнопок становится меньше, а не наезжают друг на друга
                ViewThatFits(in: .horizontal) {
                    GlassIconGroup(items: items)
                    GlassIconGroup(items: Array(items.prefix(3)))
                    GlassIconGroup(items: Array(items.prefix(2)))
                }
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
                    Button { Haptic.select(); withAnimation(Motion.snappy) { month = Date().startOfMonth } } label: {
                        Image(systemName: "arrow.uturn.backward.circle").font(.title3).foregroundStyle(.secondary)
                    }
                }
            }
            RollingAmount(value: value, font: .system(size: ap.compact ? 52 : 64, weight: .bold), masked: masked)
                .minimumScaleFactor(0.4).lineLimit(1)
                .onTapGesture { if ap.hideAmounts { Haptic.tap(); withAnimation(Motion.spring) { reveal.toggle() } } }
            HStack(spacing: 22) {
                if ap.alwaysIncome || t.inc > 0 {
                    FlowChip(symbol: "arrow.down.left", color: Theme.inc, text: masked ? "•••" : Fmt.rubU(t.inc), textColor: Theme.inc)
                }
                FlowChip(symbol: "arrow.up.right", color: Theme.warn, text: masked ? "•••" : Fmt.rubU(t.exp), textColor: .primary)
            }
            .animation(Motion.spring, value: t.exp)
        }
    }

    private var insightsButton: some View {
        PullPill(title: "Инсайты", symbol: "sparkle", pull: pull, state: pullState, since: refreshStart, doneText: doneText) {
            router.show(.insights)
        }
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
                // при смене месяца лента мягко сменяется, а не «телепортируется»
                .id(month)
                .transition(.opacity.combined(with: .blurReplace))
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
            Button { withAnimation(Motion.snappy) { layout.editing = false } } label: {
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
            .scaleEffect(micPressed && Motion.enabled ? 0.93 : 1)
            .animation(micPressed ? Motion.pressDown : Motion.pressUp, value: micPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressStart == nil {
                            pressStart = Date(); micPressed = true
                            Haptic.press()
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
                        Haptic.tap()
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
            .rotationEffect(.degrees(editing && Motion.full ? (wobble ? 0.5 : -0.5) : 0))
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
                .lineLimit(1).minimumScaleFactor(0.6)
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
                            Haptic.tap()
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

// MARK: - Капсула, которая тянется при обновлении

enum PullState: Equatable { case idle, pulling, armed, refreshing, done }

struct PullPill: View {
    let title: String
    let symbol: String
    let pull: CGFloat
    let state: PullState
    var since: Date = .distantPast
    var hideWhenIdle = false
    var doneText = "Обновлено"
    let action: () -> Void

    private var progress: CGFloat { min(1, pull / HomeView.pullThreshold) }
    /// Резинка: растяжение всегда следует за списком — и когда тянете, и когда он пружинит обратно,
    /// поэтому нет рывка в момент отпускания.
    private var stretch: CGFloat {
        let c: CGFloat = 110
        return c * (1 - 1 / (max(0, pull) / c + 1))
    }
    private var armedLook: Bool { state == .armed }
    private var busy: Bool { state == .refreshing }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
                Text(label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .id(label)
                    .transition(.blurReplace)
            }
            .foregroundStyle(armedLook ? Color.white : (state == .done ? Theme.inc : Color.primary))
            .padding(.horizontal, 18 + stretch * 0.35)
            .frame(height: 44 + stretch * 0.06)
            .background {
                ZStack {
                    // цвет набирается плавно по мере оттягивания
                    Capsule().fill(Theme.accent.opacity(state == .pulling ? Double(progress) * 0.16 : 0))
                    Capsule().fill(Theme.accent.gradient).opacity(armedLook ? 1 : 0)
                    Shimmer(active: busy && Motion.enabled, since: since).clipShape(Capsule()).opacity(busy ? 1 : 0)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
        .glass(Capsule(), interactive: true)
        .scaleEffect(armedLook && Motion.moves ? 1.04 : 1)
        // капсула едет вниз медленнее списка — ощущение, что её растягивает
        .offset(y: -stretch * 0.45)
        .opacity(hideWhenIdle && state == .idle && pull < 4 ? 0 : 1)
        .frame(height: hideWhenIdle && state == .idle && pull < 4 ? 0 : nil)
        // смена состояний — одной мягкой пружиной; растяжение идёт за пальцем без задержки
        .animation(Motion.enabled ? .spring(duration: 0.45, bounce: 0.18) : nil, value: state)
    }

    private var label: String {
        switch state {
        case .idle, .pulling: return title
        case .armed: return "Отпустите"
        case .refreshing: return "Обновляю…"
        case .done: return doneText
        }
    }

    private var iconName: String { state == .done ? "checkmark" : symbol }

    /// Одна и та же звёздочка от начала до конца: пока тянете — поворачивается за пальцем,
    /// после отпускания плавно разгоняется с того же угла и равномерно крутится; в конце мягко превращается в галочку.
    private var icon: some View {
        TimelineView(.animation(paused: !busy || !Motion.enabled)) { tl in
            Image(systemName: iconName)
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(.degrees(angle(at: tl.date)))
                .scaleEffect(state == .pulling || state == .armed ? 0.9 + progress * 0.2 : 1)
        }
    }

    private func angle(at now: Date) -> Double {
        switch state {
        case .pulling, .armed:
            return Double(progress) * 180
        case .refreshing:
            guard Motion.enabled else { return 180 }
            // скорость растёт от нуля до 330°/с за ~0,3 с — без рывка в момент старта
            let e = max(0, now.timeIntervalSince(since))
            let v = 330.0, tau = 0.3
            return 180 + v * (e - tau * (1 - exp(-e / tau)))
        default:
            return 0
        }
    }
}

/// Бегущий блик внутри капсулы во время обновления: стартует из-за левого края и плавно проявляется.
struct Shimmer: View {
    var active: Bool
    var since: Date = .distantPast
    var body: some View {
        TimelineView(.animation(paused: !active)) { tl in
            GeometryReader { g in
                let e = max(0, tl.date.timeIntervalSince(since))
                let t = e.truncatingRemainder(dividingBy: 1.4) / 1.4
                let ease = t * t * (3 - 2 * t)
                LinearGradient(colors: [.clear, Theme.accent.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.55)
                    .offset(x: (ease * 1.55 - 0.55) * g.size.width)
                    .opacity(min(1, e / 0.3))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Насколько список оттянут вниз за верхний край (iOS 18+ — точно, через геометрию прокрутки).
struct OverscrollReader: ViewModifier {
    let onChange: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { g in
                -(g.contentOffset.y + g.contentInsets.top)
            } action: { _, v in
                onChange(v)
            }
        } else {
            content
        }
    }
}

/// Правая колонка на iPad: обзор месяца, ближайшие платежи и копилки.
private struct SidePanel: View {
    let txs: [Tx]
    @Binding var month: Date
    let debts: [Debt]
    let recs: [Recurring]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MonthOverview(txs: txs, month: $month, showsMonthPill: false)
                PaymentsBlock(debts: debts, recs: recs, txs: txs)
                GoalsBlock()
                BudgetsBlock(txs: txs)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
        }
    }
}
