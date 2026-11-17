import SwiftUI

// MARK: - Варианты оформления экрана «Сегодня»
// Каждый вариант — свой приём и своя раскладка. Цвета у всех общие: их даёт выбранная тема
// (см. TodayPalette), поэтому любой вариант подстраивается под тему, светлый и тёмный режим.

enum TodayStyle: String, CaseIterable, Identifiable {
    case pismo, dvoe, scena, widgets, journal, lenta, fridge, pogoda, foto, bilet, kasseta, okna, racia, ostrova, classic

    static let key = "todayStyle"
    var id: String { rawValue }

    /// Сохранённый вариант (для скриншотов в CI — аргумент `-layout <имя>`).
    static var stored: TodayStyle {
        TodayStyle(rawValue: Demo.value("-layout") ?? UserDefaults.standard.string(forKey: key) ?? "") ?? .pismo
    }

    var title: String {
        switch self {
        case .pismo: return "Письмо"
        case .dvoe: return "Двое"
        case .scena: return "Сцена"
        case .widgets: return "Виджеты"
        case .journal: return "Журнал"
        case .lenta: return "Лента дня"
        case .fridge: return "Холодильник"
        case .pogoda: return "Погода"
        case .foto: return "Фотобудка"
        case .bilet: return "До встречи"
        case .kasseta: return "Кассета"
        case .okna: return "Два окна"
        case .racia: return "Рация"
        case .ostrova: return "Острова"
        case .classic: return "Прежний"
        }
    }

    var about: String {
        switch self {
        case .pismo: return "Одна фраза о том, как вы сейчас, крупным шрифтом с засечками."
        case .dvoe: return "Две зеркальные половины: вы и партнёр. Ответить можно прямо отсюда."
        case .scena: return "Вы двое на живом фоне, статусы облачками, снизу шторка с главным."
        case .widgets: return "Плитки как на экране «Домой»: партнёр, вы, дни вместе, настроение, сон, дела."
        case .journal: return "Обложка журнала о вас двоих: главная новость дня и анонсы."
        case .lenta: return "День обоих на одной линии времени: слева вы, справа партнёр."
        case .fridge: return "Статусы — записки на магнитах, дела — список покупок."
        case .pogoda: return "Настроение каждого — погода на его половине неба."
        case .foto: return "Ваш день — две фотополоски из статусов и настроений."
        case .bilet: return "Билет с расстоянием и датой следующей встречи."
        case .kasseta: return "Сторона А и Б: день каждого как список треков."
        case .okna: return "Два окна: свет — настроение, новое светится, пока не увидишь."
        case .racia: return "Большая кнопка: удерживай и скажи голосом."
        case .ostrova: return "Два острова в цветах пары и крупные статусы."
        case .classic: return "Вид, который был раньше."
        }
    }

    /// Крупный заголовок «Сегодня» в шапке.
    var bigTitle: Bool { ![.scena, .ostrova, .journal].contains(self) }
}

// MARK: - Фон каждого варианта (неподвижный, за прокруткой)

