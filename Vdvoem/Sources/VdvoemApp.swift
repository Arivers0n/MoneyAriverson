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
                if new == .active { store.sync.resume() }
                else { store.flushSave() }
            }
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .fontDesign(store.p.design.design)
            .preferredColorScheme(store.scheme)
            .tint(store.meColor)
            .id(store.p.themeID)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0

    private var items: [(title: String, icon: String)] {
        store.bar.map { ($0.title, $0.icon) } + [("Ещё", "ellipsis")]
    }

    var body: some View {
        ZStack {
            ForEach(Array(store.bar.enumerated()), id: \.element) { i, m in
                NavigationStack { ModuleView(module: m) }
                    .opacity(tab == i ? 1 : 0)
                    .allowsHitTesting(tab == i)
            }
            NavigationStack { MoreView() }
                .opacity(tab == store.bar.count ? 1 : 0)
                .allowsHitTesting(tab == store.bar.count)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        .animation(.easeInOut(duration: 0.18), value: tab)
    }

    private var bar: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                let on = tab == i
                Button {
                    if tab != i { store.tap() }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { tab = i }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: it.icon).font(.system(size: 18, weight: .semibold))
                            .symbolVariant(on ? .fill : .none)
                        if on { Text(it.title).font(.footnote.weight(.bold)).lineLimit(1) }
                    }
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.6))
                    .padding(.horizontal, on ? 16 : 12).frame(height: 46)
                    .background {
                        if on { Capsule().fill(LinearGradient(colors: [store.meColor, store.meColor.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: store.meColor.opacity(0.4), radius: 8, y: 4) }
                    }
                    .frame(maxWidth: on ? nil : .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 18).padding(.bottom, 6)
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
            case .dates: DatesView()
            }
        }
        .navigationTitle(module.title)
    }
}
