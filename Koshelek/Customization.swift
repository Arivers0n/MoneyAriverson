import SwiftUI
import UIKit

// MARK: - Оформление

final class Appearance: ObservableObject {
    static let shared = Appearance()
    private let d = UserDefaults.standard

    struct Accent: Identifiable { let id: String; let name: String; let light: String; let dark: String }
    static let accents: [Accent] = [
        .init(id: "blue", name: "Синий", light: "2B47C9", dark: "7C93FF"),
        .init(id: "green", name: "Изумруд", light: "17805A", dark: "4CC995"),
        .init(id: "mint", name: "Мята", light: "0F8F86", dark: "5FD6C8"),
        .init(id: "sky", name: "Небо", light: "1A7FC0", dark: "64B5F6"),
        .init(id: "violet", name: "Лаванда", light: "7B4FD0", dark: "B39BFF"),
        .init(id: "pink", name: "Фуксия", light: "C2307A", dark: "F57FB8"),
        .init(id: "red", name: "Коралл", light: "C9402E", dark: "FF8A75"),
        .init(id: "orange", name: "Апельсин", light: "C2621F", dark: "FFA35C"),
        .init(id: "gold", name: "Золото", light: "A57A12", dark: "E8C25A"),
        .init(id: "graphite", name: "Графит", light: "2F3A36", dark: "D8DED9"),
    ]

    @Published var version = 0
    @Published var scheme: String { didSet { save("ap.scheme", scheme) } }        // system | light | dark
    @Published var accent: String { didSet { save("ap.accent", accent) } }
    @Published var background: String { didSet { save("ap.bg", background) } }    // grouped | pure | tint
    @Published var cards: String { didSet { save("ap.cards", cards) } }           // filled | glass | outline
    @Published var font: String { didSet { save("ap.font", font) } }              // default | rounded | serif
    @Published var bigNumber: String { didSet { save("ap.big", bigNumber) } }     // net | exp | inc
    @Published var compact: Bool { didSet { save("ap.compact", compact) } }
    @Published var hideAmounts: Bool { didSet { save("ap.hide", hideAmounts) } }

    init() {
        scheme = d.string(forKey: "ap.scheme") ?? "system"
        accent = d.string(forKey: "ap.accent") ?? "blue"
        background = d.string(forKey: "ap.bg") ?? "grouped"
        cards = d.string(forKey: "ap.cards") ?? "filled"
        font = d.string(forKey: "ap.font") ?? "default"
        bigNumber = d.string(forKey: "ap.big") ?? "net"
        compact = d.bool(forKey: "ap.compact")
        hideAmounts = d.bool(forKey: "ap.hide")
    }

    private func save(_ k: String, _ v: Any) { d.set(v, forKey: k); version += 1 }

    var accentInfo: Accent { Self.accents.first { $0.id == accent } ?? Self.accents[0] }
    var accentColor: Color { Color.dynamic(accentInfo.light, accentInfo.dark) }
    var onAccent: Color {
        // светлые акценты в тёмной теме требуют тёмного текста
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(Color(hex: "0B0F0D")) : .white
        })
    }
    var colorScheme: ColorScheme? { scheme == "light" ? .light : (scheme == "dark" ? .dark : nil) }
    var fontDesign: Font.Design { font == "rounded" ? .rounded : (font == "serif" ? .serif : .default) }

    func reset() {
        scheme = "system"; accent = "blue"; background = "grouped"; cards = "filled"; font = "default"
        bigNumber = "net"; compact = false; hideAmounts = false
    }
}

