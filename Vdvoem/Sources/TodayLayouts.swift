import SwiftUI

// MARK: - Общие данные и детали для всех видов экрана «Сегодня»

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
