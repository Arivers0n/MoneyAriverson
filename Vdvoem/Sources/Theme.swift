import SwiftUI

// MARK: - Пресеты тем

struct ThemeDef: Identifiable, Hashable {
    let id: String
    let title: String
    let bgL: String, bgD: String
    let topL: String, topD: String
    let cardL: String, cardD: String
    let fieldL: String, fieldD: String

    static let all: [ThemeDef] = [
        ThemeDef(id: "fresh", title: "Свежесть", bgL: "EEF9E2", bgD: "0C1610", topL: "C8F0A4", topD: "1B3B22",
                 cardL: "FFFFFF", cardD: "17241B", fieldL: "E2F1D3", fieldD: "223427"),
        ThemeDef(id: "classic", title: "Классика", bgL: "F4F3F0", bgD: "0D0E12", topL: "F4F3F0", topD: "0D0E12",
                 cardL: "FFFFFF", cardD: "1A1B20", fieldL: "ECEBE7", fieldD: "24262D"),
        ThemeDef(id: "mint", title: "Мята", bgL: "EEF7E6", bgD: "0E1712", topL: "D6F2B8", topD: "17331F",
                 cardL: "FFFFFF", cardD: "18251D", fieldL: "E3EFD8", fieldD: "223329"),
        ThemeDef(id: "lavender", title: "Сирень", bgL: "F1EEFB", bgD: "12101C", topL: "DCD3F7", topD: "271F45",
                 cardL: "FFFFFF", cardD: "1B1829", fieldL: "E6E1F6", fieldD: "262238"),
        ThemeDef(id: "peach", title: "Персик", bgL: "FDF1EA", bgD: "1A1210", topL: "FFD6BE", topD: "3D2119",
                 cardL: "FFFFFF", cardD: "241A17", fieldL: "F6E5DA", fieldD: "33251F"),
        ThemeDef(id: "ocean", title: "Океан", bgL: "EAF3FA", bgD: "0B1219", topL: "C6E2F7", topD: "113454",
                 cardL: "FFFFFF", cardD: "15202B", fieldL: "DDEAF4", fieldD: "1E2D3B"),
        ThemeDef(id: "sunset", title: "Закат", bgL: "FDEFF0", bgD: "1A0F14", topL: "FBC4D2", topD: "4D1E36",
                 cardL: "FFFFFF", cardD: "25161C", fieldL: "F6E2E5", fieldD: "35222B"),
        ThemeDef(id: "sakura", title: "Сакура", bgL: "FDF0F5", bgD: "1B1016", topL: "F9CFE2", topD: "3E1A33",
                 cardL: "FFFFFF", cardD: "241520", fieldL: "F6E1EA", fieldD: "33202D"),
        ThemeDef(id: "graphite", title: "Графит", bgL: "EFEFF1", bgD: "0A0A0B", topL: "DEDFE3", topD: "1A1B1F",
                 cardL: "FFFFFF", cardD: "17171A", fieldL: "E4E4E8", fieldD: "222226"),
        ThemeDef(id: "cosmos", title: "Космос", bgL: "ECE8FA", bgD: "0B0820", topL: "CFC4F5", topD: "2A1760",
                 cardL: "FFFFFF", cardD: "1A1438", fieldL: "E2DCF5", fieldD: "261E4A"),
        ThemeDef(id: "neon", title: "Неон", bgL: "E8F7F7", bgD: "05070C", topL: "BDF3F0", topD: "08323A",
                 cardL: "FFFFFF", cardD: "0E141C", fieldL: "D8EEEE", fieldD: "16202B"),
        ThemeDef(id: "organic", title: "Органика", bgL: "F5EEDF", bgD: "15130E", topL: "E6D7B8", topD: "3A3220",
                 cardL: "FFFDF7", cardD: "211E16", fieldL: "EBE2CF", fieldD: "2C281D")
    ]

    static func find(_ id: String) -> ThemeDef { all.first { $0.id == id } ?? all[0] }
}

enum Theme {
    /// Текущая тема и стили. Обновляются хранилищем при каждой смене.
    static var current = ThemeDef.all[0]
    static var bgStyle = 0
    static var cardStyle = 0
    static var bgPattern = 0
    static var accent = Color(hex: "4C9AF0")
    static var accent2 = Color(hex: "D870A8")
}