/// Фон экранов с учётом выбранного стиля.
struct Backdrop: View {
    @ObservedObject private var ap = Appearance.shared
    var body: some View {
        ZStack {
            Theme.bg
            if ap.background == "tint" {
                LinearGradient(colors: [ap.accentColor.opacity(0.28), ap.accentColor.opacity(0.06), .clear],
                               startPoint: .top, endPoint: .center)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Фон карточки по выбранному стилю: заливка, стекло или контур.
    @ViewBuilder
    func cardBG<S: Shape>(_ shape: S) -> some View {
        switch Appearance.shared.cards {
        case "glass": self.glass(shape)
        case "outline": self.background(Color.primary.opacity(0.025), in: shape).overlay(shape.stroke(Color.primary.opacity(0.13), lineWidth: 1))
        default: self.background(Theme.card, in: shape)
        }
    }
}

// MARK: - Главный экран: блоки и кнопки

final class HomeLayout: ObservableObject {
    static let shared = HomeLayout()

    struct Block: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
        let hint: String
    }
    static let blocks: [Block] = [
        .init(id: "summary", title: "Итог месяца", symbol: "sum", hint: "Крупная цифра, приход и расход"),
        .init(id: "insights", title: "Инсайты", symbol: "sparkle", hint: "Кнопка советника"),
        .init(id: "attention", title: "Важное", symbol: "exclamationmark.circle", hint: "Платёж скоро или просрочен"),
        .init(id: "budgets", title: "Бюджеты", symbol: "cylinder.split.1x2", hint: "Полоски лимитов"),
        .init(id: "goals", title: "Копилки", symbol: "target", hint: "Прогресс накоплений"),
        .init(id: "payments", title: "Ближайшие платежи", symbol: "calendar", hint: "Кредиты и подписки на неделе"),
        .init(id: "categories", title: "Категории", symbol: "chart.pie", hint: "Куда уходят деньги"),
        .init(id: "accounts", title: "Счета", symbol: "creditcard", hint: "Балансы карт и наличных"),
        .init(id: "feed", title: "Операции", symbol: "list.bullet", hint: "Лента трат и доходов"),
    ]
    static let defaultOrder = ["summary", "insights", "attention", "feed"]

    struct Button: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
    }
    static let topButtons: [Button] = [
        .init(id: "search", title: "Поиск", symbol: "magnifyingglass"),
        .init(id: "stats", title: "Анализ", symbol: "chart.pie"),
        .init(id: "payments", title: "Платежи", symbol: "calendar"),
        .init(id: "budgets", title: "Бюджеты", symbol: "cylinder.split.1x2"),
        .init(id: "goals", title: "Копилки", symbol: "target"),
        .init(id: "insights", title: "Инсайты", symbol: "sparkle"),
        .init(id: "export", title: "Экспорт", symbol: "square.and.arrow.up"),
    ]
    static let maxTop = 4

    @Published var order: [String] { didSet { UserDefaults.standard.set(order, forKey: "home.order") } }
    @Published var top: [String] { didSet { UserDefaults.standard.set(top, forKey: "home.top") } }
    @Published var showScan: Bool { didSet { UserDefaults.standard.set(showScan, forKey: "home.scan") } }
    @Published var showPlus: Bool { didSet { UserDefaults.standard.set(showPlus, forKey: "home.plus") } }
    @Published var editing = false

    init() {
        let d = UserDefaults.standard
        order = (d.stringArray(forKey: "home.order") ?? Self.defaultOrder).filter { id in Self.blocks.contains { $0.id == id } }
        top = d.stringArray(forKey: "home.top") ?? ["search", "stats", "payments", "budgets"]
        showScan = d.object(forKey: "home.scan") as? Bool ?? true
        showPlus = d.object(forKey: "home.plus") as? Bool ?? true
    }

    var hidden: [Block] { Self.blocks.filter { !order.contains($0.id) } }
    func block(_ id: String) -> Block? { Self.blocks.first { $0.id == id } }
    func remove(_ id: String) { withAnimation(.snappy) { order.removeAll { $0 == id } } }
    func add(_ id: String) { withAnimation(.snappy) { if !order.contains(id) { order.append(id) } } }
    func toggleTop(_ id: String) {
        if let i = top.firstIndex(of: id) { top.remove(at: i) }
        else if top.count < Self.maxTop { top.append(id) }
    }
    func reset() {
        order = Self.defaultOrder; top = ["search", "stats", "payments", "budgets"]; showScan = true; showPlus = true
    }
}

// MARK: - Категории пользователя

struct CustomCat: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var hex: String
    var symbol: String
    var kind: String   // exp | inc
}

struct CatOverride: Codable, Hashable {
    var name: String?
    var hex: String?
    var symbol: String?
}

final class CategoryPrefs: ObservableObject {
    static let shared = CategoryPrefs()
    @Published var custom: [CustomCat] = []
    @Published var hidden: Set<String> = []
    @Published var overrides: [String: CatOverride] = [:]
    @Published var version = 0

