import SwiftUI
import LocalAuthentication

@main
struct VdvoemApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.data.profile.onboarded {
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
            .animation(Store.spring, value: store.p.radius)
            .animation(Store.spring, value: store.p.design)
            .animation(Store.spring, value: store.p.bgPattern)
            .id(store.p.themeID)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0

    var body: some View {
        // «Контурные» иконки — родная панель iOS; «неоновые» и «объёмные» — своя панель с тем же поведением.
        let custom = store.p.iconStyle != 0
        TabView(selection: $tab) {
            ForEach(Array(store.bar.enumerated()), id: \.element) { i, m in
                NavigationStack { ModuleView(module: m) }
                    .toolbar(custom ? .hidden : .automatic, for: .tabBar)
                    .tabItem { Label(m.title, systemImage: m.icon) }
                    .tag(i)
            }
            NavigationStack { MoreView() }
                .toolbar(custom ? .hidden : .automatic, for: .tabBar)
                .tabItem { Label("Ещё", systemImage: "square.grid.2x2") }
                .tag(store.bar.count)
        }
        .tabBarCollapses()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if custom { StyledTabBar(tab: $tab).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(Store.spring, value: store.p.iconStyle)
        .overlay { SignalOverlay() }
        .onChange(of: tab) { _, _ in store.tap() }
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
