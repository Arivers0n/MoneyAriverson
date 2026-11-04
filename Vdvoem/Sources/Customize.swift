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

    static func of(_ id: String) -> ThemeLook {
        switch id {
        case "classic":  return ThemeLook(icon: 0, font: .standard, radius: 18, pattern: 0)
        case "mint":     return ThemeLook(icon: 0, font: .rounded, radius: 20, pattern: 0)
        case "lavender": return ThemeLook(icon: 2, font: .rounded, radius: 24, pattern: 0)
        case "peach":    return ThemeLook(icon: 2, font: .rounded, radius: 26, pattern: 0)
        case "ocean":    return ThemeLook(icon: 0, font: .standard, radius: 20, pattern: 0)
        case "sunset":   return ThemeLook(icon: 2, font: .rounded, radius: 26, pattern: 0)
        case "sakura":   return ThemeLook(icon: 2, font: .rounded, radius: 28, pattern: 0)
        case "graphite": return ThemeLook(icon: 0, font: .standard, radius: 12, pattern: 0)
        case "cosmos":   return ThemeLook(icon: 1, font: .standard, radius: 22, pattern: 0,
                                          pair: ("A78BFA", "F472B6"), mode: .dark)
        case "neon":     return ThemeLook(icon: 1, font: .mono, radius: 10, pattern: 0,
                                          pair: ("19F0E0", "FF3DCB"), mode: .dark)
        case "organic":  return ThemeLook(icon: 2, font: .serif, radius: 14, pattern: 0,
                                          pair: ("8A6A3C", "6B8E4E"))
        default:         return ThemeLook(icon: 1, font: .rounded, radius: 22, pattern: 0)   // «Свежесть» — стандарт
        }
    }
}

// MARK: - Действия хранилища (оформление)

extension Store {
    /// Единая мягкая анимация для любых правок оформления — без рывков.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)

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
        if let pair = look.pair { pr.myHex = pair.0; pr.partnerHex = pair.1 }
        if let m = look.mode { pr.theme = m } else if prev.mode != nil { pr.theme = .system }
        liveRadius = nil
        withAnimation(Store.spring) { data.profile = pr }
        success()
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
        pr.wallpaper = d.wallpaper
        pr.bubbleStyle = d.bubbleStyle
        pr.myHex = d.myHex
        pr.partnerHex = d.partnerHex
        pr.theme = d.theme
        liveRadius = nil
        withAnimation(Store.spring) { data.profile = pr }
        tap()
    }

    func glassSound() {
        guard p.sound else { return }
        GlassSound.shared.play()
    }
}

// MARK: - «Стеклянный» звук (синтезируется на лету, файлы не нужны)

