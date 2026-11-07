import SwiftUI
import AVFoundation

// MARK: - «Лук» темы: что тема меняет, кроме цветов

/// Выбор готовой темы переодевает не только фон, но и стиль иконок, шрифт, скругление и узор.
struct ThemeLook {
    let icon: Int              // 0 контурные, 1 неоновые, 2 объёмные
    let font: DesignStyle
    let radius: Double
    let pattern: Int           // 0 нет, 1 точки, 2 сердечки, 3 волны
    var pair: (String, String)? = nil   // цвета пары (только у ярких тем, где нужен контраст)
    var mode: ThemeMode? = nil          // принудительный режим (тёмные темы)
    var card: Int? = nil                // стиль карточек «мира»: 3 ретро, 4 бумага, 5 игривый
    var bg: Int? = nil                  // фон «мира»: 3 зернистый градиент, 4 бумага с зерном

    static func of(_ id: String) -> ThemeLook {
        switch id {
        case "malachite": return ThemeLook(icon: 0, font: .standard, radius: 18, pattern: 0,
                                           pair: ("0F8F6B", "FF7A59"))
        case "amber":     return ThemeLook(icon: 0, font: .standard, radius: 16, pattern: 0,
                                           pair: ("E8A02B", "2BB8A8"), mode: .dark)
        case "cherry":    return ThemeLook(icon: 0, font: .standard, radius: 22, pattern: 0,
                                           pair: ("E4456F", "2FB89A"))
        case "sunset":    return ThemeLook(icon: 0, font: .standard, radius: 22, pattern: 0, pair: ("E8553D", "7C5CE0"))
        case "lilac":     return ThemeLook(icon: 0, font: .standard, radius: 22, pattern: 0, pair: ("7C4DDB", "F29A3C"))
        case "ocean":     return ThemeLook(icon: 0, font: .standard, radius: 20, pattern: 0, pair: ("0E8A9E", "F2677A"))
        case "cosmos":    return ThemeLook(icon: 0, font: .standard, radius: 22, pattern: 0, pair: ("9B7BFF", "FF7AB8"), mode: .dark)
        case "espresso":  return ThemeLook(icon: 0, font: .standard, radius: 16, pattern: 0, pair: ("D2955A", "5FC2B0"), mode: .dark)
        case "rose":      return ThemeLook(icon: 0, font: .standard, radius: 24, pattern: 0, pair: ("D6226B", "1C9FC9"))
        case "pistachio": return ThemeLook(icon: 0, font: .standard, radius: 18, pattern: 0, pair: ("5E8C16", "E8622C"))
        case "paper":     return ThemeLook(icon: 0, font: .serif, radius: 12, pattern: 0, pair: ("B5533C", "4F7A5A"), card: 4, bg: 4)
        case "toy":       return ThemeLook(icon: 1, font: .rounded, radius: 30, pattern: 2, pair: ("FF5FA2", "6C7BFF"), card: 5, bg: 0)
        case "retro":     return ThemeLook(icon: 0, font: .mono, radius: 0, pattern: 1, pair: ("E4572E", "1F7A8C"), card: 3, bg: 2)
        case "grainient": return ThemeLook(icon: 0, font: .rounded, radius: 24, pattern: 0, pair: ("7B5CFF", "FF8A5B"), card: 0, bg: 3)
        case "aurora":    return ThemeLook(icon: 0, font: .rounded, radius: 26, pattern: 0, pair: ("19C3A0", "7A5CFF"), mode: .dark, card: 0, bg: 5)
        case "neon":      return ThemeLook(icon: 2, font: .rounded, radius: 20, pattern: 0, pair: ("B24BFF", "00E0C6"), mode: .dark, card: 6, bg: 5)
        case "mocha":     return ThemeLook(icon: 0, font: .serif, radius: 22, pattern: 0, pair: ("A8643C", "6F8F72"), card: 4, bg: 0)
        default:          return ThemeLook(icon: 0, font: .standard, radius: 20, pattern: 0,
                                           pair: ("0593C6", "DB3996"))   // «Лагуна» — по умолчанию
        }
    }
}

