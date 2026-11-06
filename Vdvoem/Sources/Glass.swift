import SwiftUI
import UIKit

// MARK: - Движение: одна кривая на всё приложение

enum Motion {
    /// Включено «Уменьшение движения» в настройках iPhone: переходы становятся короткими и без пружин.
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// cubic-bezier(0.22, 1, 0.36, 1): быстро стартует, мягко садится.
    static func curve(_ d: Double) -> Animation {
        reduced ? .easeOut(duration: min(d, 0.18)) : .timingCurve(0.22, 1, 0.36, 1, duration: d)
    }
    /// Появление и уход экранов: быстрее 300 мс, иначе частые переходы утомляют.
    static var enter: Animation { curve(0.26) }
    /// Нажатие: мгновенный отклик.
    static var press: Animation { .easeOut(duration: 0.1) }
    /// Обычная пружина: почти без отскока, всегда можно перехватить на лету.
    static var spring: Animation { reduced ? curve(0.2) : .spring(response: 0.38, dampingFraction: 0.92) }
    /// Для движений после жеста (перетаскивание, сброс на место): чуть пружинит, как физический предмет.
    static var bouncy: Animation { reduced ? curve(0.2) : .spring(response: 0.32, dampingFraction: 0.8) }
}

// MARK: - Жидкое стекло iOS 26 (на старых iOS — материал)

extension View {
    /// Стеклянная подложка в форме `shape`. На iOS 26 — настоящее Liquid Glass, на iOS 17–25 — матовый материал.
    @ViewBuilder
    func glass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive { self.glassEffect(.regular.tint(tint).interactive(), in: shape) }
                else { self.glassEffect(.regular.tint(tint), in: shape) }
            } else {
                if interactive { self.glassEffect(.regular.interactive(), in: shape) }
                else { self.glassEffect(.regular, in: shape) }
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background(shape.fill(tint ?? .clear))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
    }

    /// Стекло только для плавающих элементов (док, кнопки, подписи поверх контента).
    /// Карточки в прокручиваемом контенте стеклом не делаем: стекло на стекле мутнеет и грузит GPU.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(Capsule(style: .continuous), tint: tint, interactive: interactive)
    }

    /// Нижняя панель сворачивается при прокрутке (iOS 26).
    @ViewBuilder
    func tabBarCollapses() -> some View {
        if #available(iOS 26.0, *) { self.tabBarMinimizeBehavior(.onScrollDown) } else { self }
    }
}

/// Покачивание значков в режиме правки — как на рабочем столе iOS. Считается от времени, поэтому гладкое и без накопления состояния.
struct Jiggle: ViewModifier {
    let on: Bool
    let seed: Double
    func body(content: Content) -> some View {
        if on && !Motion.reduced {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                content.rotationEffect(.degrees(sin(t * 19 + seed) * 1.7))
                    .offset(y: CGFloat(sin(t * 23 + seed * 1.7)) * 0.6)
            }
        } else {
            content
        }
    }
}

extension View {
    func jiggle(_ on: Bool, seed: Double = 0) -> some View { modifier(Jiggle(on: on, seed: seed)) }
}


// MARK: - Шрифт заголовков навигации

/// Заголовки экранов рисует система, поэтому `.fontDesign` на них не действует: задаём шрифт через внешний вид панели.
enum NavFont {
    static func apply(_ style: DesignStyle) {
        let design: UIFontDescriptor.SystemDesign
        switch style {
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        case .standard: design = .default
        }
        func font(_ size: CGFloat, _ w: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: w)
            if let d = base.fontDescriptor.withDesign(design) { return UIFont(descriptor: d, size: size) }
            return base
        }
        let large = font(34, .bold), small = font(17, .semibold)
        func make(_ transparent: Bool) -> UINavigationBarAppearance {
            let a = UINavigationBarAppearance()
            if transparent { a.configureWithTransparentBackground() } else { a.configureWithDefaultBackground() }
            a.largeTitleTextAttributes = [.font: large]
            a.titleTextAttributes = [.font: small]
            return a
        }
        // Панель всегда прозрачная: фон экрана и обои идут до самого верха, без полосы-«крышки».
        let standard = make(true), edge = make(true)
        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = standard
        proxy.compactAppearance = standard
        proxy.scrollEdgeAppearance = edge
        // Уже созданные панели обновляем сразу.
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { refresh(w, standard, edge) }
        }
    }

    private static func refresh(_ v: UIView, _ s: UINavigationBarAppearance, _ e: UINavigationBarAppearance) {
        if let bar = v as? UINavigationBar {
            bar.standardAppearance = s
            bar.compactAppearance = s
            bar.scrollEdgeAppearance = e
        }
        for sub in v.subviews { refresh(sub, s, e) }
    }
}

/// Мягкий верхний край на iOS 26: содержимое уходит под шапку плавно, без полосы с резкой границей.
struct SoftTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
