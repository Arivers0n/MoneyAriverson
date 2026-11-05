import SwiftUI

/// Демо-режим для скриншотов в CI. Включается только аргументом запуска `-demo <экран>`,
/// в обычной работе приложения не участвует. Все данные ниже вымышленные.
enum Demo {
    static let args = ProcessInfo.processInfo.arguments

    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var screen: String? { value("-demo") }
}

extension Store {
    /// Профиль с именами и датой начала, выбранная тема, пара статусов, чат, задачи, батарея.
    func seedDemo() {
        var d = AppData()
        var p = Profile()
        p.myName = "Андрей"
        p.partnerName = "Саманта"
        p.onboarded = true
        p.start = Calendar.current.date(byAdding: .day, value: -1291, to: Date()) ?? Date()

        let id = Demo.value("-theme") ?? "lagoon"
        let look = ThemeLook.of(id)
        p.themeID = id
        p.iconStyle = look.icon
        p.design = look.font
        p.radius = look.radius
        p.bgPattern = look.pattern
        if let pair = look.pair { p.myHex = pair.0; p.partnerHex = pair.1 }
        p.theme = look.mode ?? (Demo.value("-scheme") == "dark" ? .dark : .light)
        d.profile = p

        let now = Date()
        d.statuses = [StatusItem(who: .partner, kind: "cook", title: "Готовлю", note: "паста", place: "Дома",
                                 started: now.addingTimeInterval(-600), expires: now.addingTimeInterval(23 * 3600))]
        if Demo.screen == "today-both" {
            d.statuses.append(StatusItem(who: .me, kind: "walk", title: "Гуляю", note: "", place: "Парк",
                                         started: now.addingTimeInterval(-1200), expires: now.addingTimeInterval(23 * 3600)))
        }
        d.messages = [
            ChatMessage(text: "Что на ужин?", from: .partner, date: now.addingTimeInterval(-3600)),
            ChatMessage(text: "Паста, скоро буду", from: .me, date: now.addingTimeInterval(-3500)),
            ChatMessage(text: "Купи, пожалуйста, хлеб", from: .partner, date: now.addingTimeInterval(-1200)),
            ChatMessage(text: "Хорошо, уже в магазине", from: .me, date: now.addingTimeInterval(-600))
        ]
        d.tasks = [
            TaskItem(title: "Купить продукты", priority: 1),
            TaskItem(title: "Записаться на стрижку", owner: .me),
            TaskItem(title: "Забронировать столик", owner: .partner, due: now.addingTimeInterval(86400), priority: 2),
            TaskItem(title: "Позвонить маме", owner: .me, done: true)
        ]
        d.batteries = [
            BatteryInfo(id: Who.me.rawValue, who: .me, level: 0.34, charging: false, updated: now),
            BatteryInfo(id: Who.partner.rawValue, who: .partner, level: 0.78, charging: true, updated: now)
        ]
        data = d
        seedCountersIfNeeded()
    }
}

/// Корень демо-режима: засевает данные и показывает один экран.
struct DemoRoot: View {
    @EnvironmentObject var store: Store
    @StateObject private var dock = DockState()
    @State private var ready = false

    var body: some View {
        Group {
            if ready { content } else { Color.clear.onAppear { store.seedDemo(); ready = true } }
        }
        .environmentObject(dock)
    }

    @ViewBuilder private var content: some View {
        switch Demo.screen ?? "root" {
        case "root": RootView()
        case "appearance": NavigationStack { AppearanceView() }
        case "more": NavigationStack { MoreView().navigationTitle("Ещё") }
        case "chat": NavigationStack { ModuleView(module: .chat) }
        case "tasks": NavigationStack { ModuleView(module: .tasks) }
        default: NavigationStack { TodayView() }
        }
    }
}