// MARK: - Действия хранилища (оформление)

extension Store {
    /// Единая мягкая анимация для любых правок оформления — без рывков.
    static let spring = Motion.spring

    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let edgeGen = UIImpactFeedbackGenerator(style: .medium)

    /// Выбор готовой темы: фон, иконки, шрифт, скругление и узор переодеваются разом.
    func applyPreset(_ t: ThemeDef) {
        guard t.id != p.themeID else { return }
        let look = ThemeLook.of(t.id)
        let prev = ThemeLook.of(p.themeID)
        var pr = data.profile
        pr.themeID = t.id
        pr.iconStyle = look.icon
        pr.design = look.font
        pr.radius = look.radius
        pr.bgPattern = look.pattern
        // «Миры» меняют ещё и карточки с фоном; обычные темы возвращают их к стандарту, только если до этого был «мир»
        if look.card != nil || prev.card != nil { pr.cardStyle = look.card ?? 0 }
        if look.bg != nil || prev.bg != nil { pr.bgStyle = look.bg ?? 0 }
        if let pair = look.pair { pr.myHex = pair.0; pr.partnerHex = pair.1 }
        if let m = look.mode { pr.theme = m } else if prev.mode != nil { pr.theme = .system }
        liveRadius = nil
        withAnimation(Store.spring) { data.profile = pr }
        hapticOK()
        glassSound()
    }

    /// Слайдер округления: мягкий «шорох» selection на каждый пиксель, чёткий щелчок на краях (0 и 30).
    /// Во время движения пальца меняется только `liveRadius` — без записи на диск и синхронизации.
    func setRadius(_ raw: Double) {
        let v = min(30, max(0, raw.rounded()))
        guard v != (liveRadius ?? p.radius) else { return }
        liveRadius = v
        guard p.haptics else { return }
        if v == 0 || v == 30 {
            Store.edgeGen.impactOccurred(intensity: 0.8)
        } else {
            Store.selectionGen.selectionChanged()
        }
        Store.selectionGen.prepare()
    }

    /// Палец отпущен: фиксируем значение в профиле.
    func commitRadius() {
        guard let v = liveRadius else { return }
        data.profile.radius = v
        liveRadius = nil
    }

    func setIconStyle(_ v: Int) {
        guard v != p.iconStyle else { return }
        withAnimation(Store.spring) { data.profile.iconStyle = v }
        tap()
    }

    func setPattern(_ v: Int) {
        guard v != p.bgPattern else { return }
        withAnimation(Store.spring) { data.profile.bgPattern = v }
        tap()
    }

    func setFont(_ v: DesignStyle) {
        guard v != p.design else { return }
        withAnimation(Store.spring) { data.profile.design = v }
        tap()
    }

    /// «Сбросить»: плавно возвращает стандартный вид. Имена, пара, функции, значок приложения и тумблеры остаются.
    func resetAppearance() {
        let d = Profile()
        var pr = data.profile
        pr.themeID = d.themeID
        pr.iconStyle = d.iconStyle
        pr.design = d.design
        pr.radius = d.radius
        pr.bgPattern = d.bgPattern
        pr.bgStyle = d.bgStyle
        pr.cardStyle = d.cardStyle
        pr.glassMode = d.glassMode
        pr.wallpaper = d.wallpaper
        pr.bubbleStyle = d.bubbleStyle
        pr.myHex = d.myHex
        pr.partnerHex = d.partnerHex
        pr.theme = d.theme
        liveRadius = nil
        withAnimation(Store.spring) { data.profile = pr }
        tap()
    }

    func glassSound() { sfx(.glass) }
}

// MARK: - Звуки интерфейса (синтезируются на лету, файлы не нужны)

