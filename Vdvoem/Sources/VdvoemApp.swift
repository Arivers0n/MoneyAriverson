import SwiftUI
import UIKit
import LocalAuthentication
import BackgroundTasks

@main
struct VdvoemApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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
                else { store.flushSave(); Push.scheduleRefresh() }
            }
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .fontDesign(store.p.design.design)
            .preferredColorScheme(store.scheme)
            .tint(store.meColor)
            .animation(Store.spring, value: store.p.design)
            .onAppear { NavFont.apply(store.p.design) }
            .onChange(of: store.p.design) { _, d in NavFont.apply(d) }
            // Короткое содержимое не «пружинит» вверх-вниз: шапка и экран стоят на месте.
            .scrollBounceBehavior(.basedOnSize)
        }
        // Запасной вариант без пушей: iOS изредка будит приложение, оно проверяет новое.
        .backgroundTask(.appRefresh(Push.refreshID)) {
            await Push.fallbackCheck(store.sync)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @StateObject private var dock = DockState()
    @StateObject private var dial = DialState()
    @State private var selected = ""
    @EnvironmentObject var sync: SyncEngine
    @State private var gate = false

    private var tabs: [AppTab] {
        store.bar.map { AppTab(id: $0.rawValue, title: $0.title, symbol: $0.icon, hex: $0.hex) }
            + [AppTab(id: "more", title: "Ещё", symbol: "square.grid.2x2", hex: "B7A6FF")]
    }
    private var current: String { tabs.contains { $0.id == selected } ? selected : (tabs.first?.id ?? "more") }

    /// Вкладка, с которой только что ушли: остаётся полностью видимой, пока новая проявляется.
    @State private var leaving: String?
    /// Пока открыта клавиатура, док прячется, а вставка под него убирается.
    @State private var typing = false
    /// Док не нужен, пока открыта клавиатура или экран его скрывает (чат).
    private var noDock: Bool { typing || dock.hidden }

    var body: some View {
        // Все вкладки создаются сразу (прокрутка и ввод сохраняются, на первом заходе ничего не «выскакивает»).
        // Новая вкладка плавно проявляется поверх старой, старая гаснет только после этого.
        ZStack(alignment: .bottom) {
            ZStack {
                ThemeBackground(animated: true)
                // В чате обои лежат под всем экраном, включая области статус-бара и индикатора «домой».
                if dock.hidden { WallpaperView(id: store.p.wallpaper).transition(.opacity) }
            }
            .ignoresSafeArea()
            .animation(Motion.enter, value: dock.hidden)
            VStack(spacing: 0) {
                ZStack {
                    ForEach(tabs) { t in
                        let on = t.id == current
                        NavigationStack {
                            if t.id == "more" { MoreView() }
                            else if let m = Module(rawValue: t.id) { ModuleView(module: m) }
                        }
                        .environment(\.screenActive, on)
                        .opacity(on || t.id == leaving ? 1 : 0)
                        .allowsHitTesting(on)
                        .accessibilityHidden(!on)
                        .zIndex(on ? 2 : (t.id == leaving ? 1 : 0))
                    }
                }
                .animation(Motion.enter, value: current)
                // Содержимое доходит до верха экрана (и до низа, если дока нет): никаких полос и обрезков у краёв.
                .ignoresSafeArea(.container, edges: noDock ? Edge.Set.vertical : Edge.Set.top)
                .mask(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: noDock ? 0 : 24)
                    }
                    // Маска сама не должна упираться в безопасные зоны — иначе она режет содержимое по краю статус-бара.
                    .ignoresSafeArea()
                }
                // Место под док.
                Color.clear.frame(height: noDock ? 0 : 78)
            }
            // Размеры меняются мгновенно (иначе поле ввода в чате «подпрыгивает»), плавно — только сам док.
            .transaction(value: noDock) { $0.animation = nil }
            GlassDock(tabs: tabs, selected: Binding(get: { current }, set: { selected = $0 }))
                .padding(.bottom, 2)
                .opacity(noDock ? 0 : 1)
                .offset(y: noDock ? 40 : 0)
                .allowsHitTesting(!noDock)
        }
        .animation(Motion.enter, value: noDock)
        .overlay { SignalOverlay() }
        .overlay { DialOverlay() }
        .overlay { ToastHost() }
        .environmentObject(dock)
        .environmentObject(dial)
        // Запуск всегда с «Сегодня» (если раздел в панели), а не с того, что окажется первым.
        .onAppear {
            if selected.isEmpty { selected = tabs.first(where: { $0.id == Module.today.rawValue })?.id ?? tabs.first?.id ?? "more" }
            if !sync.isSignedIn && !sync.isPaired && !UserDefaults.standard.bool(forKey: "vd.skipConnect") { gate = true }
        }
        .fullScreenCover(isPresented: $gate) { ConnectGate() }
        // Уведомления вне приложения: после соединения с партнёром просим разрешение и отдаём серверу токен.
        .task(id: "\(sync.isPaired)|\(sync.accountEmail)") {
            guard sync.isPaired else { return }
            await Push.enable()
            await Push.upload(sync)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vdPushToken)) { _ in
            Task { await Push.upload(sync) }
        }
        .onChange(of: current) { old, _ in
            leaving = old
            Task {
                try? await Task.sleep(nanoseconds: 380_000_000)
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { leaving = nil }
            }
        }
        // Новая вкладка всегда показывается с развёрнутым доком.
        .onOpenURL { url in
            guard url.scheme == "vdvoem", let host = url.host else { return }
            let map = ["home": "today", "capsules": "capsule", "polls": "vote", "photos": "memories"]
            let id = map[host] ?? host
            selected = tabs.contains { $0.id == id } ? id : "more"
        }
        .onChange(of: current) { _, _ in dock.set(false, haptics: false) }
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
            case .movies: MoviesView()
            }
        }
        .navigationTitle(module.title)
    }
}