enum Pal {
    static var bg: Color { Color(light: Color(hex: Theme.current.bgL), dark: Color(hex: Theme.current.bgD)) }
    static var top: Color { Color(light: Color(hex: Theme.current.topL), dark: Color(hex: Theme.current.topD)) }
    static var card: Color { Color(light: Color(hex: Theme.current.cardL), dark: Color(hex: Theme.current.cardD)) }
    static var field: Color { Color(light: Color(hex: Theme.current.fieldL), dark: Color(hex: Theme.current.fieldD)) }
}

/// Фон экрана: цветной верх, мягкие световые пятна, по желанию — медленная «аврора».
struct ThemeBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Pal.bg
            if Theme.bgStyle != 2 {
                if Theme.bgStyle == 1 {
                    TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                        blobs(t: tl.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    blobs(t: 0)
                }
            }
            PatternOverlay(kind: Theme.bgPattern)
        }
        .ignoresSafeArea()
    }

    private func blobs(t: Double) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let a = scheme == .dark ? 0.30 : 0.45
            ZStack {
                LinearGradient(colors: [Pal.top, Pal.top.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.55).frame(maxHeight: .infinity, alignment: .top)
                Circle().fill(Theme.accent.opacity(a * 0.55)).frame(width: w * 0.9)
                    .blur(radius: 70).offset(x: -w * 0.35 + CGFloat(sin(t / 5)) * 40, y: -h * 0.32 + CGFloat(cos(t / 6)) * 30)
                Circle().fill(Theme.accent2.opacity(a * 0.5)).frame(width: w * 0.8)
                    .blur(radius: 80).offset(x: w * 0.4 + CGFloat(cos(t / 7)) * 40, y: h * 0.05 + CGFloat(sin(t / 4)) * 40)
                Circle().fill(Theme.accent.opacity(a * 0.35)).frame(width: w * 0.7)
                    .blur(radius: 80).offset(x: -w * 0.2 + CGFloat(sin(t / 8)) * 50, y: h * 0.42)
            }
            .frame(width: w, height: h)
        }
    }
}

// MARK: - Обои чата

enum WallPattern { case none, dots, hearts, grid, waves, stars }

struct WallpaperDef: Identifiable, Hashable {
    let id: String
    let title: String
    let lightA: String, lightB: String
    let darkA: String, darkB: String
    let pattern: WallPattern

    static let all: [WallpaperDef] = [
        WallpaperDef(id: "none", title: "Без обоев", lightA: "F4F3F0", lightB: "F4F3F0", darkA: "0D0E12", darkB: "0D0E12", pattern: .none),
        WallpaperDef(id: "dots", title: "Точки", lightA: "F1EEFB", lightB: "E4E9FB", darkA: "14131F", darkB: "0F1424", pattern: .dots),
        WallpaperDef(id: "hearts", title: "Сердечки", lightA: "FDEFF3", lightB: "FBE0EA", darkA: "21121A", darkB: "2D1523", pattern: .hearts),
        WallpaperDef(id: "grid", title: "Клетка", lightA: "EEF5F2", lightB: "E3EFEA", darkA: "0F1A17", darkB: "0B1411", pattern: .grid),
        WallpaperDef(id: "waves", title: "Волны", lightA: "E7F2FB", lightB: "D3E8F8", darkA: "0C1824", darkB: "0A2036", pattern: .waves),
        WallpaperDef(id: "stars", title: "Звёзды", lightA: "EDE9FB", lightB: "DAD2F5", darkA: "0E0C1E", darkB: "1A1440", pattern: .stars),
        WallpaperDef(id: "sunset", title: "Закат", lightA: "FFE9DC", lightB: "FBD3DF", darkA: "2A1620", darkB: "3A1A33", pattern: .none),
        WallpaperDef(id: "forest", title: "Лес", lightA: "E6F3E4", lightB: "CFE8CD", darkA: "0E1A12", darkB: "10261A", pattern: .dots)
    ]

    static func find(_ id: String) -> WallpaperDef { all.first { $0.id == id } ?? all[0] }
}

