import SwiftUI
import UIKit

// MARK: - «Банка дня»: жидкость из настроений
// Каждое настроение — слой жидкости своего цвета. Новое настроение падает каплей через приподнятую крышку,
// поверхность расходится волнами, поднимаются пузырьки, над жидкостью мерцают светлячки.
// Банку можно качнуть пальцем — жидкость наклоняется и пружинит обратно.

final class LiquidSim {
    struct Particle { var x: Double; var y: Double; var vx: Double; var vy: Double; var life: Double; var color: Color }
    struct Bubble { var x: Double; var y: Double; var speed: Double; var size: Double; var phase: Double }

    var colors: [Color] = []
    var level = 0.0
    var target = 0.0
    var amp = 0.0
    var tilt = 0.0
    var tiltV = 0.0
    var tiltTarget = 0.0
    var last: Double = 0
    var dropT: Double?
    var dropColor: Color = .white
    var pending: [Color] = []
    var particles: [Particle] = []
    var bubbles: [Bubble] = []
    var primed = false
    var impact = false
    var surfaceY: Double = 0
    var jarMidX: Double = 0

    func configure(colors new: [Color], animate: Bool) {
        let old = colors.count
        colors = new
        if !primed || !animate {
            primed = true
            level = Double(new.count); target = level
            pending = []; dropT = nil
            return
        }
        if new.count > old {
            let fresh = Array(new[old...])
            pending.append(contentsOf: fresh)
        } else if new.count < old {
            target = Double(new.count)
            if level > target { level = target }
            pending = []
        }
    }

    func step(_ now: Double, jar: CGRect, bottom: Double, usable: Double, cap: Double) {
        var dt = last == 0 ? 0.016 : now - last
        last = now
        dt = min(dt, 0.05)

        level += (target - level) * min(1, dt * 2.6)
        amp *= exp(-dt * 1.7)

        let k = 46.0, c = 7.0
        tiltV += (-(tilt - tiltTarget) * k - tiltV * c) * dt
        tilt += tiltV * dt

        surfaceY = bottom - level / cap * usable
        jarMidX = Double(jar.midX)

        if dropT == nil, !pending.isEmpty {
            dropColor = pending.removeFirst()
            dropT = 0
        }
        if var t = dropT {
            t += dt
            if t >= 0.95 {
                dropT = nil
                target += 1
                amp += 7
                impact = true
                for _ in 0..<12 {
                    particles.append(Particle(x: jarMidX + Double.random(in: -6...6), y: surfaceY,
                                              vx: Double.random(in: -70...70), vy: -Double.random(in: 90...220),
                                              life: 1, color: dropColor))
                }
            } else { dropT = t }
        }

        for i in particles.indices {
            particles[i].vy += 520 * dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].life -= dt * 1.4
        }
        particles.removeAll { $0.life <= 0 || $0.y > surfaceY + 4 }

        if level > 0.4, Double.random(in: 0...1) < dt * 3.2 {
            bubbles.append(Bubble(x: Double.random(in: 0.14...0.86), y: 0, speed: Double.random(in: 0.12...0.3),
                                  size: Double.random(in: 2...5.5), phase: Double.random(in: 0...6)))
        }
        for i in bubbles.indices { bubbles[i].y += bubbles[i].speed * dt }
        bubbles.removeAll { $0.y >= 1 }
    }
}

struct LiquidJar: View {
    let entries: [JarBall]
    @State private var sim = LiquidSim()
    @State private var dragging = false

    private var colors: [Color] {
        entries.map { Color(hex: jarMoods[min(max($0.mood, 0), jarMoods.count - 1)].hex) }
    }

