import SwiftUI
import UIKit

// MARK: - Вибрация

enum Haptic {
    private static var on: Bool { Appearance.shared.haptics }
    private static var strength: CGFloat {
        switch Appearance.shared.hapticStrength {
        case "soft": return 0.5
        case "strong": return 1.0
        default: return 0.75
        }
    }
    /// Лёгкий щелчок: кнопки, переключатели.
    static func tap() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: strength)
    }
    /// Плотнее: открыть экран, начать запись.
    static func press() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: strength)
    }
    /// Перелистывание месяца, выбор в списке.
    static func select() {
        guard on else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func heavy() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: strength)
    }
}

// MARK: - Анимации

enum Motion {
    /// full — всё, calm — без покачиваний и конфетти, off — почти без анимаций.
    static var level: String {
        UIAccessibility.isReduceMotionEnabled ? "off" : Appearance.shared.motion
    }
    static var full: Bool { level == "full" }
    static var enabled: Bool { level != "off" }
    static var spring: Animation? { enabled ? .spring(response: 0.42, dampingFraction: 0.82) : nil }
    static var snappy: Animation? { enabled ? .snappy(duration: 0.3) : nil }
    static func stagger(_ i: Int) -> Animation? {
        enabled ? .spring(response: 0.5, dampingFraction: 0.85).delay(Double(min(i, 12)) * 0.03) : nil
    }
}

/// Кнопка, которая мягко «проседает» при нажатии и щёлкает вибрацией.
struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.94
    var haptic = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && Motion.enabled ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.enabled ? .spring(response: 0.25, dampingFraction: 0.6) : nil, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in
                if down && haptic { Haptic.tap() }
            }
    }
}

/// Сумма, которая «прокручивается» к новому значению, и при появлении считает с нуля.
struct RollingAmount: View {
    let value: Double
    var font: Font = .system(size: 64, weight: .bold)
    var signed = true
    var masked = false
    @State private var shown: Double = 0
    @State private var appeared = false

    var body: some View {
        Text(masked ? "••••• ₽" : (signed ? Fmt.rub(shown) : Fmt.rubU(shown)))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: shown))
            .onAppear {
                guard !appeared else { return }
                appeared = true
                if Motion.full && abs(value) > 0 {
                    shown = 0
                    withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(0.1)) { shown = value }
                } else {
                    shown = value
                }
            }
            .onChange(of: value) { _, v in
                withAnimation(Motion.spring) { shown = v }
            }
    }
}

/// Плавное появление снизу при первом показе.
struct AppearIn: ViewModifier {
    @MainActor static var burstStart = Date.distantPast
    @MainActor static var lastAppear = Date.distantPast
    var index: Int = 0
    @State private var visible = false
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .onAppear {
                guard !visible else { return }
                // Анимируем только «пачку» появлений при открытии экрана, а не каждую строку при прокрутке
                let now = Date()
                if now.timeIntervalSince(Self.lastAppear) > 0.45 { Self.burstStart = now }
                Self.lastAppear = now
                let fresh = now.timeIntervalSince(Self.burstStart) < 0.5
                if fresh, let a = Motion.stagger(index) { withAnimation(a) { visible = true } } else { visible = true }
            }
    }
}

extension View {
    func appearIn(_ index: Int = 0) -> some View { modifier(AppearIn(index: index)) }
}