/// Очень короткие и мягкие. Категория `.ambient`: уважает беззвучный режим и не прерывает музыку.
/// Плееры создаются и «прогреваются» один раз — задержка при воспроизведении минимальна.
final class Sfx {
    enum Kind: CaseIterable { case glass, done, send, heart, pop }
    static let shared = Sfx()
    private var players: [Kind: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for k in Kind.allCases {
            let p = try? AVAudioPlayer(data: Self.wav(k))
            p?.volume = k == .glass ? 0.35 : 0.3
            p?.prepareToPlay()
            players[k] = p
        }
    }

    func play(_ k: Kind) {
        guard let p = players[k] else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.currentTime = 0
        p.play()
    }

    /// Набор частичных тонов: (частота, громкость, скорость затухания) и длина.
    private static func spec(_ k: Kind) -> (len: Double, parts: [(Double, Double, Double)], glide: Double) {
        switch k {
        case .glass: return (0.26, [(1760, 0.50, 16), (2637, 0.28, 22), (3520, 0.16, 30), (4699, 0.06, 40)], 0)
        case .done:  return (0.34, [(1047, 0.45, 11), (1568, 0.30, 13), (2093, 0.14, 18)], 0)         // мягкий «дзынь» вверх
        case .send:  return (0.18, [(740, 0.50, 20), (1480, 0.18, 28)], 380)                         // короткий «фью» вверх
        case .heart: return (0.42, [(523, 0.45, 8), (784, 0.35, 9), (1046, 0.18, 12)], 0)
        case .pop:   return (0.12, [(420, 0.55, 34), (840, 0.20, 40)], -160)                         // «пок»
        }
    }

    private static func wav(_ k: Kind) -> Data {
        let rate = 44_100
        let sp = spec(k)
        let count = Int(Double(rate) * sp.len)
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            var v = 0.0
            for p in sp.parts {
                let f = p.0 + sp.glide * t / sp.len
                v += p.1 * sin(2 * .pi * f * t) * exp(-p.2 * t)
            }
            v *= min(1, t / 0.004) * 0.55
            samples.append(Int16(max(-1, min(1, v)) * Double(Int16.max)))
        }
        var data = Data()
        func u32(_ x: UInt32) { withUnsafeBytes(of: x.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { withUnsafeBytes(of: x.littleEndian) { data.append(contentsOf: $0) } }
        let size = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + size)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate * 2))
        u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(size)
        for s in samples { u16(UInt16(bitPattern: s)) }
        return data
    }
}

// MARK: - Подбор цвета (HSB)

extension Color {
    /// Подтягивает насыщенность/яркость не ниже заданных — чтобы пастельные цвета разделов выглядели сочно.
    func boosted(minS: CGFloat = 0, minB: CGFloat = 0) -> Color { hsb(setS: nil, setB: nil, minS: minS, minB: minB) }

    func hsb(dS: CGFloat = 0, dB: CGFloat = 0) -> Color { hsb(setS: nil, setB: nil, minS: 0, minB: 0, dS: dS, dB: dB) }

    private func hsb(setS: CGFloat?, setB: CGFloat?, minS: CGFloat, minB: CGFloat, dS: CGFloat = 0, dB: CGFloat = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let ns = min(1, max(0, max(setS ?? s, minS) + dS))
        let nb = min(1, max(0, max(setB ?? b, minB) + dB))
        return Color(hue: Double(h), saturation: Double(ns), brightness: Double(nb), opacity: Double(a))
    }
}

// MARK: - Иконка в трёх стилях (общая для плиток «Ещё», таб-бара, списков)

