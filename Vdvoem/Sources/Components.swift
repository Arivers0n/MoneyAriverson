import SwiftUI
import LocalAuthentication

// MARK: - Цвета

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    var hex: String {
        let u = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

/// Русская локаль для дат: `Date.formatted` берёт язык телефона, а не язык приложения.
let ruLocale = Locale(identifier: "ru_RU")

extension Color {
    /// Белый или тёмный текст, смотря что читается лучше на этом цвете (для крупного и среднего текста).
    var onAccent: Color {
        let u = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double { let v = Double(c); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return 1.05 / (l + 0.05) >= 3.4 ? .white : Color(hex: "14171F")
    }
}

struct ColorPair: Identifiable {
    let id: String
    let me: String
    let partner: String
}

let colorPairs: [ColorPair] = [
    ColorPair(id: "Лагуна", me: "0593C6", partner: "DB3996"),
    ColorPair(id: "Полночь", me: "0297DE", partner: "F2683F"),
    ColorPair(id: "Индиго", me: "2A56D6", partner: "EC72B0"),
    ColorPair(id: "Малахит", me: "0F8F6B", partner: "FF7A59"),
    ColorPair(id: "Янтарь", me: "E8A02B", partner: "2BB8A8"),
    ColorPair(id: "Вишня", me: "E4456F", partner: "2FB89A"),
    ColorPair(id: "Мята и коралл", me: "3FC9A5", partner: "FF7A6B"),
    ColorPair(id: "Фиалка и янтарь", me: "8C7BF2", partner: "F5A524"),
    ColorPair(id: "Графит и золото", me: "8E95A5", partner: "E3B341"),
    ColorPair(id: "Закат", me: "E8553D", partner: "7C5CE0"),
    ColorPair(id: "Сирень", me: "7C4DDB", partner: "F29A3C"),
    ColorPair(id: "Океан", me: "0E8A9E", partner: "F2677A"),
    ColorPair(id: "Космос", me: "9B7BFF", partner: "FF7AB8"),
    ColorPair(id: "Эспрессо", me: "D2955A", partner: "5FC2B0"),
    ColorPair(id: "Роза", me: "D6226B", partner: "1C9FC9"),
    ColorPair(id: "Фисташка", me: "5E8C16", partner: "E8622C"),
    ColorPair(id: "Туман", me: "4F6FA8", partner: "D98A5B")
]

// MARK: - Модификаторы

struct CardBG: ViewModifier {
    @EnvironmentObject var store: Store
    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: store.radius, style: .continuous)
        switch store.p.cardStyle {
        case 1:
            content.background(Pal.card, in: shape)
        case 2:
            content.background(Pal.card.opacity(0.45), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
        case 3:
            // Ретро: плотная рамка и жёсткая тень без размытия
            content.background(Pal.card, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.85), lineWidth: 2))
                .background { shape.fill(Color.primary.opacity(0.85)).offset(x: 4, y: 4) }
        case 4:
            // Бумага: тёплый лист, тонкая рамка, мягкая тень как у открытки
            content.background(Pal.card, in: shape)
                .overlay(shape.stroke(Color(hex: "C9B79A").opacity(0.5), lineWidth: 1))
                .shadow(color: Color(hex: "6B4F2A").opacity(0.12), radius: 10, y: 5)
        case 5:
            // Игривый: пухлая рамка и «объёмная» цветная нижняя тень
            content.background(Pal.card, in: shape)
                .overlay(shape.stroke(store.meColor.opacity(0.35), lineWidth: 3))
                .shadow(color: store.meColor.opacity(0.28), radius: 0, x: 0, y: 5)
        default:
            // Жидкое стекло: фон темы просвечивает и преломляется; лёгкий оттенок карточки держит читаемость.
            content.glass(shape, tint: store.glassTint)
                .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
        }
    }
}

struct BigButton: ViewModifier {
    @EnvironmentObject var store: Store
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(store.meColor.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .modifier(AccentGlass(color: store.meColor, shape: RoundedRectangle(cornerRadius: min(store.radius, 26), style: .continuous)))
    }
}

extension View {
    func card() -> some View { modifier(CardBG()) }
    func bigButton() -> some View { modifier(BigButton()) }