struct WallpaperView: View {
    let id: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let w = WallpaperDef.find(id)
        let dark = scheme == .dark
        let a = Color(hex: dark ? w.darkA : w.lightA)
        let b = Color(hex: dark ? w.darkB : w.lightB)
        ZStack {
            LinearGradient(colors: [a, b], startPoint: .top, endPoint: .bottom)
            if w.pattern != .none {
                Canvas { ctx, size in draw(w.pattern, ctx: &ctx, size: size) }
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private func draw(_ p: WallPattern, ctx: inout GraphicsContext, size: CGSize) {
        let ink = Color.primary
        switch p {
        case .none: break
        case .dots:
            var y: CGFloat = 14
            while y < size.height {
                var x: CGFloat = 14
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(ink.opacity(0.10)))
                    x += 28
                }
                y += 28
            }
        case .hearts:
            var row = 0
            var y: CGFloat = 20
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 16 : 40
                while x < size.width {
                    ctx.draw(Text("♥").font(.system(size: 15)).foregroundColor(ink.opacity(0.09)), at: CGPoint(x: x, y: y))
                    x += 48
                }
                y += 34
                row += 1
            }
        case .grid:
            var x: CGFloat = 0
            while x < size.width {
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(ink.opacity(0.05)), lineWidth: 1)
                x += 30
            }
            var y: CGFloat = 0
            while y < size.height {
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(ink.opacity(0.05)), lineWidth: 1)
                y += 30
            }
        case .waves:
            var y: CGFloat = 30
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x <= size.width {
                    path.addLine(to: CGPoint(x: x, y: y + sin(x / 22) * 6))
                    x += 4
                }
                ctx.stroke(path, with: .color(ink.opacity(0.07)), lineWidth: 1.2)
                y += 36
            }
        case .stars:
            var row = 0
            var y: CGFloat = 18
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 14 : 44
                while x < size.width {
                    ctx.draw(Text("✦").font(.system(size: 11)).foregroundColor(ink.opacity(0.10)), at: CGPoint(x: x, y: y))
                    x += 56
                }
                y += 40
                row += 1
            }
        }
    }
}

// MARK: - Значки приложения

struct AppIconDef: Identifiable, Hashable {
    let id: String            // имя набора значков; пусто — основной
    let title: String
    let symbol: String
    let a: String
    let b: String

    static let all: [AppIconDef] = [
        AppIconDef(id: "", title: "Роза", symbol: "heart.fill", a: "FF8FB1", b: "E0457B"),
        AppIconDef(id: "AppIcon-Night", title: "Ночь", symbol: "moon.fill", a: "2B3A67", b: "0B1026"),
        AppIconDef(id: "AppIcon-Ocean", title: "Океан", symbol: "drop.fill", a: "5EC8F2", b: "2563EB"),
        AppIconDef(id: "AppIcon-Sunset", title: "Закат", symbol: "heart.fill", a: "FDBA74", b: "EC4899"),
        AppIconDef(id: "AppIcon-Lavender", title: "Сирень", symbol: "infinity", a: "C4B5FD", b: "7C3AED"),
        AppIconDef(id: "AppIcon-Gold", title: "Золото", symbol: "star.fill", a: "FDE68A", b: "D97706"),
        AppIconDef(id: "AppIcon-Mint", title: "Мята", symbol: "sparkle", a: "86EFAC", b: "059669"),
        AppIconDef(id: "AppIcon-Peach", title: "Персик", symbol: "heart.fill", a: "FFC8A8", b: "FB7185"),
        AppIconDef(id: "AppIcon-Candy", title: "Конфета", symbol: "infinity", a: "F9A8D4", b: "60A5FA"),
        AppIconDef(id: "AppIcon-Aurora", title: "Аврора", symbol: "sparkle", a: "6EE7B7", b: "8B5CF6"),
        AppIconDef(id: "AppIcon-Cosmos", title: "Космос", symbol: "star.fill", a: "4C1D95", b: "0F172A"),
        AppIconDef(id: "AppIcon-Mono", title: "Моно", symbol: "heart.fill", a: "9CA3AF", b: "374151"),
        AppIconDef(id: "AppIcon-Neon", title: "Неон", symbol: "sparkle", a: "22D3EE", b: "A855F7"),
        AppIconDef(id: "AppIcon-Berry", title: "Ягода", symbol: "drop.fill", a: "F472B6", b: "9D174D"),
        AppIconDef(id: "AppIcon-Lime", title: "Лайм", symbol: "heart.fill", a: "BEF264", b: "22C55E"),
        AppIconDef(id: "AppIcon-Ink", title: "Тушь", symbol: "infinity", a: "1F2937", b: "000000")
    ]
}

// MARK: - Экран «Оформление»

