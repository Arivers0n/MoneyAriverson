import SwiftUI

// MARK: - Общие «живые» элементы для игр

/// Салют из бумажек: рисуется на Canvas, сам затухает за 2,6 с. Родитель убирает его из иерархии.
struct ConfettiBurst: View {
    let colors: [Color]
    @State private var start = Date()
    @State private var finished = false
    private struct P {
        let x: Double, vx: Double, vy: Double, rot: Double, size: Double, color: Int, spin: Double
    }
    private let parts: [P] = (0..<80).map { _ in
        P(x: Double.random(in: 0.25...0.75), vx: Double.random(in: -0.4...0.4), vy: Double.random(in: -1.2 ... -0.45),
          rot: Double.random(in: 0...6.28), size: Double.random(in: 6...11), color: Int.random(in: 0..<100), spin: Double.random(in: -9...9))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40, paused: finished)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t < 2.6, !colors.isEmpty else { return }
                for p in parts {
                    let x = size.width * (p.x + p.vx * t)
                    let y = size.height * (0.42 + p.vy * t * 0.85 + 0.85 * t * t)
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.rot + p.spin * t))
                    c.opacity = max(0, 1 - t / 2.6)
                    c.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)), with: .color(colors[p.color % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .task { try? await Task.sleep(nanoseconds: 2_800_000_000); finished = true }
        .opacity(finished ? 0 : 1)
    }
}

/// Кольцо, которое расходится от активного игрока.
struct PulseRing: View {
    let color: Color
    var body: some View {
        Circle().stroke(color.opacity(0.55), lineWidth: 2)
            .phaseAnimator([0.0, 1.0]) { v, p in v.scaleEffect(1 + 0.45 * p).opacity(1 - p) } animation: { _ in .easeOut(duration: 1.3) }
    }
}

/// «Партнёр думает…» — три прыгающие точки.
struct TypingDots: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 6, height: 6)
                    .phaseAnimator([0.0, 1.0]) { v, p in v.offset(y: -5 * p).opacity(0.5 + 0.5 * p) }
                    animation: { _ in .easeInOut(duration: 0.4).delay(Double(i) * 0.14) }
            }
        }
    }
}

struct PlayerAvatar: View {
    @EnvironmentObject var store: Store
    let who: Who
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [store.color(who), store.color(who).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(store.name(who).prefix(1)).uppercased())
                .font(.system(size: size * 0.44, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Верхняя плашка партии: кто ходит, подсвечивается и «дышит».
struct TurnBanner: View {
    @EnvironmentObject var store: Store
    let turn: Who?
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            side(.me)
            Text(text).font(.headline).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .id(text).transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            side(.partner)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glass(Capsule(), tint: store.glassTint)
        .animation(Motion.spring, value: text)
        .animation(Motion.spring, value: turn)
    }

    private func side(_ w: Who) -> some View {
        let on = turn == w
        return PlayerAvatar(who: w, size: 38)
            .scaleEffect(on ? 1.1 : 0.88)
            .opacity(on ? 1 : 0.45)
            .background { if on { PulseRing(color: store.color(w)).padding(-2) } }
    }
}

struct BoardPanel: ViewModifier {
    @EnvironmentObject var store: Store
    func body(content: Content) -> some View {
        content
            .padding(14)
            .glass(RoundedRectangle(cornerRadius: Theme.r(30), style: .continuous), tint: store.glassTint)
            .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }
}

extension View {
    func boardPanel() -> some View { modifier(BoardPanel()) }
}

// MARK: - Крестик и нолик, которые рисуются на глазах

struct XShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

struct DrawnMark: View {
    let isX: Bool
    let color: Color
    @State private var t: CGFloat = 0
    var body: some View {
        let style = StrokeStyle(lineWidth: 9, lineCap: .round)
        return Group {
            if isX { XShape().trim(from: 0, to: t).stroke(color, style: style) }
            else { Circle().trim(from: 0, to: t).rotation(.degrees(-90)).stroke(color, style: style) }
        }
        .shadow(color: color.opacity(0.45), radius: 6)
        .padding(28)
        .onAppear { withAnimation(.easeOut(duration: 0.38)) { t = 1 } }
    }
}

// MARK: - Фишка реверси: переворачивается

struct FlipDisc: View {
    @EnvironmentObject var store: Store
    let owner: Int
    let isLast: Bool
    @State private var shown: Int
    @State private var sx: CGFloat = 1
    @State private var pop: CGFloat = 1

    init(owner: Int, isLast: Bool) {
        self.owner = owner; self.isLast = isLast
        _shown = State(initialValue: owner)
    }

    var body: some View {
        ZStack {
            if shown != 0 {
                let c = store.color(shown == 1 ? .me : .partner)
                Circle().fill(RadialGradient(colors: [c.opacity(0.7), c], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 22))
                    .overlay(Circle().stroke(.white.opacity(isLast ? 0.95 : 0.25), lineWidth: isLast ? 2.5 : 1))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
                    .padding(4)
                    .scaleEffect(x: sx, y: 1)
                    .scaleEffect(pop)
            }
        }
        .onChange(of: owner) { old, new in
            if old != 0, new != 0, old != new {
                withAnimation(.easeIn(duration: 0.14)) { sx = 0.02 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    shown = new
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { sx = 1 }
                }
            } else {
                shown = new
                if new != 0 {
                    pop = 0.2
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { pop = 1 }
                }
            }
        }
    }
}

// MARK: - Фишка «4 в ряд»: падает и подпрыгивает

struct DropDisc: View {
    @EnvironmentObject var store: Store
    let owner: Int
    let row: Int
    let win: Bool
    @State private var dy: CGFloat = 0
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle().fill(Pal.bg.opacity(0.9)).overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 1))
            if owner != 0 {
                let c = store.color(owner == 1 ? .me : .partner)
                Circle().fill(RadialGradient(colors: [c.opacity(0.7), c], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 24))
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    .overlay(Circle().stroke(Color.white, lineWidth: win ? 3 : 0).opacity(glow ? 1 : 0.35))
                    .shadow(color: c.opacity(win ? 0.8 : 0.3), radius: win ? 8 : 3, y: 2)
                    .padding(2)
                    .offset(y: dy)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: owner) { old, new in
            guard old == 0, new != 0 else { return }
            dy = -CGFloat(row + 1) * 52 - 24
            withAnimation(.interpolatingSpring(stiffness: 170, damping: 10)) { dy = 0 }
        }
        .onChange(of: win) { _, w in
            if w { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { glow = true } }
        }
    }
}