struct TodayStyleBackground: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    let style: TodayStyle

    var body: some View {
        let pal = TodayPalette.make(store, scheme)
        Group {
            switch style {
            case .classic, .widgets:
                ThemeBackground()
            default:
                ZStack {
                    pal.bg
                    motif(pal)
                }
            }
        }
        .id(store.p.themeID + "\(store.p.myHex)\(store.p.partnerHex)")
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    /// Мягкий тон темы сверху.
    private func topTone(_ pal: TodayPalette, _ share: CGFloat = 0.45) -> some View {
        GeometryReader { g in
            LinearGradient(colors: [pal.top, pal.top.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: g.size.height * share)
        }
    }

    @ViewBuilder private func motif(_ pal: TodayPalette) -> some View {
        switch style {
        case .pismo:
            topTone(pal, 0.35)
            GrainDots(color: pal.ink.opacity(pal.dark ? 0.05 : 0.045))
        case .dvoe:
            RadialGradient(colors: [pal.me.opacity(pal.dark ? 0.32 : 0.20), .clear], center: .topLeading, startRadius: 0, endRadius: 340)
            RadialGradient(colors: [pal.partner.opacity(pal.dark ? 0.28 : 0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 340)
        case .scena:
            // Сцена сверху, ниже — цвет шторки: если шторку потянуть, под ней не будет «дыры».
            GeometryReader { g in
                VStack(spacing: 0) {
                    stage(pal).frame(height: g.size.height * 0.72)
                    pal.card
                }
            }
        case .journal:
            GrainDots(color: pal.ink.opacity(0.04))
        case .lenta, .kasseta, .racia:
            topTone(pal, 0.4)
        case .fridge:
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [pal.field, HSB.mix(pal.field, pal.dark ? pal.card : .white, 0.35), pal.field, pal.field.hsb(dB: -0.03)],
                               startPoint: .leading, endPoint: .trailing)
                BrushedLines(opacity: pal.dark ? 0.035 : 0.10)
                LinearGradient(colors: [.black.opacity(0.06), .white.opacity(pal.dark ? 0.12 : 0.5), .black.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
            }
        case .pogoda:
            LinearGradient(colors: [pal.dark ? pal.deep : pal.top, pal.bg], startPoint: .top, endPoint: .bottom)
        case .foto:
            let base = pal.dark ? pal.deep : pal.top
            ZStack {
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { _ in
                        LinearGradient(colors: [base.hsb(dB: -0.07), base.hsb(dB: 0.05), base.hsb(dB: -0.07)], startPoint: .leading, endPoint: .trailing)
                    }
                }
                RadialGradient(colors: [Color.white.opacity(pal.dark ? 0.14 : 0.35), .clear], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: 360)
                LinearGradient(colors: [.black.opacity(pal.dark ? 0.25 : 0.04), .clear, .black.opacity(pal.dark ? 0.35 : 0.06)], startPoint: .top, endPoint: .bottom)
            }
        case .okna:
            LinearGradient(colors: pal.dark ? [pal.deep.hsb(dB: -0.06), pal.bg] : [pal.top, pal.bg], startPoint: .top, endPoint: .bottom)
            GrainDots(color: pal.ink.opacity(0.035))
        case .ostrova:
            GrainDots(color: pal.ink.opacity(0.03))
        default:
            EmptyView()
        }
    }

    private func stage(_ pal: TodayPalette) -> some View {
        ZStack {
            LinearGradient(colors: pal.dark ? [pal.deep, HSB.mix(pal.deep, pal.bg, 0.5)] : [pal.top, HSB.mix(pal.top, pal.bg, 0.5)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [pal.partner.opacity(pal.dark ? 0.62 : 0.42), .clear], center: UnitPoint(x: 0.85, y: 0.05), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [pal.me.opacity(pal.dark ? 0.55 : 0.36), .clear], center: UnitPoint(x: 0, y: 0.5), startRadius: 0, endRadius: 330)
            GrainDots(color: (pal.dark ? Color.white : pal.ink).opacity(0.05))
        }
    }
}

/// Лёгкое зерно из точек. Рисуется один раз, без анимации.
struct GrainDots: View, Equatable {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : 1.5
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(color))
                    x += 3
                }
                y += 3; row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// Шлифованная эмаль: тонкие вертикальные полосы.
struct BrushedLines: View {
    var opacity: Double = 0.10
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(opacity)))
                x += 4
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Шапка (не двигается при прокрутке)

struct TodayStyleHeader: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    let style: TodayStyle
    let subtitle: String
    let unread: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if style.bigTitle {
                    Text("Сегодня").font(.system(size: 34, weight: .bold)).tracking(-0.6)
                }
                Text(subtitle)
                    .font(style.bigTitle ? .body : .headline)
                    .foregroundStyle(style.bigTitle ? pal.muted : pal.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            NavigationLink { ModuleView(module: .chat) } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(pal.meText)
                    .frame(width: 44, height: 44)
                    .glass(Circle(), tint: store.glassTint, interactive: true)
                    .overlay(alignment: .topTrailing) {
                        if unread {
                            Circle().fill(store.partnerColor).frame(width: 11, height: 11)
                                .overlay(Circle().stroke(pal.bg, lineWidth: 2)).offset(x: 1, y: -1)
                        }
                    }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(unread ? "Чат, есть новое сообщение" : "Чат")
        }
        .foregroundStyle(pal.ink)
        .padding(.top, 4)
    }
}

