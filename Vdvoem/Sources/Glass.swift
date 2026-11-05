import SwiftUI

// MARK: - Движение: одна кривая на всё приложение

enum Motion {
    /// cubic-bezier(0.22, 1, 0.36, 1): быстро стартует, мягко садится.
    static func curve(_ d: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: d) }
    static let enter = curve(0.34)
    /// Уходящий экран остаётся непрозрачным, пока входящий не закончил появление.
    static let exit = Animation.linear(duration: 0.01).delay(0.34)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.88)
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
        if on {
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