/// Одна и та же иконка рисуется тремя разными способами и мгновенно переключается вместе с темой.
///  • Мягкие — пастельная плитка и двухтонный глиф.
///  • Цветные — плотная плитка с градиентом и белым глифом.
///  • Тонкие — лёгкий двухтонный глиф без плитки.
struct ArtIcon: View {
    @EnvironmentObject var store: Store
    let symbol: String
    let color: Color
    /// Размер глифа. Плитка всегда `size * 1.7` — все стили занимают одинаковое место.
    var size: CGFloat = 28
    /// Переопределения нужны только для миниатюр других тем.
    var style: Int? = nil
    var accent: Color? = nil
    var active = true

    var body: some View {
        let st = style ?? store.p.iconStyle
        let box = size * 1.7
        ZStack {
            switch st {
            case 1: filled(box)
            case 2: thin(box)
            default: soft(box)
            }
        }
        .id(st)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .frame(width: box, height: box)
        .saturation(active ? 1 : 0.2)
        .opacity(active ? 1 : 0.7)
    }

    private func tileRadius(_ box: CGFloat) -> CGFloat { min(Theme.r(18) * box / 64, box / 2) }

    /// Цвет глифа: насыщенный, но не кислотный, чтобы читался и на светлой, и на тёмной теме.
    private var ink: Color { color.boosted(minS: 0.55, minB: 0.8) }

    // 0. Мягкие: пастельная плитка-«сквиркл» и двухтонный глиф — основной стиль
    private func soft(_ box: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: box * 0.31, style: .continuous)
        let c = ink
        return ZStack {
            shape.fill(c.opacity(0.16))
            shape.strokeBorder(c.opacity(0.12), lineWidth: 0.5)
            Image(systemName: symbol).symbolVariant(.fill).symbolRenderingMode(.palette)
                .foregroundStyle(c, c.opacity(0.42))
                .font(.system(size: size, weight: .medium))
        }
        .padding(box * 0.02)
    }

    // 1. Цветные: плотная плитка с мягким градиентом цвета раздела и белым глифом (как в «Настройках» iOS)
    private func filled(_ box: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: box * 0.31, style: .continuous)
        // Плитка чуть глубже исходного цвета, чтобы белый глиф читался; на очень светлых цветах глиф тёмный.
        let base = color.boosted(minS: 0.55, minB: 0.8).hsb(dS: 0.04, dB: -0.06)
        let top = base.hsb(dS: -0.05, dB: 0.05)
        let bottom = base.hsb(dS: 0.08, dB: -0.14)
        return ZStack {
            shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
            Image(systemName: symbol).symbolVariant(.fill)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(bottom.onAccent)
        }
        .shadow(color: bottom.opacity(0.22), radius: box * 0.07, y: box * 0.04)
        .padding(box * 0.03)
    }

    // 2. Тонкие: только лёгкий двухтонный глиф без плитки — воздушный минимализм
    private func thin(_ box: CGFloat) -> some View {
        let c = ink
        return Image(systemName: symbol).symbolRenderingMode(.palette)
            .foregroundStyle(c, c.opacity(0.4))
            .font(.system(size: size * 1.28, weight: .light))
    }
}

// MARK: - Нижняя панель: системная (стекло iOS), своя только картинка иконки

struct AppTab: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let hex: String
}

/// Иконка вкладки в выбранном стиле. Рисуется один раз в картинку и отдаётся системной панели,
/// поэтому стекло, размытие, разделитель и высота остаются родными для iOS.
struct TabGlyph: View {
    let symbol: String
    let color: Color
    let color2: Color
    let style: Int
    let selected: Bool
    let dark: Bool