// MARK: - Данные дня

struct DayEntry: Identifiable {
    let id: String
    let date: Date
    let who: Who
    let title: String
    let hex: String
    let symbol: String
    let emoji: String?
    let status: StatusItem?
}

struct MoodWeather {
    let word: String
    let top: String
    let bottom: String
    let symbol: String
    let sunny: Bool
    let rainy: Bool
}

func moodWeather(_ mood: Int?) -> MoodWeather {
    switch mood {
    case 0: return MoodWeather(word: "Ясно", top: "2F7FD6", bottom: "F3C27F", symbol: "sun.max.fill", sunny: true, rainy: false)
    case 1: return MoodWeather(word: "Облачно", top: "3E8ACB", bottom: "A9D3F0", symbol: "cloud.sun.fill", sunny: true, rainy: false)
    case 2: return MoodWeather(word: "Дождь", top: "3B4A6B", bottom: "7D8BA6", symbol: "cloud.rain.fill", sunny: false, rainy: true)
    case 3: return MoodWeather(word: "Гроза", top: "2B2540", bottom: "6A4E7A", symbol: "cloud.bolt.rain.fill", sunny: false, rainy: true)
    case 4: return MoodWeather(word: "Туман", top: "46597D", bottom: "8E9AB0", symbol: "cloud.fog.fill", sunny: false, rainy: false)
    default: return MoodWeather(word: "Тихо", top: "3A4A6A", bottom: "6C7A96", symbol: "moon.stars.fill", sunny: false, rainy: false)
    }
}

func timeText(_ d: Date) -> String {
    d.formatted(Date.FormatStyle().locale(ruLocale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
}

func inDaysText(_ n: Int) -> String {
    switch n {
    case 0: return "сегодня"
    case 1: return "завтра"
    default: return "через \(n) \(daysWord(n))"
    }
}

extension StatusItem {
    /// Место и заметка через запятую.
    var detailLine: String { [place, note].filter { !$0.isEmpty }.joined(separator: ", ") }
}

extension Store {
    /// Статусы и настроения за сегодня, новые сверху.
    func dayEntries(_ who: Who? = nil) -> [DayEntry] {
        let cal = Calendar.current
        var out: [DayEntry] = []
        for s in data.statuses where cal.isDateInToday(s.started) && (who == nil || s.who == who) {
            let k = statusKind(s.kind)
            out.append(DayEntry(id: "s" + s.id.uuidString, date: s.started, who: s.who, title: s.title,
                                hex: k.hex, symbol: k.symbol, emoji: s.emoji, status: s))
        }
        for b in data.jar where cal.isDateInToday(b.date) && (who == nil || b.who == who) {
            let m = moodOf(b.mood)
            out.append(DayEntry(id: "j" + b.id.uuidString, date: b.date, who: b.who, title: m.title,
                                hex: m.hex, symbol: "sparkles", emoji: nil, status: nil))
        }
        return out.sorted { $0.date > $1.date }
    }

    var openTasks: [TaskItem] { data.tasks.filter { !$0.done && $0.owner != .partner } }

    var lastPartnerMessage: ChatMessage? { data.messages.last { $0.from == .partner } }

    func sendText(_ t: String) {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        data.messages.append(ChatMessage(text: s, from: .me))
        tap()
        sfx(.send)
    }

    func hug() {
        sendSignal("hug")
        Toasts.shared.show("\(name(.partner)) получит «Обнимаю»", symbol: "heart.fill")
    }

    /// Ближайшая встреча из календаря и сколько до неё дней.
    var nextMeeting: (EventItem, Int)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let e = data.events.filter({ $0.meeting == true && cal.startOfDay(for: $0.date) >= today }).min(by: { $0.date < $1.date })
        else { return nil }
        return (e, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: e.date)).day ?? 0)
    }

    func setMeeting(_ date: Date?) {
        var d = data
        let today = Calendar.current.startOfDay(for: Date())
        let idx = d.events.firstIndex { $0.meeting == true && Calendar.current.startOfDay(for: $0.date) >= today }
        if let date {
            if let i = idx { d.events[i].date = date }
            else {
                var e = EventItem(title: "Встреча", date: date, emoji: "🚆")
                e.meeting = true
                d.events.append(e)
            }
        } else if let i = idx {
            d.events.remove(at: i)
        }
        data = d
        tap()
    }

    /// Время суток словом.
    var dayPart: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "утро"
        case 12..<18: return "день"
        case 18..<23: return "вечер"
        default: return "ночь"
        }
    }
}

