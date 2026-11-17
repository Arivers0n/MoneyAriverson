import SwiftUI

// MARK: - Варианты оформления экрана «Сегодня»
// Каждый вариант — свой мир: палитра, шрифт и один главный приём. Навигация и элементы — родные iOS.

enum TodayStyle: String, CaseIterable, Identifiable {
    case pismo, dvoe, scena, fridge, pogoda, foto, bilet, kasseta, okna, racia, ostrova, classic

    static let key = "todayStyle"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pismo: return "Письмо"
        case .dvoe: return "Двое"
        case .scena: return "Сцена"
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
        case .fridge: return "Статусы — записки на магнитах, дела — список покупок."
        case .pogoda: return "Настроение каждого — погода на его половине неба."
        case .foto: return "Ваш день — две фотополоски из статусов и настроений."
        case .bilet: return "Билет с расстоянием и датой следующей встречи."
        case .kasseta: return "Сторона А и Б: день каждого как список треков."
        case .okna: return "Два окна ночью: свет — настроение, новое светится, пока не увидишь."
        case .racia: return "Большая кнопка: удерживай и скажи голосом."
        case .ostrova: return "Два цветных острова и крупные статусы."
        case .classic: return "Вид, который был раньше, в цветах вашей темы."
        }
    }

    /// Цвета для плитки выбора.
    var swatch: (String, String) {
        switch self {
        case .pismo: return ("F1F2EE", "1C2433")
        case .dvoe: return ("0E1730", "FF8A3D")
        case .scena: return ("1B2672", "F6B5CC")
        case .fridge: return ("D6E5DC", "FFD9E6")
        case .pogoda: return ("5FA5E6", "8E9AB0")
        case .foto: return ("6A1E30", "FAF8F4")
        case .bilet: return ("EDF1F5", "E2483D")
        case .kasseta: return ("F3F4F7", "2A4BA0")
        case .okna: return ("1A2040", "FFC46B")
        case .racia: return ("EEF1F6", "E2551B")
        case .ostrova: return ("8ED462", "EBC1FF")
        case .classic: return ("9AA5B8", "D7DCE5")
        }
    }

    var dark: Bool { [.dvoe, .scena, .pogoda, .foto, .okna].contains(self) }
    var bigTitle: Bool { ![.scena, .ostrova].contains(self) }

    /// Цвет текста шапки.
    var ink: Color {
        switch self {
        case .pismo: return Color(hex: "1C2433")
        case .fridge: return Color(hex: "1F2B26")
        case .bilet: return Color(hex: "142033")
        case .kasseta: return Color(hex: "1A2340")
        case .racia: return Color(hex: "161C2B")
        case .ostrova: return Color(hex: "2C2E2A")
        case .classic: return .primary
        default: return .white
        }
    }
}

// MARK: - Фон каждого варианта (неподвижный, за прокруткой)

struct TodayStyleBackground: View {
    @EnvironmentObject var store: Store
    let style: TodayStyle

    var body: some View {
        switch style {
        case .pismo:
            ZStack {
                Color(hex: "F1F2EE")
                GrainDots(color: Color(hex: "1C2433").opacity(0.05))
            }
        case .dvoe:
            ZStack {
                Color(hex: "0E1730")
                RadialGradient(colors: [store.meColor.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [store.partnerColor.opacity(0.26), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
            }
        case .scena:
            ZStack {
                Color(hex: "1B2672")
                RadialGradient(colors: [store.partnerColor.opacity(0.75), .clear], center: UnitPoint(x: 0.85, y: 0.05), startRadius: 0, endRadius: 380)
                RadialGradient(colors: [store.meColor.opacity(0.65), .clear], center: UnitPoint(x: 0, y: 0.42), startRadius: 0, endRadius: 330)
                RadialGradient(colors: [Color(hex: "406EE6").opacity(0.5), .clear], center: UnitPoint(x: 0.6, y: 0.6), startRadius: 0, endRadius: 300)
                GrainDots(color: .white.opacity(0.06))
            }
        case .fridge:
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [Color(hex: "D3E3DA"), Color(hex: "DFECE4"), Color(hex: "D6E5DC"), Color(hex: "C9DACF")],
                               startPoint: .leading, endPoint: .trailing)
                BrushedLines()
                LinearGradient(colors: [.black.opacity(0.06), .white.opacity(0.5), .black.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
            }
        case .pogoda:
            LinearGradient(colors: [Color(hex: "34486F"), Color(hex: "26365A")], startPoint: .top, endPoint: .bottom)
        case .foto:
            ZStack {
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { _ in
                        LinearGradient(colors: [Color(hex: "5A1627"), Color(hex: "7A2337"), Color(hex: "5A1627")], startPoint: .leading, endPoint: .trailing)
                    }
                }
                RadialGradient(colors: [Color(hex: "FFDCC8").opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 360)
                LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
        case .bilet: Color(hex: "EDF1F5")
        case .kasseta: Color(hex: "F3F4F7")
        case .okna:
            LinearGradient(colors: [Color(hex: "151A33"), Color(hex: "232A4E"), Color(hex: "1A2040")], startPoint: .top, endPoint: .bottom)
        case .racia: Color(hex: "EEF1F6")
        case .ostrova: Color(hex: "F5F1E4")
        case .classic: ThemeBackground()
        }
    }
}

/// Лёгкое зерно из точек. Рисуется один раз, без анимации.
struct GrainDots: View {
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
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.10)))
                x += 4
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Шапка (не двигается при прокрутке)

struct TodayStyleHeader: View {
    @EnvironmentObject var store: Store
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
                    .foregroundStyle(style.ink.opacity(style.bigTitle ? 0.68 : 0.9))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            NavigationLink { ModuleView(module: .chat) } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(style == .classic ? store.meColor : style.ink)
                    .frame(width: 44, height: 44)
                    .glass(Circle(), tint: style == .classic ? store.glassTint : nil, interactive: true)
                    .overlay(alignment: .topTrailing) {
                        if unread {
                            Circle().fill(store.partnerColor).frame(width: 11, height: 11)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2)).offset(x: 1, y: -1)
                        }
                    }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(unread ? "Чат, есть новое сообщение" : "Чат")
        }
        .foregroundStyle(style.ink)
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
                        Circle().fill(Color(hex: "E2483D")).frame(width: 8, height: 8).accessibilityLabel("важное")
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
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(TodayStyle.allCases) { s in tile(s) }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            Text((TodayStyle(rawValue: selection) ?? .pismo).about)
                .font(.caption).foregroundStyle(.secondary)
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
                ZStack(alignment: .bottomTrailing) {
                    shape.fill(Color(hex: s.swatch.0))
                    Circle().fill(Color(hex: s.swatch.1)).frame(width: 30, height: 30).padding(10)
                }
                .frame(width: 76, height: 96)
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
