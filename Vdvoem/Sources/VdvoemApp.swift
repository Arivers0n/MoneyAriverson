import SwiftUI
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

    @State private var visited: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Вкладки живут вместе (состояние и прокрутка сохраняются), а переключаются плавным
        // растворением: новая выходит поверх, старая исчезает только когда новая уже видна.
        ZStack {
            ForEach(tabs.filter { visited.contains($0.id) || $0.id == current }) { t in
                let on = t.id == current
                NavigationStack {
                    if t.id == "more" { MoreView() }
                    else if let m = Module(rawValue: t.id) { ModuleView(module: m) }
                }
                // Место под док (и под круглую кнопку): контент и нижние кнопки не перекрываются.
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 74) }
                .opacity(on ? 1 : 0)
                .scaleEffect(on || reduceMotion ? 1 : 0.985)
                .allowsHitTesting(on)
                .accessibilityHidden(!on)
                .zIndex(on ? 1 : 0)
                .animation(on ? Motion.enter : Motion.exit, value: on)
            }
        }
        .overlay(alignment: .bottom) {
            GlassDock(tabs: tabs, selected: Binding(get: { current }, set: { selected = $0 }))
                .padding(.bottom, 2)
        }
        .overlay { SignalOverlay() }
        .environmentObject(dock)
        .onAppear { if selected.isEmpty { selected = tabs.first?.id ?? "more" }; visited.insert(current) }
        .onChange(of: current) { _, new in visited.insert(new) }
        // «Ещё» сворачивает док в круг, любая другая вкладка разворачивает.
        .onChange(of: current) { _, new in dock.set(new == "more", haptics: store.p.haptics) }
        .ignoresSafeArea(.keyboard)
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
