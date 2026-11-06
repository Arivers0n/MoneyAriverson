import AppIntents
import WidgetKit
import SwiftUI
import UIKit

// MARK: - Настройка вида (общая для всех дополнительных виджетов)

enum VDStyle: String, AppEnum {
    case soft, color, dark, light
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Стиль")
    static var caseDisplayRepresentations: [VDStyle: DisplayRepresentation] = [
        .soft: DisplayRepresentation(title: "Мягкий"),
        .color: DisplayRepresentation(title: "Цветной"),
        .dark: DisplayRepresentation(title: "Тёмный"),
        .light: DisplayRepresentation(title: "Светлый")
    ]
}

enum VDAccent: String, AppEnum {
    case partner, me, rose, blue, green, orange, violet
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Цвет")
    static var caseDisplayRepresentations: [VDAccent: DisplayRepresentation] = [
        .partner: DisplayRepresentation(title: "Цвет партнёра"),
        .me: DisplayRepresentation(title: "Мой цвет"),
        .rose: DisplayRepresentation(title: "Розовый"),
        .blue: DisplayRepresentation(title: "Синий"),
        .green: DisplayRepresentation(title: "Зелёный"),
        .orange: DisplayRepresentation(title: "Оранжевый"),
        .violet: DisplayRepresentation(title: "Фиолетовый")
    ]
}

enum VDScope: String, AppEnum {
    case all, me, partner
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Чьи")
    static var caseDisplayRepresentations: [VDScope: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "Все"),
        .me: DisplayRepresentation(title: "Мои"),
        .partner: DisplayRepresentation(title: "Партнёра")
    ]
}

protocol VDLooked: WidgetConfigurationIntent {
    var style: VDStyle { get }
    var accent: VDAccent { get }
    var scope: VDScope { get }
}

struct VDLookIntent: VDLooked {
    static var title: LocalizedStringResource = "Вид виджета"
    static var description = IntentDescription("Стиль и цвет виджета.")
    @Parameter(title: "Стиль", default: .soft) var style: VDStyle
    @Parameter(title: "Цвет", default: .partner) var accent: VDAccent
    var scope: VDScope { .all }
}

struct VDScopeIntent: VDLooked {
    static var title: LocalizedStringResource = "Вид и чьи записи"
    static var description = IntentDescription("Чьи записи показывать, стиль и цвет.")
    @Parameter(title: "Чьи", default: .all) var scope: VDScope
    @Parameter(title: "Стиль", default: .soft) var style: VDStyle
    @Parameter(title: "Цвет", default: .partner) var accent: VDAccent
}

struct VDLook {
    var style: VDStyle
    var accent: VDAccent
    var scope: VDScope
}

struct VDLookEntry: TimelineEntry {
    let date: Date
    let snap: VDSnapshot
    let photo: UIImage?
    let look: VDLook
}

struct VDGenProvider<I: VDLooked>: AppIntentTimelineProvider {
    var wantsPhoto = false

    private func make(_ c: I, sample: Bool) -> VDLookEntry {
        let real = sample ? nil : WidgetShared.readSnapshot()
        var photo: UIImage?
        if wantsPhoto, !sample, real?.hasPhoto == true, let d = WidgetShared.readPhoto() { photo = UIImage(data: d) }
        return VDLookEntry(date: Date(), snap: real ?? .sample(), photo: photo, look: VDLook(style: c.style, accent: c.accent, scope: c.scope))
    }

    func placeholder(in context: Context) -> VDLookEntry {
        VDLookEntry(date: Date(), snap: .sample(), photo: nil, look: VDLook(style: .soft, accent: .partner, scope: .all))
    }
    func snapshot(for configuration: I, in context: Context) async -> VDLookEntry { make(configuration, sample: context.isPreview) }
    func timeline(for configuration: I, in context: Context) async -> Timeline<VDLookEntry> {
        let e = make(configuration, sample: false)
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date()).addingTimeInterval(86400 + 5)
        return Timeline(entries: [e], policy: .after(min(midnight, Date().addingTimeInterval(30 * 60))))
    }
}

// MARK: - Оболочка: фон, цвета, заголовок

struct VDShell<Content: View>: View {
    let e: VDLookEntry
    var title: String
    var icon: String
    var url = "vdvoem://home"
    var photoBackground = false
    @ViewBuilder var content: () -> Content

