import SwiftUI
import SpriteKit
import CoreMotion

// MARK: - Физическая банка (SpriteKit)

final class JarScene: SKScene {
    var onTapBall: ((UUID) -> Void)?
    var ownerColor: (Who) -> UIColor = { _ in .white }
    private var nodes: [UUID: SKNode] = [:]
    private var pending: [JarBall] = []
    private var firstSync = true
    private let motion = CMMotionManager()
    private let radius: CGFloat = 19

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        physicsWorld.gravity = CGVector(dx: 0, dy: -7)
        buildWalls()
        startMotion()
        sync(pending)
    }

    override func willMove(from view: SKView) { motion.stopAccelerometerUpdates() }

    override func didChangeSize(_ oldSize: CGSize) {
        if view != nil { buildWalls() }
    }

    private func buildWalls() {
        let w = size.width, h = size.height
        guard w > 60, h > 60 else { return }
        let inset: CGFloat = 8, corner: CGFloat = min(46, w / 5)
        let p = UIBezierPath()
        p.move(to: CGPoint(x: inset, y: h + 400))
        p.addLine(to: CGPoint(x: inset, y: inset + corner))
        p.addQuadCurve(to: CGPoint(x: inset + corner, y: inset), controlPoint: CGPoint(x: inset, y: inset))
        p.addLine(to: CGPoint(x: w - inset - corner, y: inset))
        p.addQuadCurve(to: CGPoint(x: w - inset, y: inset + corner), controlPoint: CGPoint(x: w - inset, y: inset))
        p.addLine(to: CGPoint(x: w - inset, y: h + 400))
        let body = SKPhysicsBody(edgeChainFrom: p.cgPath)
        body.friction = 0.25
        body.restitution = 0.3
        physicsBody = body
    }

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1 / 30
        motion.startAccelerometerUpdates(to: .main) { [weak self] d, _ in
            guard let a = d?.acceleration else { return }
            // Планшет лежит ровно — оставляем обычную силу тяжести вниз.
            let flat = abs(a.z) > 0.92
            self?.physicsWorld.gravity = flat ? CGVector(dx: 0, dy: -7) : CGVector(dx: a.x * 11, dy: a.y * 11)
        }
    }

    private func makeBall(_ b: JarBall) -> SKNode {
        let m = jarMoods[min(max(b.mood, 0), jarMoods.count - 1)]
        let n = SKShapeNode(circleOfRadius: radius)
        n.fillColor = UIColor(Color(hex: m.hex))
        n.strokeColor = ownerColor(b.who)
        n.lineWidth = 3
        n.name = b.id.uuidString
        let shine = SKShapeNode(circleOfRadius: radius * 0.3)
        shine.fillColor = UIColor.white.withAlphaComponent(0.55)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -radius * 0.38, y: radius * 0.38)
        n.addChild(shine)
        let l = SKLabelNode(text: m.emoji)
        l.fontSize = radius * 1.05
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        l.position = CGPoint(x: 0, y: -1)
        n.addChild(l)
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.restitution = 0.45
        body.friction = 0.2
        body.linearDamping = 0.15
        body.angularDamping = 0.5
        n.physicsBody = body
        return n
    }

    func sync(_ balls: [JarBall]) {
        pending = balls
        guard view != nil, size.width > 60 else { return }
        let list = Array(balls.sorted { $0.date < $1.date }.suffix(70))
        let ids = Set(list.map(\.id))
        for (id, node) in nodes where !ids.contains(id) {
            node.run(.sequence([.scale(to: 0, duration: 0.2), .removeFromParent()]))
            nodes[id] = nil
        }
        var delay = 0.0
        for b in list where nodes[b.id] == nil {
            let node = makeBall(b)
            node.position = CGPoint(x: CGFloat.random(in: 40...(size.width - 40)), y: size.height + radius * 2)
            node.alpha = 0
            addChild(node)
            nodes[b.id] = node
            node.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.01)]))
            node.physicsBody?.isDynamic = false
            node.run(.sequence([.wait(forDuration: delay), .run { node.physicsBody?.isDynamic = true }]))
            delay += firstSync ? 0.04 : 0.0
        }
        firstSync = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let hit = nodes(at: p).first { $0.name != nil } ?? nodes(at: p).first?.parent
        if let name = hit?.name, let id = UUID(uuidString: name) {
            onTapBall?(id)
            hit?.physicsBody?.applyImpulse(CGVector(dx: CGFloat.random(in: -6...6), dy: 14))
        } else {
            for n in nodes.values { n.physicsBody?.applyImpulse(CGVector(dx: CGFloat.random(in: -4...4), dy: 9)) }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

final class JarModel: ObservableObject {
    let scene = JarScene()
    init() { scene.scaleMode = .resizeFill }
}

// MARK: - Экран банки

struct JarView: View {
    @EnvironmentObject var store: Store
    @StateObject private var model = JarModel()
    @State private var note = ""
    @State private var selected: JarBall?

    private var today: [JarBall] { store.data.jar.filter { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                jar
                caption
                picker
                stats
                history
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Банка настроения")
        .onAppear {
            model.scene.ownerColor = { [store] w in UIColor(store.color(w)) }
            model.scene.onTapBall = { id in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = store.data.jar.first { $0.id == id } }
            }
            model.scene.sync(store.data.jar)
        }
        .onChange(of: store.data.jar) { _, new in model.scene.sync(new) }
    }

    private var jar: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 56, style: .continuous))
            SpriteView(scene: model.scene, options: [.allowsTransparency])
                .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15), .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
            Capsule().fill(.white.opacity(0.45)).frame(width: 12, height: 150)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 26).padding(.top, 60)
            if store.data.jar.isEmpty {
                Text("Банка пуста — бросьте первый шарик").font(.footnote).foregroundStyle(.secondary).padding(.top, 150)
            }
        }
        .frame(height: 380)
        .shadow(color: Theme.accent.opacity(0.25), radius: 20, y: 12)
        .overlay(alignment: .bottom) {
            Text("Наклоняйте телефон или касайтесь шариков").font(.caption2).foregroundStyle(.secondary).offset(y: 22)
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder private var caption: some View {
        if let s = selected {
            let m = jarMoods[min(max(s.mood, 0), jarMoods.count - 1)]
            HStack(spacing: 12) {
                Text(m.emoji).font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.name(s.who)) · \(m.title)").font(.subheadline.weight(.bold))
                    Text(s.note.isEmpty ? s.date.agoText : s.note + " · " + s.date.agoText).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12).card().transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Как вы сейчас?").font(.headline)
            HStack(spacing: 8) {
                ForEach(jarMoods) { m in
                    Button {
                        store.addBall(mood: m.id, note: note)
                        note = ""
                    } label: {
                        VStack(spacing: 4) {
                            Text(m.emoji).font(.system(size: 30))
                            Text(m.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(hex: m.hex).opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Пара слов (по желанию)", text: $note)
                .padding(12).background(Pal.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14).card()
    }

    private var stats: some View {
        HStack(spacing: 8) {
            ForEach(jarMoods) { m in
                let n = today.filter { $0.mood == m.id }.count
                VStack(spacing: 2) {
                    Text(m.emoji).font(.title3)
                    Text("\(n)").font(.subheadline.weight(.heavy).monospacedDigit())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Color(hex: m.hex).opacity(n > 0 ? 0.22 : 0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .overlay(alignment: .topLeading) { Text("Сегодня").font(.caption2).foregroundStyle(.secondary).offset(y: -16) }
        .padding(.top, 8)
    }

    private var history: some View {
        VStack(spacing: 8) {
            ForEach(store.data.jar.sorted { $0.date > $1.date }.prefix(12)) { b in
                let m = jarMoods[min(max(b.mood, 0), jarMoods.count - 1)]
                HStack(spacing: 12) {
                    Text(m.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.name(b.who)) — \(m.title)").font(.subheadline.weight(.semibold))
                        if !b.note.isEmpty { Text(b.note).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(b.date.agoText).font(.caption).foregroundStyle(.secondary)
                }
                .padding(12).card()
            }
        }
    }
}
