import SwiftUI
import UIKit

// Набор «живых» элементов. Идеи — с сайтов transitions.dev, Devigner UI, Ovio, Notchset, Mewo:
// двигаем только положение и прозрачность (дёшево для GPU), нажатия «пружинят», опасное подтверждается удержанием.

// MARK: - Тряска при ошибке

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 9
    var shakes: CGFloat = 3
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(progress * .pi * shakes * 2) * (1 - progress), y: 0))
    }
}

extension View {
    /// Тряска при ошибке: увеличьте `trigger`, чтобы встряхнуть.
    func shake(_ trigger: Int) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Int
    @State private var p: CGFloat = 0
    func body(content: Content) -> some View {
        content.modifier(ShakeEffect(progress: p))
            .onChange(of: trigger) { _, _ in
                p = 0
                withAnimation(.linear(duration: 0.42)) { p = 1 }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
    }
}

// MARK: - Удержать для подтверждения

/// Кнопка опасного действия: палец нужно подержать, кольцо заполняется, потом действие выполняется.
struct HoldToConfirm: View {
    @EnvironmentObject var store: Store
    let title: String
    var hold: Double = 0.9
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var done = false

    var body: some View {
        ZStack {
            Capsule().fill(Color.red.opacity(0.12))
            GeometryReader { g in
                Capsule().fill(Color.red.opacity(0.85)).frame(width: max(0, g.size.width * progress))
            }
            .clipShape(Capsule())
            Text(done ? "Готово" : (pressing ? "Держите…" : title))
                .font(.headline).foregroundStyle(progress > 0.5 ? .white : .red)
                .contentTransition(.opacity)
        }
        .frame(height: 52)
        .scaleEffect(pressing ? 0.98 : 1)
        .animation(Motion.press, value: pressing)
        .onLongPressGesture(minimumDuration: hold, maximumDistance: 40, pressing: { p in
            pressing = p
            if p {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.linear(duration: hold)) { progress = 1 }
            } else if !done {
                withAnimation(Motion.curve(0.25)) { progress = 0 }
            }
        }, perform: {
            done = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            action()
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Нажмите и удерживайте")
    }
}

/// Маленькая корзинка с кольцом: удалить можно только удержанием.
struct HoldTrash: View {
    let action: () -> Void
    var hold: Double = 0.7
    @State private var progress: CGFloat = 0
    @State private var pressing = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: progress).stroke(Color.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(pressing ? Color.red : Color.secondary)
        }
        .frame(width: 32, height: 32)
        .contentShape(Circle())
        .scaleEffect(pressing ? 1.15 : 1)
        .animation(Motion.bouncy, value: pressing)
        .onLongPressGesture(minimumDuration: hold, maximumDistance: 30, pressing: { p in
            pressing = p
            if p { withAnimation(.linear(duration: hold)) { progress = 1 } }
            else { withAnimation(Motion.curve(0.2)) { progress = 0 } }
        }, perform: {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            action()
        })
        .accessibilityLabel("Удалить: удерживайте")
    }
}

// MARK: - Галочка, которая рисуется

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.24, y: r.midY + r.height * 0.02))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.68))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.78, y: r.minY + r.height * 0.30))
        return p
    }
}

struct DrawnCheck: View {
    let done: Bool
    let color: Color
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.55), lineWidth: 1.6).opacity(done ? 0 : 1)
            Circle().fill(color).scaleEffect(done ? 1 : 0.2).opacity(done ? 1 : 0)
            CheckShape().trim(from: 0, to: done ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
                .animation(.easeOut(duration: 0.22).delay(done ? 0.08 : 0), value: done)
        }
        .frame(width: size, height: size)
        .animation(Motion.bouncy, value: done)
    }
}

// MARK: - Блик по тексту (ожидание)