// MARK: - Общие элементы

/// Дело с галочкой: отмечается прямо на экране «Сегодня».
struct TaskCheckRow: View {
    @EnvironmentObject var store: Store
    let task: TaskItem
    var accent: Color
    var ink: Color
    var muted: Color
    var font: Font = .body
    /// В узком месте «важное» — точкой, чтобы не обрезать название.
    var compact = false

    var body: some View {
        Button {
            guard let i = store.data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            withAnimation(Motion.spring) { store.data.tasks[i].done.toggle() }
            store.tap()
            store.sfx(.done)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(task.done ? accent : muted)
                    .contentTransition(.symbolEffect(.replace))
                Text(task.title).font(font).foregroundStyle(ink).strikethrough(task.done).lineLimit(compact ? 2 : 1)
                Spacer(minLength: 8)
                if task.priority > 0 {
                    if compact {
                        Circle().fill(accent).frame(width: 8, height: 8).accessibilityLabel("важное")
                    } else {
                        Text("важное").font(.footnote.weight(.semibold)).foregroundStyle(accent)
                    }
                }
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(task.title + (task.done ? ", сделано" : ""))
    }
}

/// Дата следующей встречи.
struct MeetingSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("Дата встречи", selection: $date, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, ruLocale)
                Button { store.setMeeting(date); dismiss() } label: { Text("Сохранить").bigButton() }
                    .buttonStyle(PressStyle())
                if store.nextMeeting != nil {
                    Button("Убрать встречу", role: .destructive) { store.setMeeting(nil); dismiss() }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Следующая встреча")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .presentationDetents([.large])
        .onAppear { if let (e, _) = store.nextMeeting { date = e.date } }
    }
}


// MARK: - Плитки выбора в «Оформлении»

