import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData { didSet { save(); sync.dataChanged(data) } }
    @Published var scope: Scope = .we
    let sync = SyncEngine()
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent("vdvoem.json")
        if let d = try? Data(contentsOf: url),
           let a = try? JSONDecoder().decode(AppData.self, from: d) {
            data = a
        } else {
            data = AppData()
        }
        sync.attach(self)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) {
            try? d.write(to: url, options: .atomic)
        }
    }

    func resetAll() { data = AppData(); scope = .we }

    // MARK: Профиль и тема
    var p: Profile { data.profile }
    var radius: CGFloat { CGFloat(p.radius) }
    var meColor: Color { Color(hex: p.myHex) }
    var partnerColor: Color { Color(hex: p.partnerHex) }
    var scheme: ColorScheme? {
        switch p.theme {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    func color(_ w: Who?) -> Color {
        switch w {
        case .me: return meColor
        case .partner: return partnerColor
        case nil: return .secondary
        }
    }

    func name(_ w: Who) -> String {
        let n = (w == .me ? p.myName : p.partnerName).trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return w == .me ? "Я" : "Партнёр" }
        return n
    }

    var scopeTitle: String {
        switch scope {
        case .we: return "Мы"
        case .me: return name(.me)
        case .partner: return name(.partner)
        }
    }

    func cycleScope() {
        switch scope {
        case .we: scope = .me
        case .me: scope = .partner
        case .partner: scope = .we
        }
        tap()
    }

    func visible(_ owner: Who?) -> Bool {
        switch scope {
        case .we: return true
        case .me: return owner == .me
        case .partner: return owner == .partner
        }
    }

    // MARK: Модули
    var active: [Module] { p.order.filter { !p.disabled.contains($0) } }
    var bar: [Module] { Array(active.prefix(4)) }
    var more: [Module] { Array(active.dropFirst(4)) }

    // MARK: Утилиты
    func tap() {
        guard p.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func success() {
        guard p.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func bind<T: Identifiable>(_ kp: WritableKeyPath<AppData, [T]>, _ item: T) -> Binding<T> {
        Binding(
            get: { self.data[keyPath: kp].first(where: { $0.id == item.id }) ?? item },
            set: { v in
                if let i = self.data[keyPath: kp].firstIndex(where: { $0.id == item.id }) {
                    self.data[keyPath: kp][i] = v
                }
            }
        )
    }

    var daysTogether: Int {
        let c = Calendar.current
        return max(0, c.dateComponents([.day], from: c.startOfDay(for: p.start), to: c.startOfDay(for: Date())).day ?? 0)
    }

    private static let anniversaryID = UUID()

    func events(on date: Date) -> [EventItem] {
        let c = Calendar.current
        var out = data.events.filter { e in
            if e.yearly {
                return c.component(.day, from: e.date) == c.component(.day, from: date)
                    && c.component(.month, from: e.date) == c.component(.month, from: date)
            }
            return c.isDate(e.date, inSameDayAs: date)
        }
        let s = p.start
        if c.component(.day, from: s) == c.component(.day, from: date),
           c.component(.month, from: s) == c.component(.month, from: date),
           c.component(.year, from: date) > c.component(.year, from: s) {
            out.insert(EventItem(id: Store.anniversaryID, title: "Годовщина", date: date, emoji: "💞", yearly: true), at: 0)
        }
        return out.sorted { $0.date < $1.date }
    }

    func addPoints(_ w: Who, _ n: Int = 1) {
        if w == .me { data.pointsMe += n } else { data.pointsPartner += n }
    }

    func level(_ w: Who) -> Int { (w == .me ? data.pointsMe : data.pointsPartner) / 5 + 1 }
}

// MARK: - Уведомления

enum Notifier {
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(id: String, title: String, body: String, at date: Date) {
        guard date > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }

    static func setDaily(_ on: Bool, hour: Int = 20) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-question"])
        guard on else { return }
        let c = UNMutableNotificationContent()
        c.title = "Вопрос дня"
        c.body = "Ответьте друг другу — это займёт минуту"
        c.sound = .default
        var d = DateComponents()
        d.hour = hour
        center.add(UNNotificationRequest(identifier: "daily-question", content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: true)))
    }
}
