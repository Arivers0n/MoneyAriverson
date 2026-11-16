import SwiftUI

// MARK: - Три варианта экрана «Сегодня»
//  0 — «Истории»: кружки статусов сверху, крупный счётчик дней, ниже только то, что важно сейчас.
//  1 — «Сетка»: плитки разного размера, как виджеты iOS.
//  2 — «Пара»: одна большая карточка двоих, остальное компактным списком.
//  3 — прежний вид.

enum TodayLayout {
    static let key = "todayLayout"
    static let titles = ["Истории", "Сетка", "Пара", "Прежний"]
    static let symbols = ["circle.dashed", "square.grid.2x2", "person.2", "list.bullet"]
}

// MARK: Общие данные

func daysWord(_ n: Int) -> String {
    let m = n % 100, d = n % 10
    if m >= 11 && m <= 14 { return "дней" }
    if d == 1 { return "день" }
    if d >= 2 && d <= 4 { return "дня" }
    return "дней"
}

struct TodayNowRow: Identifiable {
    let id: String
    let symbol: String
    let hex: String
    let title: String
    let detail: String
    let module: Module
}

extension Store {
    /// Главное сейчас: последнее сообщение партнёра, дела и ближайшая дата.
    var todayNowRows: [TodayNowRow] {
        var rows: [TodayNowRow] = []
        if let m = data.messages.last(where: { $0.from == .partner }) {
            rows.append(TodayNowRow(id: "msg", symbol: "bubble.left.fill", hex: "6EA8FF",
                                    title: "\(name(.partner)): \(m.text.isEmpty ? "голосовое" : m.text)", detail: m.date.agoText, module: .chat))
        }
        let open = data.tasks.filter { !$0.done && $0.owner != .partner }
        if !open.isEmpty {
            let urgent = open.filter { $0.priority > 0 }.count
            rows.append(TodayNowRow(id: "tasks", symbol: "checklist", hex: "3DBE8B",
                                    title: "Дел впереди: \(open.count)",
                                    detail: urgent > 0 ? "из них важных: \(urgent)" : "ничего срочного", module: .tasks))
        }
        if let (e, n) = nextEvent {
            rows.append(TodayNowRow(id: "event", symbol: "calendar", hex: "FF9E5E",
                                    title: e.title, detail: n == 0 ? "сегодня" : (n == 1 ? "завтра" : "через \(n) дн."), module: .calendar))
        }
        return rows
    }

    /// Ближайшая дата из календаря и сколько до неё дней.
    var nextEvent: (EventItem, Int)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func next(_ e: EventItem) -> Date? {
            if !e.yearly { return cal.startOfDay(for: e.date) >= today ? cal.startOfDay(for: e.date) : nil }
            var c = cal.dateComponents([.month, .day], from: e.date)
            for add in 0...1 {
                c.year = cal.component(.year, from: today) + add
                if let d = cal.date(from: c), d >= today { return d }
            }
            return nil
        }
        guard let (e, d) = data.events.compactMap({ e in next(e).map { (e, $0) } }).min(by: { $0.1 < $1.1 }) else { return nil }
        return (e, cal.dateComponents([.day], from: today, to: d).day ?? 0)
    }

    /// Ближайшая круглая дата (каждые 100 дней): сколько осталось и насколько заполнена полоска.
    var nextMilestone: (day: Int, left: Int, progress: Double) {
        let n = daysTogether
        let next = (n / 100 + 1) * 100
        return (next, next - n, Double(n % 100) / 100)
    }

    var startText: String {
        "с " + p.start.formatted(Date.FormatStyle().locale(ruLocale).day().month(.wide).year())
    }

    func lastMood(_ w: Who) -> JarBall? { data.jar.filter { $0.who == w }.max { $0.date < $1.date } }
    func battery(_ w: Who) -> BatteryInfo? { data.batteries.first { $0.who == w } }

    var sleepLine: String { lastSleep(of: .me).map { hoursText($0.hours) } ?? "Записать" }
    var trackerLine: String {
        let n = data.counters.reduce(0) { $0 + count($1.id, who: nil) }
        return n == 0 ? "Отметить" : "Сегодня: \(n)"
    }
}

