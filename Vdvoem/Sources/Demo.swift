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
        if let v = Demo.value("-icons"), let n = Int(v) { p.iconStyle = n }
        if let pair = look.pair { p.myHex = pair.0; p.partnerHex = pair.1 }
        p.theme = look.mode ?? (Demo.value("-scheme") == "dark" ? .dark : .light)
        d.profile = p

        let now = Date()
        d.statuses = [StatusItem(who: .partner, kind: "cook", title: "Готовлю", note: "паста", place: "Дома",
                                 started: now.addingTimeInterval(-600))]
        if Demo.screen == "today-both" {
            var mine = StatusItem(who: .me, kind: "custom", title: "Грущу", note: "тяжёлый день", place: "",
                                  started: now.addingTimeInterval(-1200))
            mine.emoji = "😔"
            d.statuses.append(mine)
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
        d.jar = [
            JarBall(who: .partner, mood: 1, date: now.addingTimeInterval(-7200)),
            JarBall(who: .me, mood: 4, date: now.addingTimeInterval(-3000)),
            JarBall(who: .partner, mood: 0, date: now.addingTimeInterval(-900))
        ]
        let today = now.dayKey
        let cal = Calendar.current
        if let bed = cal.date(bySettingHour: 23, minute: 40, second: 0, of: now.addingTimeInterval(-86400)),
           let wake = cal.date(bySettingHour: 7, minute: 15, second: 0, of: now) {
            d.sleeps = [SleepEntry(id: today + Who.me.rawValue, day: today, who: .me, bedtime: bed, wake: wake, quality: 4)]
        }
        var meet = EventItem(title: "Встреча", date: now.addingTimeInterval(86400 * 12), emoji: "🚆")
        meet.meeting = true
        d.events = [EventItem(title: "Годовщина знакомства", date: now.addingTimeInterval(86400 * 9)), meet]
        // Утро: прежние статусы для ленты дня (уже сменены)
        d.statuses.append(StatusItem(who: .partner, kind: "work", title: "Работаю", note: "", place: "офис",
                                     started: now.addingTimeInterval(-4 * 3600), expires: now.addingTimeInterval(-600)))
        d.statuses.append(StatusItem(who: .me, kind: "coffee", title: "Пью кофе", note: "", place: "",
                                     started: now.addingTimeInterval(-5 * 3600), expires: now.addingTimeInterval(-1200)))
        // Голосовое от партнёра (без файла — только для вида)
        var v = ChatMessage(text: "🎤 Голосовое", from: .partner, date: now.addingTimeInterval(-1500))
        v.kind = "voice"; v.dur = 7
        v.wave = [4, 9, 16, 22, 12, 18, 26, 14, 8, 20, 28, 17, 10, 6, 14, 22, 25, 12, 7, 15, 19, 9, 5, 11, 16, 8, 4, 10, 18, 13, 6, 3, 9, 14, 7, 4, 8, 12, 6, 3, 5, 9, 4, 2]
        d.messages.insert(v, at: 1)
        // Настроения за неделю
        let cal2 = Calendar.current
        for back in 1...6 {
            let day = cal2.date(byAdding: .day, value: -back, to: now) ?? now
            d.jar.append(JarBall(who: .me, mood: [1, 4, 0, 1, 2, 0][back - 1], date: day))
            d.jar.append(JarBall(who: .partner, mood: [0, 1, 1, 0, 4, 1][back - 1], date: day))
        }
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
        case "status": StatusSheet()
        default: NavigationStack { TodayView() }
        }
    }
}