/// Очень короткий и мягкий. Категория `.ambient`: уважает беззвучный режим и не прерывает музыку.
/// AVAudioPlayer создаётся и «прогревается» один раз — задержка при воспроизведении минимальна.
final class GlassSound {
    static let shared = GlassSound()
    private var player: AVAudioPlayer?

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        player = try? AVAudioPlayer(data: Self.makeWAV())
        player?.volume = 0.35
        player?.prepareToPlay()
    }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = 0
        player.play()
    }

    private static func makeWAV() -> Data {
        let rate = 44_100
        let count = Int(Double(rate) * 0.26)
        let partials: [(freq: Double, amp: Double, decay: Double)] = [
            (1760, 0.50, 16), (2637, 0.28, 22), (3520, 0.16, 30), (4699, 0.06, 40)
        ]
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            var v = 0.0
            for p in partials { v += p.amp * sin(2 * .pi * p.freq * t) * exp(-p.decay * t) }
            v *= min(1, t / 0.004) * 0.55          // мягкая атака
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
///  • Контурные — тонкая линия, без заливки.
///  • Неоновые — матовое стекло и светящийся градиентный контур.
///  • Объёмные — глянцевая «мягкая 3D» плитка с бликом и тенью.
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
            case 1: neon(box)
            case 2: solid(box)
            default: outline(box)
            }
        }
        .id(st)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .frame(width: box, height: box)
        .saturation(active ? 1 : 0.2)
        .opacity(active ? 1 : 0.7)
    }

    private func tileRadius(_ box: CGFloat) -> CGFloat { min(Theme.r(18) * box / 64, box / 2) }

    // 1. Контурные: тонкая линия цвета раздела на лёгкой цветной подложке
    private func outline(_ box: CGFloat) -> some View {
        let c = active ? color.boosted(minS: 0.55, minB: 0.85) : Color.secondary
        return ZStack {
            Circle().fill(c.opacity(0.12))
            Circle().strokeBorder(c.opacity(0.45), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.86, weight: .light))
                .foregroundStyle(c)
        }
        .padding(box * 0.03)
    }

    // 2. Неоновые: матовое стекло + светящийся градиентный контур
    private func neon(_ box: CGFloat) -> some View {
        let n1 = color.boosted(minS: 0.7, minB: 1)
        let n2 = (accent ?? store.partnerColor).boosted(minS: 0.65, minB: 1)
        let shape = RoundedRectangle(cornerRadius: tileRadius(box), style: .continuous)
        let grad = LinearGradient(colors: [n1, n2], startPoint: .topLeading, endPoint: .bottomTrailing)
        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(LinearGradient(colors: [n1.opacity(0.18), n2.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(grad, lineWidth: 1.5)
                .shadow(color: n1.opacity(0.65), radius: box * 0.1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.78, weight: .medium))
                .foregroundStyle(grad)
                .shadow(color: n1.opacity(0.9), radius: size * 0.16)
        }
        .padding(box * 0.04)
    }

    // 3. Объёмные: глянцевая «мягкая 3D»
    private func solid(_ box: CGFloat) -> some View {
        let base = color.boosted(minS: 0.5, minB: 0.9)
        let top = base.hsb(dS: -0.14, dB: 0.04)
        let bottom = base.hsb(dS: 0.18, dB: -0.2)
        let shape = RoundedRectangle(cornerRadius: tileRadius(box), style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            // глянцевый блик сверху
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: box * 0.9, height: box * 0.52)
                .offset(y: -box * 0.26)
            // светлая кромка и мягкая нижняя тень внутри
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.05), .black.opacity(0.14)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: size * 0.8, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: bottom.opacity(0.7), radius: size * 0.1, y: size * 0.08)
        }
        .clipShape(shape)
        .shadow(color: bottom.opacity(0.45), radius: box * 0.14, y: box * 0.1)
        .padding(box * 0.04)
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
        let size: CGFloat = selected ? 28 : 25.5          // активная чуть крупнее (≈ ×1.1)
        let n1 = color.boosted(minS: 0.7, minB: 1)
        let n2 = color2.boosted(minS: 0.65, minB: 1)
        Group {
            switch style {
            case 1:
                let g = LinearGradient(colors: [n1, n2], startPoint: .topLeading, endPoint: .bottomTrailing)
                if selected {
                    Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                        .foregroundStyle(g).shadow(color: n1.opacity(0.85), radius: 3.5)
                } else {
                    Image(systemName: symbol).font(.system(size: size, weight: .medium)).foregroundStyle(idle)
                }
            case 2:
                let g = LinearGradient(colors: [color.boosted(minS: 0.45, minB: 0.95).hsb(dS: -0.12, dB: 0.06),
                                                color.boosted(minS: 0.55, minB: 0.9).hsb(dS: 0.12, dB: -0.18)],
                                       startPoint: .top, endPoint: .bottom)
                if selected {
                    Image(systemName: symbol).symbolVariant(.fill).font(.system(size: size, weight: .bold))
                        .foregroundStyle(g).shadow(color: color.opacity(0.35), radius: 2, y: 1.5)
                } else {
                    Image(systemName: symbol).symbolVariant(.fill).font(.system(size: size, weight: .semibold)).foregroundStyle(idle)
                }
            default:
                Image(systemName: symbol).font(.system(size: size, weight: selected ? .regular : .light))
                    .foregroundStyle(selected ? color : idle)
            }
        }
        .frame(width: 38, height: 32)
    }
}

enum TabIcon {
    private static var cache: [String: UIImage] = [:]

    /// Картинки кэшируются: смена вкладки и стиля не перерисовывает ничего лишнего.
    @MainActor
    static func image(_ t: AppTab, store: Store, selected: Bool, dark: Bool) -> UIImage {
        let st = store.p.iconStyle
        let key = "\(t.symbol)|\(t.hex)|\(st)|\(selected)|\(dark)|\(store.p.myHex)|\(store.p.partnerHex)"
        if let hit = cache[key] { return hit }
        if cache.count > 300 { cache.removeAll() }
        let accent = st == 2 ? Color(hex: t.hex) : store.meColor
        let view = TabGlyph(symbol: t.symbol, color: accent, color2: store.partnerColor,
                            style: st, selected: selected, dark: dark)
        let r = ImageRenderer(content: view)
        r.scale = 3
        let img = (r.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
        cache[key] = img
        return img
    }
}

// MARK: - Узоры фона

struct PatternOverlay: View {
    let kind: Int       // 1 точки, 2 сердечки, 3 волны
    var body: some View {
        if kind > 0 {
            Canvas { ctx, size in
                let ink = Color.primary.opacity(0.04)
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
                        Text("Ещё").font(.system(size: 16, weight: .bold, design: look.font.design)).foregroundStyle(ink)
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
                    .strokeBorder(accent, lineWidth: on ? 3 : 0))
                .scaleEffect(on ? 1.03 : 1)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                Text(def.title).font(.caption.weight(on ? .bold : .regular)).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
