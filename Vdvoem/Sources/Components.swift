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

struct ColorPair: Identifiable {
    let id: String
    let me: String
    let partner: String
}

let colorPairs: [ColorPair] = [
    ColorPair(id: "Океан и роза", me: "4C9AF0", partner: "D870A8"),
    ColorPair(id: "Мята и коралл", me: "3FC9A5", partner: "FF7A6B"),
    ColorPair(id: "Фиалка и янтарь", me: "8C7BF2", partner: "F5A524"),
    ColorPair(id: "Бирюза и малина", me: "22B8CF", partner: "E64980"),
    ColorPair(id: "Графит и золото", me: "8E95A5", partner: "E3B341"),
    ColorPair(id: "Лайм и сирень", me: "8BC34A", partner: "B388FF")
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
                .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 1.2))
        default:
            content.glass(shape)
                .shadow(color: Theme.accent.opacity(0.10), radius: 14, y: 8)
        }
    }
}

struct BigButton: ViewModifier {
    @EnvironmentObject var store: Store
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .glass(RoundedRectangle(cornerRadius: min(store.radius, 26), style: .continuous), tint: store.meColor, interactive: true)
            .background(store.meColor.opacity(0.85), in: RoundedRectangle(cornerRadius: min(store.radius, 26), style: .continuous))
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
            Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
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
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
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
                        Button("Готово") { onSave(); dismiss() }.bold().disabled(!canSave)
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
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
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
                    Text("«\(title)» закрыт").font(.title3.bold())
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