    private var key: String { "cats:\(Space.current)" }

    struct Stored: Codable {
        var custom: [CustomCat] = []
        var hidden: [String] = []
        var overrides: [String: CatOverride] = [:]
    }

    init() { reload() }

    func reload() {
        let s = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        custom = s.custom; hidden = Set(s.hidden); overrides = s.overrides
        version += 1
    }

    var stored: Stored { Stored(custom: custom, hidden: Array(hidden).sorted(), overrides: overrides) }

    func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: key)
        UserDefaults.standard.set(true, forKey: "prefsDirty:\(Space.current)")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "prefsTs:\(Space.current)")
        version += 1
        Task { @MainActor in SyncEngine.shared.schedulePush() }
    }

    /// Применить пришедшее с сервера (без пометки «изменено»).
    func applyRemote(_ obj: Any?, space: String) {
        guard let obj, JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: "cats:\(space)")
        if space == Space.current { reload() }
    }

    static func storedJSON(space: String) -> Any {
        guard let d = UserDefaults.standard.data(forKey: "cats:\(space)"),
              let o = try? JSONSerialization.jsonObject(with: d) else { return [String: Any]() }
        return o
    }

    func toggleHidden(_ id: String) {
        guard !Catalog.locked.contains(id) else { return }
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        persist()
    }

    func save(_ c: CustomCat) {
        if let i = custom.firstIndex(where: { $0.id == c.id }) { custom[i] = c } else { custom.append(c) }
        persist()
    }

    func setOverride(_ id: String, _ o: CatOverride?) {
        overrides[id] = o
        persist()
    }

    func deleteCustom(_ id: String) {
        custom.removeAll { $0.id == id }
        persist()
    }

    static let symbolChoices = [
        "cart.fill", "basket.fill", "cup.and.saucer.fill", "fork.knife", "takeoutbag.and.cup.and.straw.fill", "wineglass.fill",
        "car.fill", "bus.fill", "tram.fill", "fuelpump.fill", "airplane", "bicycle",
        "house.fill", "bolt.fill", "drop.fill", "wifi", "phone.fill", "tv.fill",
        "cross.case.fill", "pills.fill", "heart.fill", "figure.run", "dumbbell.fill", "scissors",
        "tshirt.fill", "bag.fill", "gift.fill", "gamecontroller.fill", "film.fill", "music.note",
        "book.fill", "graduationcap.fill", "pawprint.fill", "leaf.fill", "teddybear.fill", "stroller.fill",
        "wrench.and.screwdriver.fill", "hammer.fill", "building.columns.fill", "creditcard.fill", "banknote.fill", "percent",
        "briefcase.fill", "laptopcomputer", "iphone", "sparkles", "star.fill", "ellipsis",
    ]
    static let colorChoices = ["2E8B57", "17805A", "0F8F86", "1A9BB0", "3B6FD8", "2B47C9", "4E5E9E", "7B5CC4",
                               "8A4FD0", "C04FB0", "D04F6E", "C9402E", "D9822B", "E0A21A", "9A8A1F", "A4703A", "7A8580"]
}

// MARK: - Иконка приложения

struct AppIconChoice: Identifiable {
    let id: String          // имя альтернативной иконки или "" для основной
    let title: String
    let preview: String     // имя картинки-превью в ассетах
}

enum AppIcons {
    static let all: [AppIconChoice] = [
        .init(id: "", title: "Изумруд", preview: "Preview-Default"),
        .init(id: "AppIcon-Night", title: "Ночь", preview: "Preview-Night"),
        .init(id: "AppIcon-Ocean", title: "Океан", preview: "Preview-Ocean"),
        .init(id: "AppIcon-Sunset", title: "Закат", preview: "Preview-Sunset"),
        .init(id: "AppIcon-Lavender", title: "Лаванда", preview: "Preview-Lavender"),
        .init(id: "AppIcon-Gold", title: "Золото", preview: "Preview-Gold"),
        .init(id: "AppIcon-Mono", title: "Минимал", preview: "Preview-Mono"),
        .init(id: "AppIcon-Pink", title: "Розовый", preview: "Preview-Pink"),
    ]
}