    private func jarPath(_ r: CGRect) -> Path {
        let w = r.width, h = r.height
        let neck = w * 0.60, nx = r.midX - neck / 2
        let top = r.minY, shoulderY = r.minY + h * 0.15, bodyTop = r.minY + h * 0.30, rad = w * 0.24
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

    private func wave(x0: CGFloat, x1: CGFloat, top: CGFloat, bottom: CGFloat, amp: CGFloat, phase: Double, t: Double, tilt: CGFloat, mid: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: bottom))
        var x = x0
        while x <= x1 {
            let s = sin(Double(x) * 0.045 + t * 1.7 + phase)
            let y = top + amp * CGFloat(s) + tilt * (x - mid) * 0.35
            p.addLine(to: CGPoint(x: x, y: y))
            x += 5
        }
        p.addLine(to: CGPoint(x: x1, y: bottom))
        p.closeSubpath()
        return p
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(&ctx, size, tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(height: 440)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in sim.tiltTarget = Double(max(-1, min(1, v.translation.width / 110))) * 0.7 }
                .onEnded { _ in sim.tiltTarget = 0 }
        )
        .onAppear { sim.configure(colors: colors, animate: false) }
        .onChange(of: entries.map { $0.id }) { _, _ in sim.configure(colors: colors, animate: true) }
        .accessibilityLabel("Банка настроения")
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = min(size.width * 0.74, 300)
        let jar = CGRect(x: (size.width - w) / 2, y: 70, width: w, height: size.height - 70 - 26)
        let bottom = Double(jar.maxY) - 7
        let usable = Double(jar.height) * 0.70 - 7
        let cap = Double(max(10, sim.colors.count))
        sim.step(t, jar: jar, bottom: bottom, usable: usable, cap: cap)
        if sim.impact { sim.impact = false; UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8) }

        let outer = jarPath(jar)
        let inner = jarPath(jar.insetBy(dx: 5, dy: 5))

        // Тень на полу
        var floor = ctx
        floor.addFilter(.blur(radius: 10))
        floor.fill(Path(ellipseIn: CGRect(x: jar.minX + 10, y: jar.maxY - 6, width: jar.width - 20, height: 22)), with: .color(.black.opacity(0.16)))

        // Стекло: задняя стенка
        ctx.fill(outer, with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.05)]),
                                              startPoint: CGPoint(x: jar.minX, y: jar.minY), endPoint: CGPoint(x: jar.maxX, y: jar.maxY)))

        // Жидкость
        var liquid = ctx
        liquid.clip(to: inner)
        let n = sim.colors.count
        let topIndex = Int(ceil(sim.level)) - 1
        let tilt = CGFloat(sim.tilt)
        if n > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                if sim.level <= Double(i) + 0.001 { continue }
                let f = min(sim.level, Double(i + 1)) / cap
                let top = CGFloat(bottom - f * usable)
                let a = CGFloat(1.4 + sim.amp * (i == topIndex ? 1 : 0.35))
                let path = wave(x0: jar.minX, x1: jar.maxX, top: top, bottom: CGFloat(bottom) + 8, amp: a, phase: Double(i) * 1.3, t: t, tilt: tilt, mid: jar.midX)
                let c = sim.colors[i]
                liquid.fill(path, with: .linearGradient(Gradient(colors: [c.opacity(0.95), c.opacity(0.78)]),
                                                        startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: CGFloat(bottom))))
                if i == topIndex {
                    // блик на поверхности
                    var line = Path()
                    var x = jar.minX
                    while x <= jar.maxX {
                        let s = sin(Double(x) * 0.045 + t * 1.7 + Double(i) * 1.3)
                        let y = top + a * CGFloat(s) + tilt * (x - jar.midX) * 0.35
                        if x == jar.minX { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
                        x += 5
                    }
                    liquid.stroke(line, with: .color(.white.opacity(0.6)), lineWidth: 1.6)
                }
            }
            // объём: тёмный низ и свет сверху
            liquid.fill(Path(jar), with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.18)]),
                                                         startPoint: CGPoint(x: 0, y: CGFloat(bottom - usable)), endPoint: CGPoint(x: 0, y: CGFloat(bottom))))
            // пузырьки
            let liqH = sim.level / cap * usable
            for b in sim.bubbles {
                let bx = jar.minX + jar.width * CGFloat(0.12 + 0.76 * b.x) + CGFloat(sin(t * 2 + b.phase)) * 3
                let by = CGFloat(bottom - b.y * liqH)
                let r = CGFloat(b.size)
                liquid.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.32)))
                liquid.stroke(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.55)), lineWidth: 0.8)
            }
        }

        // Светлячки над жидкостью
        let glow = sim.colors.last ?? Color.white
        var sparks = ctx
        sparks.clip(to: inner)
        for i in 0..<14 {
            let seed = Double(i) * 12.9898
            let fx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let fy = (sin(seed * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1)
            let x = jar.minX + jar.width * CGFloat(0.15 + 0.7 * abs(fx)) + CGFloat(sin(t * 0.5 + seed)) * 14
            let ySpan = max(30, CGFloat(sim.surfaceY) - jar.minY - jar.height * 0.22)
            let y = jar.minY + jar.height * 0.2 + ySpan * CGFloat(abs(fy)) * 0.9 + CGFloat(cos(t * 0.4 + seed * 1.3)) * 12
            if y > CGFloat(sim.surfaceY) - 6 { continue }
            let a = max(0, sin(t * 1.3 + seed * 2)) * 0.9 + 0.1
            var g = sparks
            g.addFilter(.blur(radius: 4))
            g.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(glow.opacity(0.7 * a)))
            sparks.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .color(.white.opacity(0.9 * a)))
        }

        // Брызги
        for p in sim.particles {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(p.color.opacity(max(0, p.life))))
        }

        // Стекло: блики и контур
        ctx.fill(outer, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .clear, .white.opacity(0.06)]),
                                              startPoint: CGPoint(x: jar.minX, y: jar.minY), endPoint: CGPoint(x: jar.maxX, y: jar.maxY)))
        ctx.stroke(outer, with: .linearGradient(Gradient(colors: [.white.opacity(0.95), .white.opacity(0.25), .white.opacity(0.7)]),
                                                startPoint: CGPoint(x: jar.minX, y: jar.minY), endPoint: CGPoint(x: jar.maxX, y: jar.maxY)), lineWidth: 2.6)
        var shine = ctx
        shine.addFilter(.blur(radius: 2.5))
        let sx = jar.minX + 16
        shine.fill(Path(roundedRect: CGRect(x: sx, y: jar.minY + jar.height * 0.34, width: 9, height: jar.height * 0.42), cornerRadius: 5), with: .color(.white.opacity(0.42)))
        shine.fill(Path(roundedRect: CGRect(x: jar.maxX - 18, y: jar.minY + jar.height * 0.40, width: 4, height: jar.height * 0.14), cornerRadius: 2), with: .color(.white.opacity(0.3)))
        // бегущий блик
        let sweep = CGFloat((sin(t * 0.6) + 1) / 2)
        var sw = ctx
        sw.clip(to: outer)
        sw.addFilter(.blur(radius: 14))
        sw.fill(Path(ellipseIn: CGRect(x: jar.minX + sweep * (jar.width - 40) - 10, y: jar.minY + jar.height * 0.35, width: 40, height: jar.height * 0.55)), with: .color(.white.opacity(0.10)))

        // Капля и крышка
        var lift: CGFloat = 0
        var tilt2: Double = 0
        if let dt = sim.dropT {
            let k = dt / 0.95
            let open = max(0, min(1, (k - 0.04) / 0.55))
            lift = CGFloat(sin(open * .pi)) * 26
            tilt2 = sin(open * .pi) * -14
            let y0 = Double(jar.minY) - 52
            let y1 = sim.surfaceY
            let y = y0 + (y1 - y0) * k * k
            let r: CGFloat = 8.5
            var g = ctx
            g.addFilter(.blur(radius: 8))
            g.fill(Path(ellipseIn: CGRect(x: sim.jarMidX - 14, y: y - 14, width: 28, height: 28)), with: .color(sim.dropColor.opacity(0.55)))
            ctx.fill(Path(ellipseIn: CGRect(x: sim.jarMidX - Double(r), y: y - Double(r) * 1.25, width: Double(r) * 2, height: Double(r) * 2.5)), with: .color(sim.dropColor))
            ctx.fill(Path(ellipseIn: CGRect(x: sim.jarMidX - 4, y: y - Double(r), width: 4, height: 6)), with: .color(.white.opacity(0.7)))
        }
        let neck = jar.width * 0.60
        let lidRect = CGRect(x: jar.midX - neck / 2 - 9, y: jar.minY - 22, width: neck + 18, height: 30)
        var lid = ctx
        lid.translateBy(x: lidRect.midX, y: lidRect.midY)
        lid.rotate(by: .degrees(tilt2))
        lid.translateBy(x: -lidRect.midX + (tilt2 == 0 ? 0 : 12), y: -lidRect.midY - lift)
        let lidPath = Path(roundedRect: lidRect, cornerRadius: 9)
        lid.fill(lidPath, with: .linearGradient(Gradient(stops: [
            .init(color: Color(white: 0.52), location: 0), .init(color: Color(white: 0.93), location: 0.3),
            .init(color: .white, location: 0.5), .init(color: Color(white: 0.62), location: 1)]),
            startPoint: CGPoint(x: lidRect.minX, y: 0), endPoint: CGPoint(x: lidRect.maxX, y: 0)))
        lid.stroke(lidPath, with: .color(.white.opacity(0.8)), lineWidth: 1)
        for gx in stride(from: lidRect.minX + 14, to: lidRect.maxX - 8, by: 9) {
            lid.stroke(Path { p in p.move(to: CGPoint(x: gx, y: lidRect.minY + 6)); p.addLine(to: CGPoint(x: gx, y: lidRect.maxY - 6)) },
                       with: .color(.black.opacity(0.10)), lineWidth: 1)
        }
    }
}
