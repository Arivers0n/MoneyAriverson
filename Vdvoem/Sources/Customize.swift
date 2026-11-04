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
        case "mint":     return ThemeLook(icon: 0, font: .rounded, radius: 20, pattern: 3)
        case "lavender": return ThemeLook(icon: 2, font: .rounded, radius: 24, pattern: 1)
        case "peach":    return ThemeLook(icon: 2, font: .rounded, radius: 26, pattern: 2)
        case "ocean":    return ThemeLook(icon: 0, font: .standard, radius: 20, pattern: 3)
        case "sunset":   return ThemeLook(icon: 2, font: .rounded, radius: 26, pattern: 0)
        case "sakura":   return ThemeLook(icon: 2, font: .rounded, radius: 28, pattern: 2)
        case "graphite": return ThemeLook(icon: 0, font: .standard, radius: 12, pattern: 0)
        case "cosmos":   return ThemeLook(icon: 1, font: .standard, radius: 22, pattern: 1,
                                          pair: ("A78BFA", "F472B6"), mode: .dark)
        case "neon":     return ThemeLook(icon: 1, font: .mono, radius: 10, pattern: 0,
                                          pair: ("19F0E0", "FF3DCB"), mode: .dark)
        case "organic":  return ThemeLook(icon: 2, font: .serif, radius: 14, pattern: 3,
                                          pair: ("8A6A3C", "6B8E4E"))
        default:         return ThemeLook(icon: 0, font: .rounded, radius: 22, pattern: 0)   // «Свежесть» — стандарт
        }
    }
}

// MARK: - Действия хранилища (оформление)

extension Store {
    /// Единая анимация для любых правок оформления — без рывков.
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let rigidGen = UIImpactFeedbackGenerator(style: .rigid)

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
        withAnimation(Store.spring) { data.profile = pr }
        success()
        glassSound()
    }

    /// Слайдер округления: микро-вибрация на каждый пиксель, «упор» на краях.
    func setRadius(_ raw: Double) {
        let v = min(30, max(0, raw.rounded()))
        guard v != p.radius else { return }
        data.profile.radius = v
        guard p.haptics else { return }
        Store.selectionGen.selectionChanged()
        Store.selectionGen.prepare()
        if v == 0 || v == 30 { Store.rigidGen.impactOccurred(intensity: 0.7) }
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
        withAnimation(Store.spring) { data.profile = pr }
        tap()
    }

    func glassSound() {
        guard p.sound else { return }
        GlassSound.shared.play()
    }
}

// MARK: - «Стеклянный» звук (синтезируется на лету, файлы не нужны)

final class GlassSound {
    static let shared = GlassSound()
    private var player: AVAudioPlayer?

    private init() {
        player = try? AVAudioPlayer(data: Self.makeWAV())
        player?.volume = 0.6
        player?.prepareToPlay()
    }

    func play() {
        // .ambient: не прерывает музыку и уважает беззвучный режим
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        player?.currentTime = 0
        player?.play()
    }

