import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData { didSet { save(); scheduleSync(); applyTheme(); location.apply(); WidgetBridge.shared.update(self) } }
    @Published var scope: Scope = .we
    /// Скругление во время движения слайдера: меняет экран мгновенно, но не пишет на диск/в синхронизацию на каждом шаге.
    @Published var liveRadius: Double? = nil { didSet { Theme.radius = CGFloat(liveRadius ?? data.profile.radius) } }
    let sync = SyncEngine()
    let location = LocationService()
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent("vdvoem.json")
        if let d = try? Data(contentsOf: url),
           var a = try? JSONDecoder().decode(AppData.self, from: d) {
            for i in a.cards.indices where a.cards[i].number.isEmpty {
                a.cards[i].number = Keychain.get("card." + a.cards[i].id.uuidString) ?? ""
            }
            data = a
        } else {
            data = AppData()
        }
        // Один раз: «Сегодня» — первый раздел панели (запуск начинается с него).
        if !UserDefaults.standard.bool(forKey: "vd.mig.today2") {
            UserDefaults.standard.set(true, forKey: "vd.mig.today2")
            data.profile.disabled.removeAll { $0 == .today }
            data.profile.order.removeAll { $0 == .today }
            data.profile.order.insert(.today, at: 0)
        }
        applyTheme()
        sync.attach(self)
        location.attach(self)
        WidgetBridge.shared.update(self)
        seedCountersIfNeeded()
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateBattery() }
        }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateBattery() }
        }
        updateBattery()
    }

    func applyTheme() {
        Theme.current = ThemeDef.find(data.profile.themeID)
        Theme.bgStyle = data.profile.bgStyle > 2 ? 0 : data.profile.bgStyle
        Theme.cardStyle = data.profile.cardStyle > 2 ? 0 : data.profile.cardStyle
        Theme.bgPattern = data.profile.bgPattern
        Theme.radius = CGFloat(liveRadius ?? data.profile.radius)
        Theme.accent = Color(hex: data.profile.myHex)
        Theme.accent2 = Color(hex: data.profile.partnerHex)
    }

    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?

    /// Сравнение с сервером кодирует все записи, поэтому делаем его не на каждую мелкую правку, а раз в 0,25 с.
    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.sync.dataChanged(self.data)
        }
    }

    /// Запись на диск с паузой 0,3 с и вне главного потока: частые правки не тормозят экран.
    private func save() {
        saveTask?.cancel()
        let snapshot = data
        let target = url
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            Store.write(snapshot, to: target)
        }
    }

    /// Немедленная запись (при сворачивании приложения).
    func flushSave() {
        syncTask?.cancel()
        sync.dataChanged(data)
        saveTask?.cancel()
        Store.write(data, to: url)
    }

    /// Номера карт хранятся в Keychain, в файле данных их нет.
    nonisolated static func write(_ d: AppData, to url: URL) {
        var copy = d
        for c in copy.cards where !c.number.isEmpty { Keychain.set("card." + c.id.uuidString, c.number) }
        copy.cards = copy.cards.map { var x = $0; x.number = ""; return x }
        if let b = try? JSONEncoder().encode(copy) { try? b.write(to: url, options: .atomic) }
    }

    func resetAll() { data = AppData(); scope = .we }

    // MARK: Профиль и тема
    var p: Profile { data.profile }
    var radius: CGFloat { CGFloat(liveRadius ?? p.radius) }
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
    /// Нижняя панель: первые четыре включённых раздела. Чат в панель не попадает — в нём панель скрыта.
    var bar: [Module] { Array(active.filter { $0 != .chat }.prefix(4)) }
    var more: [Module] { active.filter { !bar.contains($0) } }

    /// Новый порядок нижней панели после перетаскивания: остальные разделы сохраняют своё место после неё.
    func setBar(_ mods: [Module]) {
        let rest = data.profile.order.filter { !mods.contains($0) }
        guard mods + rest != data.profile.order else { return }
        data.profile.order = mods + rest
        selectionTick()
    }

    /// Цвет стекла: 0 — прозрачное, 1 — матовое, 2 — окрашенное в цвет пары.
    var glassTint: Color {
        switch p.glassMode {
        case 1: return Pal.card.opacity(0.72)
        case 2: return meColor.opacity(0.22)
        default: return Pal.card.opacity(0.32)
        }
    }

    func selectionTick() {
        guard p.haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: Утилиты
    func tap() {
        guard p.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func success() {
        sfx(.done)
        guard p.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Только вибро-отклик «успех», без звука.
    func hapticOK() {
        guard p.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Короткий звук интерфейса (уважает выключатель в «Оформлении» и беззвучный режим).
    func sfx(_ k: Sfx.Kind) {
        guard p.sound else { return }
        Sfx.shared.play(k)
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
