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
    /// full — всё, calm — без движения (только мягкие проявления), off — без анимаций.
    /// Системное «Уменьшение движения» = calm: убираем перемещения, но оставляем плавность.
    static var level: String {
        let chosen = Appearance.shared.motion
        if UIAccessibility.isReduceMotionEnabled && chosen == "full" { return "calm" }
        return chosen
    }
    static var full: Bool { level == "full" }
    static var enabled: Bool { level != "off" }
    /// Можно ли сдвигать и масштабировать элементы (в «спокойном» режиме — нет).
    static var moves: Bool { level == "full" }

    // Единые токены движения — все экраны берут кривые отсюда.
    /// Основная пружина интерфейса (≈ duration 0.4, bounce 0.15).
    static var spring: Animation? { enabled ? .spring(duration: 0.4, bounce: 0.15) : nil }
    /// Быстрые переключения: месяц, вкладки, чекбоксы.
    static var snappy: Animation? { enabled ? .spring(duration: 0.28, bounce: 0.1) : nil }
    /// Нажатие: палец вниз — мгновенный отклик.
    static let pressDown: Animation = .easeOut(duration: 0.1)
    /// Отпускание — пружина возвращает форму.
    static let pressUp: Animation = .spring(duration: 0.3, bounce: 0.2)
    /// Праздничный «поп» — редкие моменты (успех, конфетти, быстрая запись).
    static var pop: Animation? { moves ? .spring(duration: 0.35, bounce: 0.35) : (enabled ? .easeOut(duration: 0.2) : nil) }
    /// Появление элементов: сильный ease-out (cubic-bezier 0.23, 1, 0.32, 1).
    static func entrance(_ d: Double = 0.45) -> Animation? { enabled ? .timingCurve(0.23, 1, 0.32, 1, duration: d) : nil }
    static func stagger(_ i: Int) -> Animation? {
        guard enabled else { return nil }
        return .timingCurve(0.23, 1, 0.32, 1, duration: 0.45).delay(Double(min(i, 10)) * 0.04)
    }
}

/// Кнопка, которая «проседает» при нажатии: вниз — быстро, обратно — пружиной.
/// Вибрация по умолчанию выключена: частые нажатия не должны жужжать, вибрируют только важные события.
struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.96
    var haptic = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && Motion.enabled ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.enabled ? (configuration.isPressed ? Motion.pressDown : Motion.pressUp) : nil, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in
                if down && haptic { Haptic.tap() }
            }
    }
}

/// Сумма, которая «прокручивается» к новому значению, и при появлении считает с нуля.
struct RollingAmount: View {
    /// Счёт «с нуля» — редкий момент: только при первом показе после запуска приложения.
    @MainActor static var counted = false
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
                if Motion.full && abs(value) > 0 && !Self.counted {
                    Self.counted = true
                    shown = 0
                    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.9).delay(0.1)) { shown = value }
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
            .offset(y: visible || !Motion.moves ? 0 : 10)
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