    /// Короткий колокольчик: несколько гармоник с быстрым затуханием.
    private static func makeWAV() -> Data {
        let rate = 44_100
        let count = Int(Double(rate) * 0.45)
        let partials: [(freq: Double, amp: Double, decay: Double)] = [
            (1568, 0.50, 9), (2349, 0.30, 12), (3136, 0.20, 16), (4186, 0.10, 22)
        ]
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            var v = 0.0
            for p in partials { v += p.amp * sin(2 * .pi * p.freq * t) * exp(-p.decay * t) }
            v *= min(1, t / 0.003) * 0.6
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

// MARK: - Иконка в трёх стилях

struct StyledIcon: View {
    @EnvironmentObject var store: Store
    let systemName: String
    var size: CGFloat = 22
    var color: Color? = nil
    /// Переопределения нужны только для миниатюр других тем.
    var style: Int? = nil
    var radius: CGFloat? = nil
    var dim = false

    var body: some View {
        let st = style ?? store.p.iconStyle
        let c = color ?? store.meColor
        let r = radius ?? store.radius

        ZStack {
            switch st {
            case 1:
                Image(systemName: systemName)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(c)
                    .shadow(color: c.opacity(dim ? 0.3 : 1), radius: size * 0.22)
                    .shadow(color: c.opacity(dim ? 0.15 : 0.8), radius: size * 0.5)
                    .id(st)
            case 2:
                let tile = RoundedRectangle(cornerRadius: min(r, size * 0.7), style: .continuous)
                Image(systemName: systemName)
                    .font(.system(size: size * 0.78, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                    .frame(width: size * 1.7, height: size * 1.7)
                    .background(tile.fill(LinearGradient(colors: [c.opacity(dim ? 0.6 : 0.95), c.opacity(dim ? 0.3 : 0.55)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(tile.strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.05)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: c.opacity(dim ? 0 : 0.4), radius: 6, y: 4)
                    .id(st)
            default:
                Image(systemName: systemName)
                    .font(.system(size: size, weight: .light))
                    .foregroundStyle(c)
                    .id(st)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .frame(width: size * 1.7, height: size * 1.7)
    }
}

/// Нижняя панель со стилем иконок. Для «контурных» остаётся родная панель iOS.
struct StyledTabBar: View {
    @EnvironmentObject var store: Store
    @Binding var tab: Int

    var body: some View {
        let items = store.bar.map { ($0.title, $0.icon) } + [("Ещё", "square.grid.2x2")]
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let on = tab == i
                Button { tab = i } label: {
                    VStack(spacing: 2) {
                        StyledIcon(systemName: items[i].1, size: 18, color: on ? store.meColor : .secondary, dim: !on)
                        Text(items[i].0)
                            .font(.system(size: 10, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? store.meColor : .secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 6)
        .glass(RoundedRectangle(cornerRadius: max(store.radius, 12) + 10, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 2)
    }
}

// MARK: - Узоры фона

struct PatternOverlay: View {
    let kind: Int       // 1 точки, 2 сердечки, 3 волны
    var body: some View {
        if kind > 0 {
            Canvas { ctx, size in
                let ink = Color.primary.opacity(0.09)
                switch kind {
                case 1:
                    let step: CGFloat = 28
                    for row in 0..<Int(size.height / step) + 1 {
                        for col in 0..<Int(size.width / step) + 1 {
                            let x = CGFloat(col) * step + (row.isMultiple(of: 2) ? 0 : step / 2)
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: CGFloat(row) * step, width: 4, height: 4)), with: .color(ink))
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
                        ctx.stroke(path, with: .color(ink), lineWidth: 1.5)
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

struct ThemePreviewCard: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    let def: ThemeDef

    var body: some View {
        let look = ThemeLook.of(def.id)
        let dark = look.mode == .dark || (look.mode == nil && scheme == .dark)
        let top = Color(hex: dark ? def.topD : def.topL)
        let bg = Color(hex: dark ? def.bgD : def.bgL)
        let card = Color(hex: dark ? def.cardD : def.cardL)
        let accent = look.pair.map { Color(hex: $0.0) } ?? store.meColor
        let ink: Color = dark ? .white : Color(hex: "1B1B1F")
        let r = CGFloat(look.radius)
        let on = def.id == store.p.themeID

        Button { store.applyPreset(def) } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: r + 4, style: .continuous)
                        .fill(LinearGradient(colors: [top, bg], startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ещё").font(.system(size: 16, weight: .bold, design: look.font.design)).foregroundStyle(ink)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                            ForEach(["bubble.left.fill", "safari", "lock.fill", "gamecontroller.fill"], id: \.self) { sym in
                                ZStack {
                                    RoundedRectangle(cornerRadius: r * 0.55, style: .continuous).fill(card)
                                    StyledIcon(systemName: sym, size: 14, color: accent, style: look.icon, radius: r * 0.4)
                                }
                                .frame(height: 44)
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
                .overlay(RoundedRectangle(cornerRadius: r + 4, style: .continuous)
                    .strokeBorder(accent, lineWidth: on ? 3 : 0))
                .scaleEffect(on ? 1.03 : 1)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                Text(def.title).font(.caption.weight(on ? .bold : .regular)).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