struct TodayStylePicker: View {
    @EnvironmentObject var store: Store
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(TodayStyle.allCases) { s in tile(s).id(s.rawValue) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
            }
            Text((TodayStyle(rawValue: selection) ?? .pismo).about)
                .font(.caption).foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(Motion.curve(0.2), value: selection)
        }
    }

    private func tile(_ s: TodayStyle) -> some View {
        let on = selection == s.rawValue
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            guard !on else { return }
            withAnimation(Motion.spring) { selection = s.rawValue }
            store.tap()
            store.sfx(.pop)
        } label: {
            VStack(spacing: 8) {
                TodayStyleThumb(style: s)
                    .frame(width: 76, height: 104)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(on ? store.meColor : Color.primary.opacity(0.12), lineWidth: on ? 2.5 : 1))
                Text(s.title).font(.caption.weight(on ? .semibold : .regular)).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(width: 84)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(s.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Миниатюра варианта в цветах текущей темы: видно, как он будет выглядеть, ещё до выбора.
struct TodayStyleThumb: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    let style: TodayStyle

    var body: some View {
        let p = TodayPalette.make(store, scheme)
        ZStack(alignment: .topLeading) {
            backdrop(p)
            sketch(p).padding(8)
        }
        .frame(width: 76, height: 104)
        .environment(\.todayPalette, p)
    }

    @ViewBuilder private func backdrop(_ p: TodayPalette) -> some View {
        switch style {
        case .scena:
            VStack(spacing: 0) {
                ZStack {
                    p.dark ? p.deep : p.top
                    RadialGradient(colors: [p.partner.opacity(0.6), .clear], center: .topTrailing, startRadius: 0, endRadius: 60)
                    RadialGradient(colors: [p.me.opacity(0.5), .clear], center: .leading, startRadius: 0, endRadius: 50)
                }
                .frame(height: 62)
                p.card
            }
        case .fridge: p.field
        case .foto: p.dark ? p.deep : p.top
        case .pogoda, .okna: LinearGradient(colors: [p.dark ? p.deep : p.top, p.bg], startPoint: .top, endPoint: .bottom)
        case .widgets, .classic: LinearGradient(colors: [p.top, p.bg], startPoint: .top, endPoint: .center)
        default: p.bg
        }
    }

    private func bar(_ c: Color, _ w: CGFloat, _ h: CGFloat = 4) -> some View {
        Capsule().fill(c).frame(width: w, height: h)
    }

    @ViewBuilder private func sketch(_ p: TodayPalette) -> some View {
        switch style {
        case .pismo:
            VStack(alignment: .leading, spacing: 5) {
                bar(p.ink, 54, 6); bar(p.ink, 44, 6); bar(p.ink, 50, 6)
                bar(p.muted.opacity(0.6), 40).padding(.top, 4)
                HStack(spacing: 4) { bar(p.ink, 26, 9); bar(p.card, 22, 9) }.padding(.top, 4)
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 4).fill(p.card).frame(width: 28, height: 22); RoundedRectangle(cornerRadius: 4).fill(p.card).frame(width: 28, height: 22) }
            }
        case .dvoe:
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [p.me.opacity(0.4), p.me.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [p.partner.opacity(0.4), p.partner.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            }
            .frame(height: 58)
            .overlay(Circle().fill(p.card).frame(width: 18).overlay(Image(systemName: "heart.fill").font(.system(size: 7)).foregroundStyle(p.partner)))
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 6).fill(p.card.opacity(0.7)).frame(height: 18).offset(y: 26) }
        case .scena:
            ZStack(alignment: .topLeading) {
                Circle().fill(p.me).frame(width: 18).overlay(Circle().stroke(p.card, lineWidth: 2)).offset(x: 6, y: 30)
                Circle().fill(p.partner).frame(width: 18).overlay(Circle().stroke(p.card, lineWidth: 2)).offset(x: 38, y: 18)
                RoundedRectangle(cornerRadius: 5).fill(p.card.opacity(0.9)).frame(width: 30, height: 10).offset(x: 28, y: 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) { bar(p.ink, 18, 7); bar(p.ink.opacity(0.1), 18, 7); bar(p.partner.opacity(0.25), 16, 7) }
                    bar(p.muted.opacity(0.5), 46); bar(p.muted.opacity(0.5), 40)
                }
                .offset(y: 60)
            }
        case .widgets:
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 7).fill(p.card).frame(height: 26)
                    .overlay(alignment: .leading) { Circle().fill(p.partner).frame(width: 14).padding(.leading, 5) }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 7).fill(p.card).overlay(Circle().fill(p.me).frame(width: 10))
                    RoundedRectangle(cornerRadius: 7).fill(p.card).overlay(Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(p.partner))
                }
                .frame(height: 26)
                RoundedRectangle(cornerRadius: 7).fill(p.card).frame(height: 22)
            }
        case .journal:
            VStack(alignment: .leading, spacing: 4) {
                Text("ВДВОЁМ").font(.custom("Georgia-Bold", size: 13)).foregroundStyle(p.ink).lineLimit(1).minimumScaleFactor(0.5)
                Rectangle().fill(p.ink).frame(height: 1)
                bar(p.partnerText, 48, 6); bar(p.partnerText, 36, 6)
                bar(p.muted.opacity(0.6), 46).padding(.top, 2)
                ForEach(0..<3, id: \.self) { _ in HStack(spacing: 3) { bar(p.meText, 6, 6); bar(p.ink.opacity(0.5), 38) } }
            }
        case .lenta:
            ZStack(alignment: .top) {
                Rectangle().fill(p.faint).frame(width: 1.5, height: 80).frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 3) {
                            if i % 2 == 0 { bar(p.me.opacity(0.5), 18, 6) } else { Spacer().frame(width: 18) }
                            Circle().fill(i % 2 == 0 ? p.me : p.partner).frame(width: 7)
                            if i % 2 == 1 { bar(p.partner.opacity(0.5), 18, 6) } else { Spacer().frame(width: 18) }
                        }
                    }
                }
                .padding(.top, 6)
            }
        case .fridge:
            ZStack(alignment: .topLeading) {
                Rectangle().fill(p.paper).frame(width: 26, height: 32).rotationEffect(.degrees(-4)).offset(x: 2, y: 6)
                Rectangle().fill(p.wash(p.partner, 0.3)).frame(width: 26, height: 22).rotationEffect(.degrees(3)).offset(x: 32, y: 4)
                Rectangle().fill(p.wash(p.me, 0.3)).frame(width: 26, height: 22).rotationEffect(.degrees(-2)).offset(x: 32, y: 32)
                Rectangle().fill(p.paper).frame(width: 30, height: 30).rotationEffect(.degrees(2)).offset(x: 2, y: 48)
                Circle().fill(p.partner).frame(width: 7).offset(x: 42, y: 1)
            }
        case .pogoda:
            HStack(spacing: 1) {
                LinearGradient(colors: [Color(hex: "2F7FD6"), Color(hex: "F3C27F")], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Color(hex: "46597D"), Color(hex: "8E9AB0")], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
        case .foto:
            HStack(alignment: .top, spacing: 6) {
                ForEach(0..<2, id: \.self) { k in
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in Rectangle().fill(k == 0 ? p.me.opacity(0.7) : p.partner.opacity(0.7)).frame(height: 16) }
                    }
                    .padding(2).padding(.bottom, 5).background(Color(hex: "FAF8F4"))
                    .rotationEffect(.degrees(k == 0 ? -3 : 3))
                }
            }
            .padding(.horizontal, 4).padding(.top, 4)
        case .bilet:
            VStack(spacing: 0) {
                HStack { bar(p.meText, 14, 5); Spacer(); bar(p.partnerText, 14, 5) }.padding(6)
                Rectangle().fill(p.line).frame(height: 1)
                bar(p.ink, 34, 7).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            .background(p.card, in: RoundedRectangle(cornerRadius: 7))
            .padding(.top, 6)
        case .kasseta:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) { p.partner; HSB.mix(p.me, p.partner, 0.5); p.me }.frame(height: 4)
                VStack(alignment: .leading, spacing: 4) {
                    bar(p.meText, 36, 6)
                    ForEach(0..<3, id: \.self) { _ in bar(p.faint.opacity(0.6), 44, 3) }
                }
                .padding(6)
            }
            .background(p.card, in: RoundedRectangle(cornerRadius: 7))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.top, 12)
        case .okna:
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { k in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(RadialGradient(colors: [Color(hex: k == 0 ? "B9A7F5" : "FFC46B").opacity(0.9), Color(hex: k == 0 ? "6E5BD0" : "E8902E")], center: .bottom, startRadius: 0, endRadius: 40))
                        .overlay(Rectangle().fill(p.dark ? p.deep : p.card).frame(width: 2))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.dark ? p.deep.hsb(dB: 0.08) : p.card, lineWidth: 3))
                        .frame(height: 50)
                }
            }
            .padding(.top, 8)
        case .racia:
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(p.card).frame(height: 18)
                Circle().fill(RadialGradient(colors: [p.me.hsb(dS: -0.15, dB: 0.15), p.me], center: .center, startRadius: 0, endRadius: 22))
                    .frame(width: 40).overlay(Circle().stroke(p.me.opacity(0.25), lineWidth: 1).padding(-6))
                    .frame(maxWidth: .infinity)
            }
        case .ostrova:
            ZStack(alignment: .topLeading) {
                Ellipse().fill(p.wash(p.me, 0.6)).frame(width: 70, height: 56).offset(x: -26, y: -20)
                Ellipse().fill(p.wash(p.partner, 0.55)).frame(width: 70, height: 60).offset(x: 20, y: 34)
                bar(p.ink, 28, 7).offset(y: 6)
                bar(p.ink, 28, 7).offset(x: 32, y: 66)
            }
        case .classic:
            VStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 6).fill(p.card.opacity(0.85)).frame(height: 16) }
            }
            .padding(.top, 8)
        }
    }
}