struct ShimmerText: ViewModifier {
    var active = true
    @State private var phase: CGFloat = -0.6
    func body(content: Content) -> some View {
        if active && !Motion.reduced {
            content
                .overlay {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.5)
                            .offset(x: g.size.width * phase)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
                .onAppear { withAnimation(.linear(duration: 1.7).repeatForever(autoreverses: false)) { phase = 1.1 } }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(ShimmerText(active: active)) }
}

// MARK: - Двойной тап: сердечко

struct DoubleTapHeart: ViewModifier {
    let action: () -> Void
    @State private var burst = 0
    @State private var pop = false
    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    HeartBurst(trigger: burst).allowsHitTesting(false)
                    Image(systemName: "heart.fill").font(.system(size: 64)).foregroundStyle(Color(hex: "F43F5E"))
                        .shadow(color: .black.opacity(0.25), radius: 8)
                        .scaleEffect(pop ? 1 : 0.2).opacity(pop ? 1 : 0).allowsHitTesting(false)
                }
            }
            .onTapGesture(count: 2) {
                burst += 1
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { pop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { withAnimation(.easeOut(duration: 0.2)) { pop = false } }
                action()
            }
    }
}

extension View {
    func doubleTapHeart(_ action: @escaping () -> Void) -> some View { modifier(DoubleTapHeart(action: action)) }
}

// MARK: - Стереть, чтобы открыть

/// Закрывает содержимое «защитным слоем», который стирают пальцем. Открытое состояние запоминается по `key`.
struct ScratchCard<Content: View>: View {
    @EnvironmentObject var store: Store
    let key: String
    var hint = "Сотрите, чтобы открыть"
    var tint: Color = .pink
    @ViewBuilder let content: Content

    @State private var points: [CGPoint] = []
    @State private var cells = Set<Int>()
    @State private var open: Bool
    @State private var lastTick = 0

    init(key: String, hint: String = "Сотрите, чтобы открыть", tint: Color = .pink, @ViewBuilder content: () -> Content) {
        self.key = key; self.hint = hint; self.tint = tint; self.content = content()
        _open = State(initialValue: UserDefaults.standard.bool(forKey: "vd.scratch." + key))
    }

    private let cols = 12, rows = 8

    var body: some View {
        content
            .overlay {
                if !open {
                    GeometryReader { g in
                        cover(g.size)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in scratch(v.location, g.size) }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    }
                }
            }
            .animation(Motion.curve(0.35), value: open)
    }

    private func cover(_ size: CGSize) -> some View {
        ZStack {
            Canvas { ctx, sz in
                ctx.drawLayer { l in
                    l.fill(Path(CGRect(origin: .zero, size: sz)),
                           with: .linearGradient(Gradient(colors: [tint.opacity(0.95), tint.opacity(0.65), Color(hex: "B7A6FF")]),
                                                 startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)))
                    // Блёстки: фиксированный узор, не зависит от кадра
                    for i in 0..<28 {
                        let x = CGFloat((i * 53) % 100) / 100 * sz.width
                        let y = CGFloat((i * 37 + 11) % 100) / 100 * sz.height
                        l.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(0.5)))
                    }
                    l.blendMode = .clear
                    var path = Path()
                    for (i, p) in points.enumerated() {
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    l.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))
                    for p in points { l.fill(Path(ellipseIn: CGRect(x: p.x - 23, y: p.y - 23, width: 46, height: 46)), with: .color(.black)) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
            if points.count < 6 {
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw.fill").font(.system(size: 26))
                    Text(hint).font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 4)
                .allowsHitTesting(false)
            }
        }
    }

    private func scratch(_ p: CGPoint, _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if let last = points.last, hypot(last.x - p.x, last.y - p.y) < 5 { return }
        points.append(p)
        if points.count > 600 { points.removeFirst(points.count - 600) }
        let cx = min(cols - 1, max(0, Int(p.x / size.width * CGFloat(cols))))
        let cy = min(rows - 1, max(0, Int(p.y / size.height * CGFloat(rows))))
        // кисть закрашивает и соседние клетки
        for dx in -1...1 { for dy in -1...1 {
            let x = cx + dx, y = cy + dy
            if x >= 0, x < cols, y >= 0, y < rows { cells.insert(y * cols + x) }
        } }
        if points.count - lastTick > 14 {
            lastTick = points.count
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
        if cells.count >= Int(Double(cols * rows) * 0.62) {
            UserDefaults.standard.set(true, forKey: "vd.scratch." + key)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            open = true
        }
    }
}