    private var idle: Color {
        Color(UIColor.secondaryLabel.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)))
    }

    var body: some View {
        let size: CGFloat = selected ? 24 : 22
        let c = color.boosted(minS: 0.55, minB: 0.8)
        Group {
            switch style {
            case 1:
                // Цветные: у выбранной вкладки — мини-плитка с белым глифом
                if selected {
                    let base = color.boosted(minS: 0.55, minB: 0.8).hsb(dS: 0.04, dB: -0.06)
                    let bottom = base.hsb(dS: 0.08, dB: -0.14)
                    let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                    ZStack {
                        shape.fill(LinearGradient(colors: [base.hsb(dS: -0.05, dB: 0.05), bottom],
                                                  startPoint: .top, endPoint: .bottom))
                        Image(systemName: symbol).symbolVariant(.fill).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(bottom.onAccent)
                    }
                    .frame(width: 32, height: 28)
                } else {
                    Image(systemName: symbol).font(.system(size: size - 2, weight: .regular)).foregroundStyle(idle)
                }
            case 2:
                // Тонкие
                Image(systemName: symbol).symbolRenderingMode(.palette)
                    .foregroundStyle(selected ? c : idle, selected ? c.opacity(0.4) : idle.opacity(0.5))
                    .font(.system(size: size, weight: .light))
            default:
                // Мягкие: выбранная — двухтонная заливка цветом, остальные — контур
                if selected {
                    Image(systemName: symbol).symbolVariant(.fill).symbolRenderingMode(.palette)
                        .foregroundStyle(c, c.opacity(0.42)).font(.system(size: size, weight: .medium))
                } else {
                    Image(systemName: symbol).font(.system(size: size - 1, weight: .regular)).foregroundStyle(idle)
                }
            }
        }
        .frame(width: 38, height: 32)
    }
}

// MARK: - Стеклянный док

/// Состояние дока: развёрнут, свёрнут в компактную таблетку, скрыт (в чате) или в режиме правки порядка.
@MainActor
final class DockState: ObservableObject {
    @Published var collapsed = false
    @Published var hidden = false
    @Published var editing = false
    private var last = Date.distantPast
    private static let gen = UIImpactFeedbackGenerator(style: .soft)

    static let spring = Motion.spring

    func set(_ v: Bool, haptics: Bool) {
        guard v != collapsed else { return }
        last = Date()
        if haptics { Self.gen.impactOccurred(intensity: 0.7); Self.gen.prepare() }
        withAnimation(Self.spring) { collapsed = v }
    }

    func hide(_ v: Bool) {
        guard v != hidden else { return }
        withAnimation(Motion.enter) { hidden = v }
        if v { editing = false }
    }

    func edit(_ v: Bool, haptics: Bool) {
        guard v != editing else { return }
        if haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        withAnimation(Self.spring) { editing = v; if v { collapsed = false } }
    }

    /// Скролл вниз сворачивает, вверх разворачивает. Пауза после смены — чтобы док не дрожал.
    func scrolled(from old: CGFloat, to new: CGFloat, haptics: Bool) {
        guard !editing, Date().timeIntervalSince(last) > 0.6 else { return }
        let d = new - old
        guard abs(d) > 10 else { return }
        if d > 0, new > 120 { set(true, haptics: haptics) }
        else if d < 0 { set(false, haptics: haptics) }
    }
}

struct DockScroll: ViewModifier {
    @EnvironmentObject var dock: DockState
    @EnvironmentObject var store: Store
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
                dock.scrolled(from: old, to: new, haptics: false)
            }
        } else {
            content
        }
    }
}

/// Экран, на котором нижней панели нет (чат): панель мягко уезжает вниз, а место под неё освобождается.
struct HidesDock: ViewModifier {
    @EnvironmentObject var dock: DockState
    func body(content: Content) -> some View {
        content
            .onAppear { dock.hide(true) }
            .onDisappear { dock.hide(false) }
    }
}

extension View {
    func dockScroll() -> some View { modifier(DockScroll()) }
    func hidesDock() -> some View { modifier(HidesDock()) }
}