func batteryColor(_ l: Double) -> Color {
    l < 0.2 ? Color(hex: "EF4444") : (l < 0.5 ? Color(hex: "F5B83D") : Color(hex: "34C38F"))
}

// MARK: Общие детали

/// Мягкое появление по очереди: 40 мс между блоками, весь экран укладывается в ~0,3 с.
struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                if Motion.reduced || Demo.screen != nil { shown = true; return }
                withAnimation(Motion.curve(0.34).delay(Double(min(index, 6)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    func staggerIn(_ i: Int) -> some View { modifier(StaggerIn(index: i)) }
}

/// Бьющееся сердце в цветах пары (на паузе, когда экран скрыт).
struct BeatingHeart: View {
    @EnvironmentObject var store: Store
    var size: CGFloat = 16
    var body: some View {
        LiveTimeline(fps: 24) { date in
            let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            // двойной удар «тук-тук», потом пауза — как настоящий пульс
            let beat = max(0, sin(t * .pi * 4)) * (t < 0.5 ? 1 : 0)
            Image(systemName: "heart.fill").font(.system(size: size, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [store.meColor, store.partnerColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(1 + 0.16 * beat)
        }
        .accessibilityHidden(true)
    }
}

/// Значок статуса: фото, эмодзи или символ.
struct StatusGlyph: View {
    let status: StatusItem
    var size: CGFloat = 44
    var body: some View {
        let k = statusKind(status.kind)
        let c = Color(hex: k.hex).boosted(minS: 0.55, minB: 0.8)
        Group {
            if status.hasPhoto, let m = status.media, let f = status.file {
                RemoteImage(media: m, file: f, thumb: "160x160").frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else if let e = status.emoji, !e.isEmpty {
                Text(e).font(.system(size: size * 0.5)).frame(width: size, height: size).background(c.opacity(0.16), in: Circle())
            } else {
                Image(systemName: k.symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(c)
                    .frame(width: size, height: size).background(c.opacity(0.16), in: Circle())
            }
        }
    }
}

/// Кружок-«история»: кольцо в цвете статуса, внутри фото человека, снизу значок статуса.
struct StoryAvatar: View {
    @EnvironmentObject var store: Store
    let who: Who
    var size: CGFloat = 68

    var body: some View {
        let st = store.statusNow(who)
        let ring: AnyShapeStyle = {
            guard let st else { return AnyShapeStyle(Color.primary.opacity(0.14)) }
            let c = Color(hex: statusKind(st.kind).hex).boosted(minS: 0.55, minB: 0.85)
            return AnyShapeStyle(AngularGradient(colors: [c, store.color(who), c], center: .center))
        }()
        ZStack(alignment: .bottomTrailing) {
            AvatarFace(who: who, size: size)
                .padding(4)
                .overlay(Circle().strokeBorder(ring, style: StrokeStyle(lineWidth: 2.5, dash: st == nil && who == .me ? [4, 4] : [])))
            Group {
                if let st {
                    if let e = st.emoji, !e.isEmpty {
                        Text(e).font(.system(size: size * 0.26))
                    } else {
                        Image(systemName: statusKind(st.kind).symbol).font(.system(size: size * 0.2, weight: .semibold)).foregroundStyle(.white)
                    }
                } else if who == .me {
                    Image(systemName: "plus").font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(store.meColor.onAccent)
                }
            }
            .frame(width: size * 0.36, height: size * 0.36)
            .background {
                if let st { Circle().fill(Color(hex: statusKind(st.kind).hex)) }
                else if who == .me { Circle().fill(store.meColor) }
            }
            .overlay { if st != nil || who == .me { Circle().stroke(Pal.bg, lineWidth: 2.5) } }
        }
    }
}

/// Маленькая плашка заряда телефона.
struct BatteryChip: View {
    @EnvironmentObject var store: Store
    let who: Who
    var body: some View {
        let b = store.battery(who)
        let level = b?.level ?? 0
        let symbol = b == nil ? "battery.0" : (b!.charging ? "battery.100.bolt" : (level > 0.75 ? "battery.100" : level > 0.5 ? "battery.75" : level > 0.25 ? "battery.50" : "battery.25"))
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2.weight(.semibold))
                .foregroundStyle(b == nil ? Color.secondary : batteryColor(level))
            Text(b.map { "\(Int($0.level * 100))%" } ?? "—").font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Заряд \(store.name(who)): " + (b.map { "\(Int($0.level * 100)) процентов" } ?? "нет данных"))
    }
}

/// Полоска до ближайшей круглой даты.
struct MilestoneBar: View {
    @EnvironmentObject var store: Store
    @State private var shown = false
    var body: some View {
        let m = store.nextMilestone
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [store.meColor, store.partnerColor], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * CGFloat(shown ? m.progress : 0)))
                }
            }
            .frame(height: 6)
            Text("До \(m.day.formatted(.number.locale(ruLocale))) \(daysWord(m.day)) — \(m.left) \(daysWord(m.left))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .onAppear {
            if Demo.screen != nil || Motion.reduced { shown = true } else { withAnimation(Motion.curve(0.9).delay(0.15)) { shown = true } }
        }
    }
}

/// Карточка «Сейчас»: сообщение, дела, ближайшая дата.
struct NowListCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let rows = store.todayNowRows
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    NavigationLink { ModuleView(module: r.module) } label: {
                        HStack(spacing: 12) {
                            let c = Color(hex: r.hex).boosted(minS: 0.5, minB: 0.75)
                            Image(systemName: r.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(c)
                                .frame(width: 36, height: 36).background(c.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                Text(r.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    if i < rows.count - 1 { Divider().padding(.leading, 64) }
                }
            }
            .card()
        }
    }
}

private func sectionTitle(_ t: String) -> some View {
    Text(t).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
}

// MARK: - 1. «Истории»

struct TodayStories: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool

    var body: some View {
        VStack(spacing: 18) {
            stories.staggerIn(0)
            hero.staggerIn(1)
            if !store.todayNowRows.isEmpty {
                VStack(spacing: 10) { sectionTitle("Сейчас"); NowListCard() }.staggerIn(2)
            }
            moodCard.staggerIn(3)
            quickRow.staggerIn(4)
        }
    }

    // Кружки: я, партнёр, история

    private var stories: some View {
        HStack(alignment: .top, spacing: 18) {
            story(.me)
            story(.partner)
            NavigationLink { StatusFeedView() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 24, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 76, height: 76)
                        .glass(Circle(), tint: store.glassTint)
                    Text("История").font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 84)
            }
            .buttonStyle(PressStyle())
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func story(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let label = VStack(spacing: 8) {
            StoryAvatar(who: who, size: 68)
            VStack(spacing: 1) {
                Text(st?.title ?? (who == .me ? "Мой статус" : store.name(.partner)))
                    .font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(st.map { $0.started.agoText } ?? (who == .me ? "добавить" : "без статуса"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 84)
        if who == .me {
            Button { showStatus = true; store.tap() } label: { label }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { label }.buttonStyle(PressStyle())
                .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
        }
    }

    // Крупный счётчик дней

    private var hero: some View {
        let n = store.daysTogether
        let shape = RoundedRectangle(cornerRadius: store.radius, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                BeatingHeart(size: 14)
                Text("Вместе").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text(store.startText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n.formatted(.number.locale(ruLocale)))
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                Text(daysWord(n)).font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }
            MilestoneBar()
            Divider()
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.caption2).foregroundStyle(.secondary)
                    Text(store.distanceKm().map { $0.kmText } ?? (store.p.shareLocation ? "ждём партнёра" : "место скрыто"))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                ForEach(Who.allCases, id: \.self) { w in
                    HStack(spacing: 5) {
                        Circle().fill(store.color(w)).frame(width: 6, height: 6)
                        BatteryChip(who: w)
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [store.meColor.opacity(0.22), store.partnerColor.opacity(0.16), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
        .card()
    }

    // Настроение обоих в одну строку

    private var moodCard: some View {
        NavigationLink { JarView() } label: {
            HStack(spacing: 14) {
                HStack(spacing: -8) {
                    ForEach(Who.allCases, id: \.self) { w in
                        let m = store.lastMood(w)
                        MoodMarble(color: m.map { Color(hex: moodOf($0.mood).hex) } ?? Color.gray.opacity(0.45),
                                   ring: store.color(w), d: 30)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Настроение").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(moodLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("Отметить").font(.footnote.weight(.semibold)).foregroundStyle(store.meColor.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(store.meColor, in: Capsule())
            }
            .padding(.horizontal, 16).padding(.vertical, 14).card()
        }
        .buttonStyle(PressStyle())
    }

    private var moodLine: String {
        var parts: [String] = []
        for w in Who.allCases {
            guard let m = store.lastMood(w) else { continue }
            parts.append(moodOf(m.mood).title)
        }
        return parts.isEmpty ? "Как вы сегодня?" : parts.joined(separator: " · ")
    }

    // Быстрые разделы: одинаковой высоты, пустое состояние — действие

    private var quickRow: some View {
        HStack(spacing: 12) {
            quick("Сон", "moon.zzz", "9DB7FF", store.sleepLine, empty: store.lastSleep(of: .me) == nil) { SleepView() }
            quick("Трекер", "chart.bar", "FFC25C", store.trackerLine, empty: store.trackerLine == "Отметить") { TrackerView() }
            quick("Банка", "sparkles", "7EE0C0", "\(store.data.jar.count) шар.", empty: false) { JarView() }
        }
    }

    private func quick<D: View>(_ title: String, _ icon: String, _ hex: String, _ detail: String, empty: Bool, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 8) {
                ArtIcon(symbol: icon, color: Color(hex: hex), size: 18)
                Spacer(minLength: 0)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(empty ? "+ " + detail : detail).font(.caption.weight(empty ? .semibold : .regular))
                    .foregroundStyle(empty ? AnyShapeStyle(store.meColor) : AnyShapeStyle(Color.secondary)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).frame(height: 116).card()
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - 2. «Сетка»

struct TodayGrid: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    private let gap: CGFloat = 12

    var body: some View {
        VStack(spacing: gap) {
            daysTile.staggerIn(0)
            HStack(spacing: gap) { statusTile(.me); statusTile(.partner) }.staggerIn(1)
            messageTile.staggerIn(2)
            HStack(spacing: gap) {
                moodTile
                VStack(spacing: gap) { sleepTile; tasksTile }
            }.staggerIn(3)
            HStack(spacing: gap) { trackerTile; phonesTile }.staggerIn(4)
        }
    }

    private func box<C: View>(_ h: CGFloat?, tint: Color? = nil, @ViewBuilder _ c: () -> C) -> some View {
        let shape = RoundedRectangle(cornerRadius: store.radius, style: .continuous)
        return c()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: h == nil ? nil : .infinity, alignment: .topLeading)
            .frame(height: h)
            .background(LinearGradient(colors: [(tint ?? .clear).opacity(0.18), (tint ?? .clear).opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
            .card()
    }

    private func tileHead(_ title: String, _ icon: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(c)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // Дни вместе — широкая плитка

    private var daysTile: some View {
        let n = store.daysTogether
        return box(150, tint: store.meColor) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(n.formatted(.number.locale(ruLocale)))
                            .font(.system(size: 50, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        Text("\(daysWord(n)) вместе · \(store.startText)").font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 8)
                    ZStack {
                        HStack(spacing: -14) {
                            AvatarFace(who: .me, size: 50).overlay(Circle().stroke(Pal.bg, lineWidth: 2.5))
                            AvatarFace(who: .partner, size: 50).overlay(Circle().stroke(Pal.bg, lineWidth: 2.5))
                        }
                        BeatingHeart(size: 15).offset(y: 30)
                    }
                }
                Spacer(minLength: 8)
                MilestoneBar()
            }
        }
    }

    // Статус — квадратная плитка на каждого

    @ViewBuilder private func statusTile(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let c = st.map { Color(hex: statusKind($0.kind).hex).boosted(minS: 0.5, minB: 0.8) } ?? store.color(who)
        let tile = box(172, tint: c) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    AvatarFace(who: who, size: 26)
                    Text(who == .me ? "Я" : store.name(who)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 6)
                if let st {
                    StatusGlyph(status: st, size: 44)
                    Spacer(minLength: 6)
                    Text(st.title).font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                    if !st.note.isEmpty {
                        Text(st.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(st.started.agoText).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                } else if who == .me {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(store.meColor)
                        .frame(width: 44, height: 44).background(store.meColor.opacity(0.14), in: Circle())
                    Spacer(minLength: 6)
                    Text("Поставить статус").font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(store.name(.partner)) увидит сразу").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Image(systemName: "moon.stars").font(.system(size: 18)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).background(Color.primary.opacity(0.06), in: Circle())
                    Spacer(minLength: 6)
                    Text("Без статуса").font(.headline).foregroundStyle(.secondary).lineLimit(1)
                    Text("пока тихо").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        if who == .me {
            Button { showStatus = true; store.tap() } label: { tile }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { tile }.buttonStyle(PressStyle())
                .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
        }
    }

    // Последнее сообщение — пузырём, как в чате

    private var messageTile: some View {
        let m = store.data.messages.last
        return NavigationLink { ModuleView(module: .chat) } label: {
            box(nil) {
                HStack(alignment: .center, spacing: 12) {
                    if let m {
                        AvatarFace(who: m.from, size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.text.isEmpty ? "Голосовое сообщение" : m.text).font(.subheadline).foregroundStyle(m.from == .me ? store.meColor.onAccent : .primary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(m.from == .me ? AnyShapeStyle(store.meColor) : AnyShapeStyle(Color.primary.opacity(0.07)),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text((m.from == .me ? "Вы" : store.name(.partner)) + " · " + m.date.agoText)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(store.meColor)
                        Text("Напишите первым").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    // Настроение — высокая плитка, сон и дела — по половинке рядом

    private var moodTile: some View {
        NavigationLink { JarView() } label: {
            box(204, tint: Color(hex: "7EE0C0")) {
                VStack(alignment: .leading, spacing: 0) {
                    tileHead("Настроение", "sparkles", Color(hex: "46C2A5"))
                    Spacer(minLength: 8)
                    HStack(spacing: 12) {
                        ForEach(Who.allCases, id: \.self) { w in
                            let m = store.lastMood(w)
                            VStack(spacing: 6) {
                                MoodMarble(color: m.map { Color(hex: moodOf($0.mood).hex) } ?? Color.gray.opacity(0.45),
                                           ring: store.color(w), d: 44)
                                Text(m.map { moodOf($0.mood).title } ?? "—").font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(store.lastMood(.me) == nil ? "+ Отметить своё" : "Банка: \(store.data.jar.count) шар.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.lastMood(.me) == nil ? AnyShapeStyle(store.meColor) : AnyShapeStyle(Color.secondary))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private var sleepTile: some View {
        NavigationLink { SleepView() } label: {
            box(96, tint: Color(hex: "9DB7FF")) {
                VStack(alignment: .leading, spacing: 0) {
                    tileHead("Сон", "moon.zzz.fill", Color(hex: "7E9BFF"))
                    Spacer(minLength: 4)
                    let e = store.lastSleep(of: .me)
                    Text(e.map { hoursText($0.hours) } ?? "+ Записать").font(.subheadline.weight(.semibold))
                        .foregroundStyle(e == nil ? AnyShapeStyle(store.meColor) : AnyShapeStyle(Color.primary)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private var tasksTile: some View {
        let open = store.data.tasks.filter { !$0.done && $0.owner != .partner }
        return NavigationLink { ModuleView(module: .tasks) } label: {
            box(96, tint: Color(hex: "3DBE8B")) {
                VStack(alignment: .leading, spacing: 0) {
                    tileHead("Дела", "checklist", Color(hex: "3DBE8B"))
                    Spacer(minLength: 4)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(open.count)").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.primary)
                        Text(open.contains { $0.priority > 0 } ? "есть важные" : "впереди").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private var trackerTile: some View {
        NavigationLink { TrackerView() } label: {
            box(96, tint: Color(hex: "FFC25C")) {
                VStack(alignment: .leading, spacing: 0) {
                    tileHead("Трекер", "chart.bar.fill", Color(hex: "F0A830"))
                    Spacer(minLength: 4)
                    Text(store.trackerLine == "Отметить" ? "+ Отметить" : store.trackerLine).font(.subheadline.weight(.semibold))
                        .foregroundStyle(store.trackerLine == "Отметить" ? AnyShapeStyle(store.meColor) : AnyShapeStyle(Color.primary)).lineLimit(1)
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private var phonesTile: some View {
        box(96) {
            VStack(alignment: .leading, spacing: 0) {
                tileHead(store.distanceKm().map { "Между вами " + $0.kmText } ?? "Телефоны", "location.fill", .secondary)
                Spacer(minLength: 4)
                ForEach(Who.allCases, id: \.self) { w in
                    HStack(spacing: 6) {
                        Circle().fill(store.color(w)).frame(width: 6, height: 6)
                        Text(store.name(w)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        BatteryChip(who: w)
                    }
                }
            }
        }
    }
}

// MARK: - 3. «Пара»

struct TodayPair: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool

    var body: some View {
        VStack(spacing: 18) {
            pairCard.staggerIn(0)
            if !store.todayNowRows.isEmpty {
                VStack(spacing: 10) { sectionTitle("Сейчас"); NowListCard() }.staggerIn(1)
            }
            linksCard.staggerIn(2)
        }
    }

    private var pairCard: some View {
        let n = store.daysTogether
        let shape = RoundedRectangle(cornerRadius: max(store.radius, 24), style: .continuous)
        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                person(.me)
                VStack(spacing: 4) {
                    BeatingHeart(size: 18).padding(.top, 22)
                    Text(n.formatted(.number.locale(ruLocale)))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("\(daysWord(n))\nвместе").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(width: 92)
                person(.partner)
            }
            MilestoneBar()
            HStack(spacing: 10) {
                Button { showStatus = true; store.tap() } label: {
                    Label(store.statusNow(.me) == nil ? "Поставить статус" : "Сменить статус", systemImage: "sparkle")
                        .font(.footnote.weight(.semibold)).foregroundStyle(store.meColor.onAccent).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(store.meColor, in: Capsule())
                }
                .buttonStyle(PressStyle())
                NavigationLink { JarView() } label: {
                    Label("Настроение", systemImage: "face.smiling")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .glass(Capsule(), tint: store.glassTint, interactive: true)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(18)
        .background {
            ZStack {
                RadialGradient(colors: [store.meColor.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
                RadialGradient(colors: [store.partnerColor.opacity(0.26), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
            }
            .clipShape(shape)
        }
        .card()
    }

    @ViewBuilder private func person(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let m = store.lastMood(who)
        let col = VStack(spacing: 6) {
            StoryAvatar(who: who, size: 76)
            Text(who == .me ? "Я" : store.name(who)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(st?.title ?? "Без статуса")
                .font(.subheadline.weight(.semibold)).foregroundStyle(st == nil ? Color.secondary : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(st.map { $0.note.isEmpty ? $0.started.agoText : $0.note } ?? " ")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                if let m {
                    HStack(spacing: 3) {
                        Circle().fill(Color(hex: moodOf(m.mood).hex)).frame(width: 7, height: 7)
                        Text(moodOf(m.mood).title).font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                BatteryChip(who: who)
            }
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        if who == .me {
            Button { showStatus = true; store.tap() } label: { col }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { col }.buttonStyle(PressStyle())
                .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
        }
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            link("Сон", "moon.zzz", "9DB7FF", store.sleepLine) { SleepView() }
            Divider().padding(.leading, 62)
            link("Трекер", "chart.bar", "FFC25C", store.trackerLine) { TrackerView() }
            Divider().padding(.leading, 62)
            link("Между вами", "location", "8EC5FF", store.distanceKm().map { $0.kmText } ?? (store.p.shareLocation ? "Ждём партнёра" : "Скрыто")) { ModuleView(module: .places) }
            Divider().padding(.leading, 62)
            link("История статусов", "clock.arrow.circlepath", "C5A3FF", "") { StatusFeedView() }
        }
        .card()
    }

    private func link<D: View>(_ title: String, _ icon: String, _ hex: String, _ detail: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 12) {
                ArtIcon(symbol: icon, color: Color(hex: hex), size: 17)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 8)
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
