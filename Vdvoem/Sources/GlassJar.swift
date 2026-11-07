import SwiftUI

// MARK: - Стеклянная банка со светящимися шарами настроения

struct JarShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let neck = w * 0.58, nx = r.midX - neck / 2
        let top = r.minY, shoulderY = r.minY + h * 0.14, bodyTop = r.minY + h * 0.28, rad = w * 0.22
        var p = Path()
        p.move(to: CGPoint(x: nx, y: top))
        p.addLine(to: CGPoint(x: nx + neck, y: top))
        p.addLine(to: CGPoint(x: nx + neck, y: shoulderY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: bodyTop), control: CGPoint(x: r.maxX, y: shoulderY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: bodyTop))
        p.addQuadCurve(to: CGPoint(x: nx, y: shoulderY), control: CGPoint(x: r.minX, y: shoulderY))
        p.closeSubpath()
        return p
    }
}

/// Один светящийся шар: объём, внутреннее свечение, два блика и кольцо цвета автора.
struct MoodMarble: View {
    let color: Color
    let ring: Color
    let d: CGFloat

    var body: some View {
        ZStack {
            // тело: глубокий цвет по краям, светлая сердцевина
            Circle().fill(RadialGradient(colors: [color.opacity(0.35), color, color.opacity(0.78)],
                                         center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: d * 0.78))
            // преломление света на нижнем крае
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.0), Color.white.opacity(0.28)],
                                         center: UnitPoint(x: 0.5, y: 0.5), startRadius: d * 0.3, endRadius: d * 0.62))
                .mask(Circle().fill(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)))
            Ellipse().fill(Color.white.opacity(0.75)).frame(width: d * 0.34, height: d * 0.17)
                .rotationEffect(.degrees(-32)).offset(x: -d * 0.19, y: -d * 0.25).blur(radius: 0.6)
            Circle().fill(Color.white.opacity(0.55)).frame(width: d * 0.08).offset(x: d * 0.2, y: d * 0.22)
            Circle().stroke(LinearGradient(colors: [ring, ring.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 1.6)
        }
        .frame(width: d, height: d)
        .shadow(color: color.opacity(0.55), radius: 7, y: 2)
    }
}

/// Пробка из дерева с кольцами, сидит в горлышке.
private struct JarLid: View {
    let w: CGFloat
    let a: Color, b: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [a, b], startPoint: .leading, endPoint: .trailing))
            // кольцо-обод и блик
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
            VStack(spacing: 3) {
                Capsule().fill(Color.white.opacity(0.28)).frame(height: 2)
                Spacer(minLength: 0)
                Capsule().fill(Color.black.opacity(0.14)).frame(height: 2)
            }.padding(.vertical, 4).padding(.horizontal, 6)
        }
        .frame(width: w, height: 20)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

struct GlassJar: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    let balls: [JarBall]            // по времени, старые первыми
    @State private var tilt: CGFloat = 0
    @State private var dragging = false

    private let d: CGFloat = 32

    private func jitter(_ id: UUID, _ salt: Int) -> CGFloat {
        var h: UInt64 = 1469598103934665603
        for u in (id.uuidString + "\(salt)").utf8 { h = (h ^ UInt64(u)) &* 1099511628211 }
        return CGFloat(h % 1000) / 1000 - 0.5
    }

    private func spot(_ i: Int, _ b: JarBall, jw: CGFloat, jh: CGFloat) -> CGPoint {
        let inner = jw - 26
        let perRow = max(2, Int(inner / (d * 0.92)))
        let row = i / perRow, col = i % perRow
        let step = inner / CGFloat(perRow)
        let shift: CGFloat = row % 2 == 0 ? 0 : step / 2
        var x = 13 + step / 2 + CGFloat(col) * step + shift + jitter(b.id, 1) * 4
        x = min(max(x, 13 + d / 2), jw - 13 - d / 2)
        let y = jh - 16 - d / 2 - CGFloat(row) * d * 0.8 + jitter(b.id, 2) * 3
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { g in
            let jw = min(g.size.width * 0.74, 250)
            let jh = g.size.height - 30
            ZStack {
                // мягкая тень-«пол» и отражение света
                Ellipse().fill(RadialGradient(colors: [Color.black.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: jw * 0.5))
                    .frame(width: jw * 1.05, height: 22).offset(y: jh / 2 + 12)
                jar(jw: jw, jh: jh)
                    .rotationEffect(.degrees(Double(tilt) * 7), anchor: .bottom)
                    .animation(dragging ? .interactiveSpring(response: 0.18, dampingFraction: 0.9) : Motion.bouncy, value: tilt)
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in dragging = true; tilt = max(-1, min(1, v.translation.width / 90)) }
                    .onEnded { _ in dragging = false; tilt = 0 }
            )
        }
        .frame(height: 340)
        .accessibilityLabel("Банка настроения")
    }

    private func jar(jw: CGFloat, jh: CGFloat) -> some View {
        let shown = Array(balls.suffix(36))
        let dark = scheme == .dark
        return ZStack(alignment: .topLeading) {
            // стекло: толще у краёв, прозрачнее в центре
            JarShape().fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.12 : 0.34), Color.white.opacity(dark ? 0.03 : 0.08)], startPoint: .top, endPoint: .bottom))
            JarShape().fill(LinearGradient(stops: [
                .init(color: Color.white.opacity(dark ? 0.16 : 0.30), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.78),
                .init(color: Color.white.opacity(dark ? 0.10 : 0.22), location: 1)
            ], startPoint: .leading, endPoint: .trailing))
            // тёплое свечение изнутри от шаров
            RadialGradient(colors: [store.meColor.opacity(0.22), .clear], center: .bottom, startRadius: 0, endRadius: jw * 0.9)
                .frame(width: jw, height: jh).allowsHitTesting(false)
            LiveTimeline(fps: 20) { date in
                let t = date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, b in
                        let p = spot(i, b, jw: jw, jh: jh)
                        let bob = CGFloat(sin(t * 0.9 + Double(i) * 0.9)) * 1.4
                        let sway = CGFloat(cos(t * 0.7 + Double(i) * 1.3)) * 0.8 + tilt * CGFloat(i % 5) * 1.2
                        MoodMarble(color: Color(hex: moodOf(b.mood).hex), ring: store.color(b.who), d: d)
                            .position(x: p.x + sway, y: p.y + bob)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .scale(scale: 0.6)).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.interpolatingSpring(stiffness: 120, damping: 11), value: shown.count)
            }
            .frame(width: jw, height: jh)
            // длинный блик по левой стенке и короткий справа
            Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: jh * 0.46).offset(x: 14, y: jh * 0.30).blur(radius: 1.2)
                .allowsHitTesting(false)
            Capsule().fill(Color.white.opacity(0.35)).frame(width: 4, height: jh * 0.12)
                .offset(x: jw - 20, y: jh * 0.34).blur(radius: 1)
                .allowsHitTesting(false)
        }
        .frame(width: jw, height: jh)
        .clipShape(JarShape())
        .overlay(JarShape().stroke(LinearGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.18), Color.white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.2))
        .overlay(JarShape().inset(by: 3).stroke(Color.white.opacity(dark ? 0.08 : 0.22), lineWidth: 1))
        .overlay(alignment: .top) {
            JarLid(w: jw * 0.58 + 16, a: store.meColor, b: store.partnerColor).offset(y: -12)
        }
        .shadow(color: store.meColor.opacity(0.18), radius: 22, y: 12)
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
    }
}