/// Док в духе iOS 26: одна стеклянная капсула, внутри которой «линза» выбранной вкладки плавно переезжает на новое место.
///  • тап — переход; можно вести пальцем по панели, линза едет следом;
///  • зажать — значки начинают покачиваться, их можно переставлять (как на рабочем столе);
///  • прокрутка вниз сворачивает панель в компактную таблетку, вверх — разворачивает.
struct GlassDock: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var dock: DockState
    @Environment(\.colorScheme) private var scheme
    let tabs: [AppTab]
    @Binding var selected: String

    @State private var live: [AppTab] = []
    @State private var dragID: String?
    @State private var dragStart = 0
    @State private var dragX: CGFloat = 0

    private let height: CGFloat = 62
    private let pad: CGFloat = 6

    private var more: AppTab? { tabs.first { $0.id == "more" } }
    private var movable: [AppTab] { tabs.filter { $0.id != "more" } }
    /// Что рисуем: во время правки — живой порядок, иначе — как есть.
    private var shown: [AppTab] { dock.editing ? live + (more.map { [$0] } ?? []) : tabs }

    var body: some View {
        VStack(spacing: 10) {
            if dock.editing { donePill.transition(.move(edge: .bottom).combined(with: .opacity)) }
            GeometryReader { geo in
                let full = max(0, geo.size.width - 32)
                let collapsed = dock.collapsed && !dock.editing
                let shape = RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                let itemW = max(1, (full - pad * 2) / CGFloat(max(shown.count, 1)))
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        if let i = shown.firstIndex(where: { $0.id == selected }), !dock.editing {
                            lensView(for: shown[i]).frame(width: itemW - 4, height: height - 10)
                                .offset(x: pad + itemW * CGFloat(i) + 2)
                        }
                        HStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in item(t, index: i, itemW: itemW) }
                        }
                        .padding(.horizontal, pad)
                    }
                    .frame(width: full, height: height)
                    .opacity(collapsed ? 0 : 1)
                    .allowsHitTesting(!collapsed)
                    compact
                        .opacity(collapsed ? 1 : 0)
                        .allowsHitTesting(collapsed)
                }
                .frame(width: collapsed ? compactWidth : full, height: height, alignment: .leading)
                .clipShape(shape)
                .modifier(DockGlass(shape: shape, tint: store.glassTint))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                .contentShape(shape)
                .simultaneousGesture(scrub(full: full, itemW: itemW), including: dock.editing || collapsed ? .none : .all)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                    if !collapsed, !dock.editing { startEditing() }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: collapsed ? .bottomLeading : .bottom)
                .padding(.horizontal, 16)
                .animation(Motion.spring, value: collapsed)
                .animation(Motion.spring, value: selected)
            }
            .frame(height: height + 8)
        }
        .accessibilityElement(children: .contain)
        .animation(Motion.spring, value: dock.editing)
    }

    // MARK: Линза выбранной вкладки

    @ViewBuilder private func lensView(for t: AppTab) -> some View {
        let c = store.meColor
        let capsule = Capsule(style: .continuous)
        Group {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(c.opacity(0.22)).interactive(), in: capsule)
            } else {
                capsule.fill(c.opacity(0.16))
                    .overlay(capsule.strokeBorder(c.opacity(0.18), lineWidth: 0.5))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Свёрнутая таблетка

    private var compactWidth: CGFloat { 132 }

    private var compact: some View {
        let t = tabs.first { $0.id == selected } ?? tabs[0]
        let st = store.p.iconStyle
        return Button { dock.set(false, haptics: store.p.haptics) } label: {
            HStack(spacing: 8) {
                TabGlyph(symbol: t.symbol, color: st == 2 ? Color(hex: t.hex) : store.meColor, color2: store.partnerColor,
                         style: st, selected: true, dark: scheme == .dark)
                    .scaleEffect(0.85).frame(width: 34)
                Text(t.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(store.meColor).lineLimit(1)
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .frame(width: compactWidth, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Развернуть панель")
    }

    // MARK: Кнопка «Готово» в режиме правки

    private var donePill: some View {
        Button {
            dock.edit(false, haptics: store.p.haptics)
            store.setBar(live.compactMap { t in Module(rawValue: t.id) })
        } label: {
            HStack(spacing: 8) {
                Text("Перетащите значки, чтобы поменять местами").font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Text("Готово").font(.footnote.weight(.semibold)).foregroundStyle(store.meColor)
            }
            .padding(.horizontal, 16).frame(height: 38)
            .modifier(DockGlass(shape: Capsule(style: .continuous), tint: store.glassTint))
        }
        .buttonStyle(.plain)
    }

    private func startEditing() {
        live = movable
        dock.edit(true, haptics: store.p.haptics)
    }

    // MARK: Жесты

    /// Обычный режим: ведём пальцем по панели — линза едет следом за пальцем.
    private func scrub(full: CGFloat, itemW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard !dock.editing else { return }
                let i = Int(((v.location.x - pad) / itemW).rounded(.down))
                guard tabs.indices.contains(i), tabs[i].id != selected else { return }
                selected = tabs[i].id
                store.selectionTick()
            }
    }

    private func reorder(_ t: AppTab, from index: Int, itemW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard dock.editing, t.id != "more" else { return }
                if dragID == nil { dragID = t.id; dragStart = live.firstIndex { $0.id == t.id } ?? index }
                guard dragID == t.id, let cur = live.firstIndex(where: { $0.id == t.id }) else { return }
                dragX = v.translation.width
                let target = min(max(Int((Double(dragStart) + Double(dragX / itemW)).rounded()), 0), live.count - 1)
                if target != cur {
                    withAnimation(Motion.bouncy) { live.move(fromOffsets: IndexSet(integer: cur), toOffset: target > cur ? target + 1 : target) }
                    store.selectionTick()
                }
            }
            .onEnded { _ in
                withAnimation(Motion.bouncy) { dragID = nil; dragX = 0 }
            }
    }

    // MARK: Один значок

    private func item(_ t: AppTab, index: Int, itemW: CGFloat) -> some View {
        let on = t.id == selected && !dock.editing
        let st = store.p.iconStyle
        let dragging = dragID == t.id
        let curIdx = live.firstIndex { $0.id == t.id } ?? index
        return VStack(spacing: 0) {
            TabGlyph(symbol: t.symbol, color: st == 2 ? Color(hex: t.hex) : store.meColor, color2: store.partnerColor,
                     style: st, selected: on || dock.editing, dark: scheme == .dark)
                .scaleEffect(on ? 0.94 : 0.86)
            Text(t.title).font(.system(size: 10, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? store.meColor : Color.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !dock.editing else { return }
            if selected != t.id { store.tap() }
            selected = t.id
        }
        .jiggle(dock.editing && t.id != "more" && !dragging, seed: Double(index) * 1.3)
        .scaleEffect(dragging ? 1.12 : 1)
        .offset(x: dragging ? dragX - CGFloat(curIdx - dragStart) * itemW : 0)
        .zIndex(dragging ? 1 : 0)
        .opacity(dock.editing && t.id == "more" ? 0.4 : 1)
        .gesture(reorder(t, from: index, itemW: itemW), including: dock.editing ? .all : .subviews)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/// Стекло дока: на iOS 26 — настоящее Liquid Glass без подложки, ниже — матовый материал.
struct DockGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            content.background(.thinMaterial, in: shape)
                .background(shape.fill(tint))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
    }
}

// MARK: - Узоры фона

struct PatternOverlay: View {
    let kind: Int       // 1 точки, 2 сердечки, 3 волны
    var body: some View {
        if kind > 0 {
            Canvas { ctx, size in
                let ink = Color.primary.opacity(0.03)
                switch kind {
                case 1:
                    let step: CGFloat = 28
                    for row in 0..<Int(size.height / step) + 1 {
                        for col in 0..<Int(size.width / step) + 1 {
                            let x = CGFloat(col) * step + (row.isMultiple(of: 2) ? 0 : step / 2)
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: CGFloat(row) * step, width: 3, height: 3)), with: .color(ink))
                        }
                    }
                case 2:
                    var heart = ctx.resolve(Image(systemName: "heart.fill"))
                    heart.shading = .color(ink)
                    let step: CGFloat = 54
                    for row in 0..<Int(size.height / step) + 1 {
                        for col in 0..<Int(size.width / step) + 1 {
                            let x = CGFloat(col) * step + (row.isMultiple(of: 2) ? 0 : step / 2)
                            ctx.draw(heart, in: CGRect(x: x, y: CGFloat(row) * step, width: 14, height: 13))
                        }
                    }
                default:
                    let step: CGFloat = 38
                    for row in 0..<Int(size.height / step) + 1 {
                        var path = Path()
                        let y0 = CGFloat(row) * step
                        path.move(to: CGPoint(x: 0, y: y0))
                        var x: CGFloat = 0
                        while x <= size.width {
                            path.addLine(to: CGPoint(x: x, y: y0 + sin(x / 26 + CGFloat(row)) * 6))
                            x += 4
                        }
                        ctx.stroke(path, with: .color(ink), lineWidth: 1)
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    static func symbol(_ k: Int) -> String {
        switch k {
        case 1: return "circle.grid.3x3.fill"
        case 2: return "heart.fill"
        case 3: return "water.waves"
        default: return "nosign"
        }
    }

    static func title(_ k: Int) -> String {
        switch k {
        case 1: return "Точки"
        case 2: return "Сердечки"
        case 3: return "Волны"
        default: return "Без узора"
        }
    }
}

// MARK: - Карточка-миниатюра темы (карусель)

/// Все карточки одного размера и с одним скруглением — оно берётся из слайдера, поэтому карусель живо реагирует на него.
struct ThemePreviewCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    let def: ThemeDef

    private let tiles: [(String, String)] = [
        ("bubble.left.and.bubble.right", "8EC5FF"), ("safari", "FFB38A"),
        ("lock", "B7A6FF"), ("gamecontroller", "C9A7FF")
    ]

    var body: some View {
        let look = ThemeLook.of(def.id)
        let dark = look.mode == .dark || (look.mode == nil && scheme == .dark)
        let top = Color(hex: dark ? def.topD : def.topL)
        let bg = Color(hex: dark ? def.bgD : def.bgL)
        let card = Color(hex: dark ? def.cardD : def.cardL)
        let accent = look.pair.map { Color(hex: $0.0) } ?? store.meColor
        let accent2 = look.pair.map { Color(hex: $0.1) } ?? store.partnerColor
        let ink: Color = dark ? .white : Color(hex: "1B1B1F")
        let on = def.id == store.p.themeID
        let outer = store.radius + 4
        let inner = store.radius * 0.5

        Button { store.applyPreset(def) } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: outer, style: .continuous)
                        .fill(LinearGradient(colors: [top, bg], startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ещё").font(.system(size: 16, weight: .medium, design: look.font.design)).foregroundStyle(ink)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                            ForEach(tiles, id: \.0) { t in
                                ZStack {
                                    RoundedRectangle(cornerRadius: inner, style: .continuous).fill(card)
                                    ArtIcon(symbol: t.0, color: Color(hex: t.1), size: 13, style: look.icon, accent: look.icon == 0 ? accent : accent2)
                                }
                                .frame(height: 46)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { i in
                                Circle().fill(i == 0 ? accent : ink.opacity(0.3)).frame(width: 7, height: 7)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(card, in: Capsule())
                    }
                    .padding(10)
                }
                .frame(width: 128, height: 196)
                .overlay(RoundedRectangle(cornerRadius: outer, style: .continuous)
                    .strokeBorder(accent, lineWidth: on ? 2 : 0))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

                Text(def.title).font(.caption.weight(on ? .semibold : .regular)).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