    var accent: Color {
        let s = e.snap
        switch e.look.accent {
        case .partner: return vdHex(s.partnerHex)
        case .me: return vdHex(s.myHex)
        case .rose: return Color(red: 0.86, green: 0.22, blue: 0.58)
        case .blue: return Color(red: 0.0, green: 0.58, blue: 0.78)
        case .green: return Color(red: 0.2, green: 0.7, blue: 0.5)
        case .orange: return Color(red: 0.95, green: 0.5, blue: 0.1)
        case .violet: return Color(red: 0.55, green: 0.35, blue: 0.9)
        }
    }

    private var forced: ColorScheme? {
        switch e.look.style { case .dark, .color: return .dark; case .light: return .light; case .soft: return nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Label(title, systemImage: icon).font(.caption.weight(.semibold))
                    .foregroundStyle(e.look.style == .color ? Color.white.opacity(0.9) : accent).lineLimit(1)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(e.look.style == .color ? Color.white : Color.primary)
        .environment(\.colorScheme, forced ?? colorSchemeFallback)
        .widgetURL(URL(string: url))
        .containerBackground(for: .widget) { background }
    }

    @Environment(\.colorScheme) private var colorSchemeFallback

    @ViewBuilder private var background: some View {
        switch e.look.style {
        case .soft:
            LinearGradient(colors: [accent.opacity(0.26), Color(.systemBackground)], startPoint: .top, endPoint: .bottom)
        case .color:
            LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dark:
            LinearGradient(colors: [accent.opacity(0.35), Color(red: 0.07, green: 0.07, blue: 0.09)], startPoint: .top, endPoint: .bottom)
        case .light:
            LinearGradient(colors: [accent.opacity(0.14), .white], startPoint: .top, endPoint: .bottom)
        }
    }
}

private func daysFrom(_ d: Date, now: Date) -> Int {
    let c = Calendar.current
    return c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: d)).day ?? 0
}

private func daysText(_ n: Int) -> String {
    if n <= 0 { return "сегодня" }
    if n == 1 { return "завтра" }
    let m10 = n % 10, m100 = n % 100
    let w = (m10 == 1 && m100 != 11) ? "день" : ((2...4).contains(m10) && !(12...14).contains(m100) ? "дня" : "дней")
    return "через \(n) \(w)"
}

private func shortDate(_ d: Date) -> String {
    d.formatted(Date.FormatStyle().locale(Locale(identifier: "ru_RU")).day().month(.abbreviated))
}

private struct Empty: View {
    let text: String
    var body: some View { Text(text).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center) }
}

// MARK: - Задачи