// MARK: - Радиальное меню (зажать — вокруг пальца раскрывается круг)

struct DialItem: Identifiable {
    let id: String
    let emoji: String
    let title: String
}

@MainActor
final class DialState: ObservableObject {
    @Published var active = false
    @Published var center: CGPoint = .zero
    @Published var items: [DialItem] = []
    @Published var hover: Int? = nil
    private var feedback = UISelectionFeedbackGenerator()

    func begin(_ items: [DialItem], at p: CGPoint) {
        self.items = items
        center = p
        hover = nil
        feedback.prepare()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) { active = true }
    }

    func move(to p: CGPoint) {
        guard active, !items.isEmpty else { return }
        let dx = p.x - center.x, dy = p.y - center.y
        let dist = hypot(dx, dy)
        var new: Int? = nil
        if dist > 38 {
            var a = atan2(dy, dx) + .pi / 2          // 0 — вверх, по часовой
            if a < 0 { a += 2 * .pi }
            let step = 2 * Double.pi / Double(items.count)
            new = Int((a + step / 2).truncatingRemainder(dividingBy: 2 * .pi) / step) % items.count
        }
        if new != hover {
            hover = new
            if new != nil { feedback.selectionChanged() }
        }
    }

    /// Палец отпущен: возвращает выбранный пункт.
    func end() -> DialItem? {
        let pick = hover.map { items[$0] }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { active = false; hover = nil }
        return pick
    }
}

struct DialOverlay: View {
    @EnvironmentObject var dial: DialState
    @EnvironmentObject var store: Store
    private let radius: CGFloat = 92

    var body: some View {
        GeometryReader { g in
            if dial.active {
                let c = CGPoint(x: min(max(dial.center.x, radius + 34), g.size.width - radius - 34),
                                y: min(max(dial.center.y, radius + 90), g.size.height - radius - 90))
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea().transition(.opacity)
                    ZStack {
                        Circle().fill(.ultraThinMaterial).frame(width: radius * 2 + 56, height: radius * 2 + 56)
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                        Circle().fill(store.meColor.opacity(0.25)).frame(width: 30, height: 30)
                        ForEach(Array(dial.items.enumerated()), id: \.element.id) { i, item in
                            let a = Double(i) / Double(dial.items.count) * 2 * .pi - .pi / 2
                            let on = dial.hover == i
                            Text(item.emoji).font(.system(size: 30))
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(on ? store.meColor.opacity(0.35) : Color.white.opacity(0.14)))
                                .scaleEffect(on ? 1.35 : 1)
                                .offset(x: CGFloat(cos(a)) * radius, y: CGFloat(sin(a)) * radius)
                                .animation(Motion.bouncy, value: on)
                        }
                        if let h = dial.hover {
                            Text(dial.items[h].title).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.55), in: Capsule())
                                .offset(y: -radius - 60).transition(.opacity)
                        }
                    }
                    .position(c)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

extension View {
    /// Зажмите — вокруг пальца раскроется круг; ведите к нужному пункту и отпустите.
    func dialMenu(_ items: [DialItem], onPick: @escaping (DialItem) -> Void) -> some View {
        modifier(DialMenuModifier(items: items, onPick: onPick))
    }
}

private struct DialMenuModifier: ViewModifier {
    @EnvironmentObject var dial: DialState
    let items: [DialItem]
    let onPick: (DialItem) -> Void
    @GestureState private var held = false

    func body(content: Content) -> some View {
        content.gesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { v in
                    if case .second(true, let drag?) = v {
                        if !dial.active { dial.begin(items, at: drag.startLocation) }
                        dial.move(to: drag.location)
                    }
                }
                .onEnded { _ in
                    if let pick = dial.end() { onPick(pick) }
                }
        )
    }
}