    func pairToolbar(scope: Bool = true, add: (() -> Void)? = nil) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let add {
                    Button(action: add) { Image(systemName: "plus").fontWeight(.semibold) }
                }
                if scope { ScopePill() }
            }
        }
    }
}

// MARK: - Компоненты

/// Знак приложения: два пересекающихся кружка в цветах пары.
struct PairMark: View {
    @EnvironmentObject var store: Store
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: -size * 0.35) {
            Circle().fill(store.meColor).frame(width: size, height: size)
            Circle().fill(store.partnerColor).frame(width: size, height: size)
                .overlay(Circle().stroke(Pal.bg, lineWidth: 2))
        }
        .accessibilityHidden(true)
    }
}

struct ScopePill: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Button { store.cycleScope() } label: {
            HStack(spacing: 8) {
                Text(store.scopeTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: -7) {
                    if store.scope != .partner { Circle().fill(store.meColor).frame(width: 16, height: 16) }
                    if store.scope != .me { Circle().fill(store.partnerColor).frame(width: 16, height: 16) }
                }
            }
        }
    }
}

struct Screen<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 12) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
        }
        .dockScroll()
        .modifier(SoftTopEdge())
        .background(ThemeBackground())
    }
}

struct SectionTitle: View {
    let text: String
    var color: Color = .secondary
    init(_ t: String, color: Color = .secondary) { text = t; self.color = color }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 10).padding(.horizontal, 4)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let text: String
    var action: String? = nil
    var onTap: (() -> Void)? = nil
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 56)).foregroundStyle(.tertiary).padding(.top, 70)
            Text(title).font(.title2.weight(.medium)).multilineTextAlignment(.center)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action, let onTap {
                Button(action: onTap) { Text(action).bigButton() }.padding(.top, 10)
            }
            if let hint {
                Text(hint).font(.footnote.monospaced()).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
    }
}

struct FormSheet<C: View>: View {
    @EnvironmentObject private var themeStore: Store   // перерисовка при смене темы
    @Environment(\.dismiss) private var dismiss
    let title: String
    let canSave: Bool
    let onSave: () -> Void
    let content: C

    init(title: String, canSave: Bool = true, onSave: @escaping () -> Void, @ViewBuilder content: () -> C) {
        self.title = title
        self.canSave = canSave
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .scrollContentBackground(.hidden)
                .background(Pal.bg.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { onSave(); dismiss() }.fontWeight(.semibold).disabled(!canSave)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct Chip: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

struct WhoPicker: View {
    @EnvironmentObject var store: Store
    @Binding var who: Who
    var body: some View {
        Picker("Кто", selection: $who) {
            Text(store.name(.me)).tag(Who.me)
            Text(store.name(.partner)).tag(Who.partner)
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Блокировка (Face ID / код)

struct LockGate<Content: View>: View {
    @EnvironmentObject private var themeStore: Store   // перерисовка при смене темы
    let title: String
    let content: () -> Content
    @State private var ok = false

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Group {
            if ok {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("«\(title)» закрыт").font(.title3.weight(.medium))
                    Button { auth() } label: { Text("Разблокировать").bigButton() }
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Pal.bg.ignoresSafeArea())
            }
        }
        .onAppear { if !ok { auth() } }
    }

    private func auth() {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Открыть «\(title)»") { success, _ in
                DispatchQueue.main.async { ok = success }
            }
        } else {
            ok = true
        }
    }
}

// MARK: - Данные для экранов-пустышек

extension Calendar {
    static var ru: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "ru_RU")
        return c
    }
}


/// Основная кнопка: на iOS 26 — цветное Liquid Glass, раньше — плотная заливка. Без двойного фона.
struct AccentGlass<S: Shape>: ViewModifier {
    let color: Color
    let shape: S
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(color).interactive(), in: shape)
        } else {
            content.background(color, in: shape)
        }
    }
}

/// Нажатие карточки: лёгкое «вдавливание» на 150 мс, одна кривая на всё приложение.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            // Быстро вниз при касании, чуть мягче обратно при отпускании
            .animation(configuration.isPressed ? Motion.press : Motion.curve(0.22), value: configuration.isPressed)
    }
}