struct VDTasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemTasks", intent: VDScopeIntent.self, provider: VDGenProvider<VDScopeIntent>()) { e in VDTasksView(e: e) }
            .configurationDisplayName("Задачи")
            .description("Открытые задачи — ваши, партнёра или все.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

struct VDTasksView: View {
    @Environment(\.widgetFamily) private var family
    let e: VDLookEntry
    var body: some View {
        let all = e.snap.tasks
        let want = e.look.scope == .me ? "me" : "partner"
        let list = e.look.scope == .all ? all : all.filter { $0.who == want }
        let limit = family == .systemSmall ? 3 : (family == .systemMedium ? 4 : 9)
        let title = e.look.scope == .me ? "Мои задачи" : (e.look.scope == .partner ? "Задачи: \(e.snap.partnerName)" : "Задачи")
        VDShell(e: e, title: title, icon: "checklist", url: "vdvoem://tasks") {
            if list.isEmpty { Empty(text: "Всё сделано 🎉") }
            else {
                ForEach(Array(list.prefix(limit).enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 8) {
                        Circle().strokeBorder(t.priority >= 2 ? Color.red : (t.who == "partner" ? vdHex(e.snap.partnerHex) : vdHex(e.snap.myHex)), lineWidth: 2).frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.title).font(.subheadline).lineLimit(1)
                            if let d = t.due, family != .systemSmall {
                                Text(daysText(daysFrom(d, now: e.date)) + " · " + shortDate(d)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
                if list.count > limit { Text("и ещё \(list.count - limit)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Неделя

struct VDWeekWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemWeek", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDWeekView(e: e) }
            .configurationDisplayName("Неделя")
            .description("Семь дней: даты и сроки задач.")
            .supportedFamilies([.systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

struct VDWeekView: View {
    @Environment(\.widgetFamily) private var family
    let e: VDLookEntry
    var body: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: e.date)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let count: (Date) -> Int = { d in
            let a = e.snap.events.filter { cal.isDate($0.date, inSameDayAs: d) }.count
            let b = e.snap.tasks.filter { t in t.due.map { cal.isDate($0, inSameDayAs: d) } ?? false }.count
            return a + b
        }
        let upcoming = e.snap.events.filter { daysFrom($0.date, now: e.date) < 7 }
        VDShell(e: e, title: "Неделя", icon: "calendar", url: "vdvoem://calendar") {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let today = cal.isDateInToday(d)
                    VStack(spacing: 3) {
                        Text(d.formatted(Date.FormatStyle().locale(Locale(identifier: "ru_RU")).weekday(.narrow)).uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text("\(cal.component(.day, from: d))").font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(width: 28, height: 28)
                            .background(today ? VDShellAccent.color(e) : Color.clear, in: Circle())
                            .foregroundStyle(today ? Color.white : Color.primary)
                        Circle().fill(count(d) > 0 ? VDShellAccent.color(e) : Color.clear).frame(width: 5, height: 5)
                    }.frame(maxWidth: .infinity)
                }
            }
            if upcoming.isEmpty { Empty(text: "На этой неделе событий нет") }
            else {
                ForEach(Array(upcoming.prefix(family == .systemLarge ? 6 : 2).enumerated()), id: \.offset) { _, ev in
                    HStack(spacing: 8) {
                        Text(ev.emoji)
                        Text(ev.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(daysText(daysFrom(ev.date, now: e.date))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

enum VDShellAccent {
    static func color(_ e: VDLookEntry) -> Color {
        let s = e.snap
        if e.look.style == .color { return Color.white.opacity(0.3) }
        switch e.look.accent {
        case .partner: return vdHex(s.partnerHex)
        case .me: return vdHex(s.myHex)
        case .rose: return Color(red: 0.86, green: 0.22, blue: 0.58)
        case .blue: return Color(red: 0.0, green: 0.58, blue: 0.78)
        case .green: return Color(red: 0.2, green: 0.7, blue: 0.5)
        case .orange: return Color(red: 0.95, green: 0.5, blue: 0.1)
        case .violet: return Color(red: 0.55, green: 0.35, blue: 0.9)
        }
    }
}

// MARK: - Ближайшие даты

struct VDDatesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemDates", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDDatesView(e: e) }
            .configurationDisplayName("Ближайшие даты")
            .description("Годовщины, дни рождения и события.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
            .contentMarginsDisabled()
    }
}

struct VDDatesView: View {
    @Environment(\.widgetFamily) private var family
    let e: VDLookEntry
    var body: some View {
        let list = e.snap.events
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                if let f = list.first {
                    Text("\(f.emoji) \(f.title)").font(.headline).lineLimit(1)
                    Text(daysText(daysFrom(f.date, now: e.date))).font(.caption)
                } else { Text("Нет событий").font(.headline) }
            }.frame(maxWidth: .infinity, alignment: .leading).containerBackground(for: .widget) { Color.clear }
        } else {
            VDShell(e: e, title: "Даты", icon: "gift", url: "vdvoem://calendar") {
                if list.isEmpty { Empty(text: "Добавьте даты в календаре") }
                else if family == .systemSmall, let f = list.first {
                    Text(f.emoji).font(.system(size: 30))
                    Text(f.title).font(.headline).lineLimit(2)
                    Text(daysText(daysFrom(f.date, now: e.date))).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(list.prefix(3).enumerated()), id: \.offset) { _, ev in
                        HStack(spacing: 10) {
                            Text(ev.emoji).font(.title3)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ev.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(shortDate(ev.date)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(daysText(daysFrom(ev.date, now: e.date))).font(.caption.weight(.semibold))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Планы

struct VDPlansWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemPlans", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDPlansView(e: e) }
            .configurationDisplayName("Планы")
            .description("Общие планы и прогресс по шагам.")
            .supportedFamilies([.systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

struct VDPlansView: View {
    @Environment(\.widgetFamily) private var family
    let e: VDLookEntry
    var body: some View {
        VDShell(e: e, title: "Планы", icon: "flag", url: "vdvoem://plans") {
            if e.snap.plans.isEmpty { Empty(text: "Планов пока нет") }
            else {
                ForEach(Array(e.snap.plans.prefix(family == .systemLarge ? 4 : 2).enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(p.emoji)
                            Text(p.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text("\(p.done)/\(p.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: p.total == 0 ? 0 : Double(p.done) / Double(p.total)).tint(VDShellAccent.color(e))
                        if let t = p.target {
                            Text(daysText(daysFrom(t, now: e.date))).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Хотелки партнёра

struct VDWishesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemWishes", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDWishesView(e: e) }
            .configurationDisplayName("Хотелки партнёра")
            .description("Что хочет получить партнёр — чтобы не забыть про подарок.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

struct VDWishesView: View {
    @Environment(\.widgetFamily) private var family
    let e: VDLookEntry
    var body: some View {
        VDShell(e: e, title: "Хотелки: \(e.snap.partnerName)", icon: "sparkles", url: "vdvoem://wishes") {
            if e.snap.wishes.isEmpty { Empty(text: "Список пуст") }
            else {
                ForEach(Array(e.snap.wishes.prefix(family == .systemSmall ? 4 : 4).enumerated()), id: \.offset) { _, w in
                    HStack(spacing: 8) { Image(systemName: "gift").font(.caption).foregroundStyle(VDShellAccent.color(e)); Text(w).font(.subheadline).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Text("всего \(e.snap.wishesTotal)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Кино

struct VDMoviesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemMovies", intent: VDScopeIntent.self, provider: VDGenProvider<VDScopeIntent>()) { e in VDMoviesView(e: e) }
            .configurationDisplayName("Кино")
            .description("Что смотрите сейчас и что хотите посмотреть.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

struct VDMoviesView: View {
    @Environment(\.widgetFamily) private var family
    let e: VDLookEntry
    var body: some View {
        let list = e.snap.movies.filter { e.look.scope == .all || $0.owner == (e.look.scope == .me ? "me" : "partner") }
        VDShell(e: e, title: "Кино", icon: "film", url: "vdvoem://movies") {
            if list.isEmpty { Empty(text: "Список пуст") }
            else {
                ForEach(Array(list.prefix(family == .systemSmall ? 3 : 4).enumerated()), id: \.offset) { _, m in
                    HStack(spacing: 8) {
                        Image(systemName: m.state == 1 ? "play.circle.fill" : "bookmark").foregroundStyle(VDShellAccent.color(e))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.title).font(.subheadline).lineLimit(1)
                            let who = m.owner == "me" ? e.snap.myName : (m.owner == "partner" ? e.snap.partnerName : "вместе")
                            Text(who + (m.progress.isEmpty ? "" : " · " + m.progress)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Капсула времени

struct VDCapsuleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemCapsule", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDCapsuleView(e: e) }
            .configurationDisplayName("Капсула")
            .description("Сколько осталось до открытия капсулы времени.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct VDCapsuleView: View {
    let e: VDLookEntry
    var body: some View {
        VDShell(e: e, title: "Капсула", icon: "hourglass", url: "vdvoem://capsules") {
            if let d = e.snap.capsuleOpens {
                let n = max(0, daysFrom(d, now: e.date))
                Text("\(n)").font(.system(size: 44, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                Text(n == 1 ? "день до открытия" : "дн. до открытия").font(.caption).foregroundStyle(.secondary)
                Text(e.snap.capsuleTitle).font(.footnote.weight(.semibold)).lineLimit(1)
            } else { Empty(text: "Закрытых капсул нет") }
        }
    }
}

// MARK: - Голосование

struct VDPollWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemPoll", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDPollView(e: e) }
            .configurationDisplayName("Голосование")
            .description("Последний общий опрос и голоса.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

struct VDPollView: View {
    @Environment(\.widgetFamily) private var family
    let e: VDLookEntry
    var body: some View {
        VDShell(e: e, title: "Голосование", icon: "chart.bar", url: "vdvoem://polls") {
            if let p = e.snap.poll {
                Text(p.question).font(.subheadline.weight(.semibold)).lineLimit(2)
                let total = max(1, p.options.reduce(0) { $0 + $1.votes })
                ForEach(Array(p.options.prefix(family == .systemSmall ? 2 : 3).enumerated()), id: \.offset) { _, o in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text(o.text).font(.caption).lineLimit(1); if o.mine { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }; Spacer(); Text("\(o.votes)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        ProgressView(value: Double(o.votes) / Double(total)).tint(VDShellAccent.color(e))
                    }
                }
                Spacer(minLength: 0)
            } else { Empty(text: "Опросов пока нет") }
        }
    }
}

// MARK: - Игры

struct VDGamesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemGames", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDGamesView(e: e) }
            .configurationDisplayName("Игры")
            .description("Счёт побед и чей ход.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

struct VDGamesView: View {
    let e: VDLookEntry
    var body: some View {
        VDShell(e: e, title: "Игры", icon: "gamecontroller", url: "vdvoem://games") {
            HStack(spacing: 0) {
                VStack { Text("\(e.snap.winsMe)").font(.system(size: 34, weight: .bold, design: .rounded)); Text(e.snap.myName).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity)
                Text(":").font(.title2).foregroundStyle(.secondary)
                VStack { Text("\(e.snap.winsPartner)").font(.system(size: 34, weight: .bold, design: .rounded)); Text(e.snap.partnerName).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            Text(e.snap.myTurns > 0 ? "Ваш ход: \(e.snap.myTurns)" : "Ходов к вам нет").font(.caption.weight(.semibold))
        }
    }
}

// MARK: - Питомец

struct VDPetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemPet", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDPetView(e: e) }
            .configurationDisplayName("Питомец")
            .description("Общий питомец: возраст и когда кормили.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

struct VDPetView: View {
    let e: VDLookEntry
    var body: some View {
        VDShell(e: e, title: "Питомец", icon: "pawprint", url: "vdvoem://pet") {
            if e.snap.petName.isEmpty { Empty(text: "Питомца пока нет") }
            else {
                Text(e.snap.petFedHours >= 8 ? "🥺" : "😸").font(.system(size: 38))
                Text(e.snap.petName).font(.headline).lineLimit(1)
                Text(e.snap.petFedHours >= 8 ? "Хочет есть" : "Сыт · \(e.snap.petFedHours) ч назад").font(.caption).foregroundStyle(.secondary)
                Text("Живёт \(e.snap.petAgeDays) дн.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Фото партнёра

struct VDPartnerPhotoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemPhoto", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>(wantsPhoto: true)) { e in VDPhotoView(e: e) }
            .configurationDisplayName("Общее фото")
            .description("Последнее фото из вашей ленты.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}

struct VDPhotoView: View {
    let e: VDLookEntry
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if e.photo == nil {
                VStack(spacing: 6) { Image(systemName: "photo.on.rectangle").font(.title); Text("Нет общих фото").font(.caption) }
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !e.snap.photoCaption.isEmpty {
                Text(e.snap.photoCaption).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            }
        }
        .widgetURL(URL(string: "vdvoem://photos"))
        .containerBackground(for: .widget) {
            if let p = e.photo { Image(uiImage: p).resizable().scaledToFill() }
            else { LinearGradient(colors: [vdHex(e.snap.partnerHex).opacity(0.28), Color(.systemBackground)], startPoint: .top, endPoint: .bottom) }
        }
    }
}

// MARK: - Чат

struct VDChatWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "VdvoemChat", intent: VDLookIntent.self, provider: VDGenProvider<VDLookIntent>()) { e in VDChatView(e: e) }
            .configurationDisplayName("Чат")
            .description("Последнее сообщение и сколько их сегодня.")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

struct VDChatView: View {
    let e: VDLookEntry
    var body: some View {
        VDShell(e: e, title: "Чат", icon: "bubble.left.and.bubble.right", url: "vdvoem://chat") {
            if e.snap.lastMessage.isEmpty { Empty(text: "Сообщений пока нет") }
            else {
                Text(e.snap.lastMessage).font(.subheadline).lineLimit(3)
                Spacer(minLength: 0)
                Text("сегодня: \(e.snap.messagesToday)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
