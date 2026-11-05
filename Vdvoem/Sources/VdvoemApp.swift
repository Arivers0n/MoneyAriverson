import SwiftUI
import UIKit
import LocalAuthentication

@main
struct VdvoemApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if Demo.screen != nil {
                    DemoRoot()
                } else if store.data.profile.onboarded {
                    if store.data.profile.lockApp {
                        LockGate(title: "Вдвоём") { RootView() }
                    } else {
                        RootView()
                    }
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(store)
            .environmentObject(store.sync)
            .onChange(of: phase) { _, new in
                if new == .active { store.sync.resume(); store.updateBattery() }
                else { store.flushSave() }
            }
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .fontDesign(store.p.design.design)
            .preferredColorScheme(store.scheme)
            .tint(store.meColor)
            .animation(Store.spring, value: store.p.design)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @StateObject private var dock = DockState()
    @State private var selected = ""

    private var tabs: [AppTab] {
        store.bar.map { AppTab(id: $0.rawValue, title: $0.title, symbol: $0.icon, hex: $0.hex) }
            + [AppTab(id: "more", title: "Ещё", symbol: "square.grid.2x2", hex: "B7A6FF")]
    }
    private var current: String { tabs.contains { $0.id == selected } ? selected : (tabs.first?.id ?? "more") }

    /// Вкладка, с которой только что ушли: остаётся полностью видимой, пока новая проявляется.
    @State private var leaving: String?
    /// Пока открыта клавиатура, док прячется, а вставка под него убирается.
    @State private var typing = false

    var body: some View {
        // Все вкладки создаются сразу (прокрутка и ввод сохраняются, на первом заходе ничего не «выскакивает»).
        // Новая вкладка плавно проявляется поверх старой, старая гаснет только после этого.
        ZStack(alignment: .bottom) {
            ThemeBackground()
            VStack(spacing: 0) {
                ZStack {
                    ForEach(tabs) { t in
                        let on = t.id == current
                        NavigationStack {
                            if t.id == "more" { MoreView() }
                            else if let m = Module(rawValue: t.id) { ModuleView(module: m) }
                        }
                        .opacity(on || t.id == leaving ? 1 : 0)
                        .allowsHitTesting(on)
                        .accessibilityHidden(!on)
                        .zIndex(on ? 2 : (t.id == leaving ? 1 : 0))
                    }
                }
                .animation(Motion.enter, value: current)
                // Место под док: содержимое любого экрана заканчивается выше панели и ничем не перекрывается.
                Color.clear.frame(height: typing ? 0 : 78)
            }
            GlassDock(tabs: tabs, selected: Binding(get: { current }, set: { selected = $0 }))
                .padding(.bottom, 2)
                .opacity(typing ? 0 : 1)
                .offset(y: typing ? 24 : 0)
                .allowsHitTesting(!typing)
        }
        .animation(Motion.enter, value: typing)
        .overlay { SignalOverlay() }
        .environmentObject(dock)
        .onAppear { if selected.isEmpty { selected = tabs.first?.id ?? "more" } }
        .onChange(of: current) { old, _ in
            leaving = old
            Task {
                try? await Task.sleep(nanoseconds: 380_000_000)
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { leaving = nil }
            }
        }
        // «Ещё» сворачивает док в круг, любая другая вкладка разворачивает.
        .onChange(of: current) { _, new in dock.set(new == "more", haptics: store.p.haptics) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in typing = false }
    }
}

struct ModuleView: View {
    let module: Module
    var body: some View {
        Group {
            switch module {
            case .tasks: TasksView()
            case .calendar: CalendarView()
            case .wishes: WishesView()
            case .lists: ListsView()
            case .chat: ChatView()
            case .plans: PlansView()
            case .files: LockGate(title: "Файлы") { FilesView() }
            case .cards: LockGate(title: "Карты") { CardsView() }
            case .question: QuestionView()
            case .compat: CompatView()
            case .games: GamesView()
            case .capsule: CapsuleView()
            case .vote: VoteView()
            case .radar: RadarView()
            case .notes: NotesView()
            case .days: DaysView()
            case .mood: JarView()
            case .today: TodayView()
            case .memories: MemoriesView()
            case .places: PlacesView()
            case .signal: SignalView()
            case .pet: PetView()
            case .dates: DatesView()
            }
        }
        .navigationTitle(module.title)
    }
}
