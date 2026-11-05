import SwiftUI
import UIKit

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

/// Цветная «плитка-картинка» раздела: пастельный фон, большая эмодзи, мягкий блик.
struct ArtTile: View {
    let emoji: String
    let hex: String
    var size: CGFloat = 52
    var body: some View {
        let c = Color(hex: hex)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(LinearGradient(colors: [c.opacity(0.95), c.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center))
            Text(emoji).font(.system(size: size * 0.56)).shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        }
        .frame(width: size, height: size)
        .shadow(color: c.opacity(0.45), radius: 8, y: 5)
    }
}


// MARK: - Место под плавающий док

/// Увеличивает нижнюю безопасную зону всего окна на высоту дока. Так прокрутка, поле ввода чата
/// и нижние кнопки на любом экране (в том числе открытом из «Ещё») заканчиваются выше дока,
/// а содержимое при этом по-прежнему проезжает под стеклом.
struct DockInset: UIViewControllerRepresentable {
    let bottom: CGFloat
    func makeUIViewController(context: Context) -> InsetController { InsetController() }
    func updateUIViewController(_ vc: InsetController, context: Context) { vc.bottom = bottom }

    final class InsetController: UIViewController {
        var bottom: CGFloat = 0 { didSet { if oldValue != bottom { apply() } } }
        private weak var target: UIViewController?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent == nil { target?.additionalSafeAreaInsets.bottom = 0 } else { apply() }
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); target?.additionalSafeAreaInsets.bottom = 0 }

        private func apply() {
            var top: UIViewController = self
            while let p = top.parent { top = p }
            target = top
            UIView.animate(withDuration: 0.25) {
                top.additionalSafeAreaInsets.bottom = self.bottom
                top.view.layoutIfNeeded()
            }
        }
    }
}

/// Нижний отступ экрана устройства (под индикатором «домой»), без учёта нашей вставки.
enum Screen2 {
    static var homeInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }
}