struct AppearanceView: View {
    @EnvironmentObject var store: Store
    @State private var iconError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                section("Предпросмотр тем") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) { ForEach(ThemeDef.all) { t in ThemePreviewCard(def: t) } }
                            .scrollTargetLayout()
                            .padding(.vertical, 6)
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
                LivePreview()
                section("Тема") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                        ForEach(ThemeDef.all) { t in themeTile(t) }
                    }
                    Picker("Режим", selection: $store.data.profile.theme) {
                        ForEach(ThemeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                section("Цвета пары") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(colorPairs) { p in pairTile(p) }
                    }
                    HStack(spacing: 14) {
                        ColorPicker(store.name(.me), selection: Binding(
                            get: { Color(hex: store.p.myHex) }, set: { store.data.profile.myHex = $0.hex }), supportsOpacity: false)
                        ColorPicker(store.name(.partner), selection: Binding(
                            get: { Color(hex: store.p.partnerHex) }, set: { store.data.profile.partnerHex = $0.hex }), supportsOpacity: false)
                    }
                    .font(.subheadline)
                }
                section("Фон") {
                    choice([("Свечение", "sparkles"), ("Аврора", "wind"), ("Однотонный", "square.fill")], $store.data.profile.bgStyle)
                    Text("«Аврора» — цветные пятна медленно плавают за карточками.").font(.caption).foregroundStyle(.secondary)
                    Text("Узор").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) { ForEach(0..<4, id: \.self) { k in patternDot(k) } }
                            .padding(.vertical, 8).padding(.horizontal, 6)
                    }
                }
                section("Иконки") {
                    Picker("Стиль иконок", selection: Binding(get: { store.p.iconStyle }, set: { store.setIconStyle($0) })) {
                        Text("Контурные").tag(0)
                        Text("Неоновые").tag(1)
                        Text("Объёмные").tag(2)
                    }.pickerStyle(.segmented)
                    HStack {
                        ForEach(["heart.fill", "calendar", "bubble.left.fill", "star.fill", "gearshape.fill"], id: \.self) {
                            StyledIcon(systemName: $0, size: 22).frame(maxWidth: .infinity)
                        }
                    }
                    Text("Применяется к нижней панели и спискам функций. У «контурных» остаётся родная панель iOS.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                section("Карточки") {
                    choice([("Мягкие", "rectangle.fill"), ("Плоские", "rectangle"), ("Контур", "rectangle.dashed")], $store.data.profile.cardStyle)
                }
                section("Обои чата") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) { ForEach(WallpaperDef.all) { w in wallTile(w) } }.padding(.vertical, 4)
                    }
                    Picker("Пузыри", selection: $store.data.profile.bubbleStyle) {
                        Text("Круглые").tag(0)
                        Text("Мягкие").tag(1)
                        Text("Острые").tag(2)
                    }.pickerStyle(.segmented)
                }
                section("Значок приложения") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                        ForEach(AppIconDef.all) { i in iconTile(i) }
                    }
                    if let e = iconError { Text(e).font(.footnote).foregroundStyle(.red) }
                }
                section("Шрифт и форма") {
                    Picker("Шрифт", selection: Binding(get: { store.p.design }, set: { store.setFont($0) })) {
                        ForEach(DesignStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("Скругление").font(.subheadline)
                        Slider(value: Binding(get: { store.p.radius }, set: { store.setRadius($0) }), in: 0...30, step: 1)
                        Text("\(Int(store.p.radius))px").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    Toggle("Вибро-отклик", isOn: $store.data.profile.haptics)
                    Toggle("Звук при смене темы", isOn: $store.data.profile.sound)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Оформление")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сбросить") { store.resetAppearance() }
            }
        }
        .animation(Store.spring, value: store.p.themeID)
        .animation(Store.spring, value: store.p.cardStyle)
        .animation(Store.spring, value: store.p.radius)
        .animation(Store.spring, value: store.p.design)
    }

    private func patternDot(_ k: Int) -> some View {
        let on = store.p.bgPattern == k
        return Button { store.setPattern(k) } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: [store.meColor.opacity(0.55), store.meColor.opacity(0.9)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: PatternOverlay.symbol(k)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .overlay(Circle().strokeBorder(Color.primary, lineWidth: on ? 2.5 : 0).padding(-5))
            .scaleEffect(on ? 1.06 : 1)
            .accessibilityLabel(PatternOverlay.title(k))
        }
        .buttonStyle(.plain)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary).tracking(1)
            c()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func choice(_ items: [(String, String)], _ sel: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                let on = sel.wrappedValue == i
                Button { sel.wrappedValue = i; store.tap() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: it.1).font(.title3)
                        Text(it.0).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(on ? .white : .primary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(on ? AnyShapeStyle(store.meColor) : AnyShapeStyle(Pal.field), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pairTile(_ p: ColorPair) -> some View {
        let on = store.p.myHex == p.me && store.p.partnerHex == p.partner
        return Button {
            store.data.profile.myHex = p.me; store.data.profile.partnerHex = p.partner; store.tap()
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: -10) {
                    Circle().fill(Color(hex: p.me)).frame(width: 30, height: 30)
                    Circle().fill(Color(hex: p.partner)).frame(width: 30, height: 30)
                }
                Text(p.id).font(.system(size: 10, weight: .medium)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Pal.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Color.primary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func themeTile(_ t: ThemeDef) -> some View {
        let on = store.p.themeID == t.id
        let dark = ThemeLook.of(t.id).mode == .dark
        return Button {
            store.applyPreset(t)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: dark ? t.topD : t.topL), Color(hex: dark ? t.bgD : t.bgL)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    Capsule().fill(Color(hex: dark ? t.cardD : t.cardL)).frame(width: 26, height: 12).offset(y: 10)
                }
                .frame(width: 58, height: 58)
                .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .overlay(Circle().strokeBorder(Color.primary, lineWidth: on ? 2.5 : 0).padding(-4))
                .scaleEffect(on ? 1.05 : 1)
                Text(t.title).font(.caption2.weight(on ? .bold : .regular)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func wallTile(_ w: WallpaperDef) -> some View {
        let on = store.p.wallpaper == w.id
        return Button {
            store.data.profile.wallpaper = w.id
            store.tap()
        } label: {
            VStack(spacing: 6) {
                WallpaperPreview(id: w.id)
                    .frame(width: 74, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(on ? store.meColor : Color.primary.opacity(0.1), lineWidth: on ? 2.5 : 1))
                Text(w.title).font(.caption2.weight(on ? .bold : .regular)).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconTile(_ i: AppIconDef) -> some View {
        let on = store.p.iconID == i.id
        return Button { setIcon(i) } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: i.a), Color(hex: i.b)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: i.symbol).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(on ? store.meColor : Color.clear, lineWidth: 3).padding(-3))
                Text(i.title).font(.caption2.weight(on ? .bold : .regular)).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func setIcon(_ i: AppIconDef) {
        iconError = nil
        UIApplication.shared.setAlternateIconName(i.id.isEmpty ? nil : i.id) { err in
            DispatchQueue.main.async {
                if let err {
                    iconError = "Не удалось сменить значок: \(err.localizedDescription)"
                } else {
                    store.data.profile.iconID = i.id
                    store.tap()
                }
            }
        }
    }
}

/// Мини-экран: показывает, как выглядят выбранные тема, цвета, карточки и пузыри.
struct LivePreview: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let bubble: CGFloat = store.p.bubbleStyle == 1 ? 12 : (store.p.bubbleStyle == 2 ? 5 : 18)
        ZStack {
            WallpaperView(id: store.p.wallpaper)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "frying.pan.fill").font(.title3).foregroundStyle(.white)
                        .frame(width: 42, height: 42).background(.white.opacity(0.2), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Готовлю").font(.headline).foregroundStyle(.white)
                        Text("\(store.name(.partner)) · 10 мин назад").font(.caption).foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                }
                .padding(12)
                .background(LinearGradient(colors: [Color(hex: "E8590C"), Color(hex: "E8590C").opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: store.radius, style: .continuous))
                HStack {
                    Text("Что на ужин?").font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(store.partnerColor, in: RoundedRectangle(cornerRadius: bubble, style: .continuous)).foregroundStyle(.white)
                    Spacer()
                }
                HStack {
                    Spacer()
                    Text("Паста! Скоро буду ❤️").font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(store.meColor, in: RoundedRectangle(cornerRadius: bubble, style: .continuous)).foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    Label("Чат", systemImage: "bubble.left.fill").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34).background(store.meColor, in: Capsule())
                    ForEach(["heart", "photo", "map"], id: \.self) { Image(systemName: $0).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                .padding(5).background(Pal.card, in: Capsule())
            }
            .padding(14)
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
    }
}

struct WallpaperPreview: View {
    let id: String
    var body: some View {
        WallpaperView(id: id).allowsHitTesting(false)
    }
}
