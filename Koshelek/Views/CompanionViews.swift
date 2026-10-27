import SwiftUI
import AVFoundation

// MARK: - Звуки

enum CompanionSound {
    private static var cache: [String: AVAudioPlayer] = [:]
    private static var ready = false

    static func play(_ name: String) {
        guard Appearance.shared.sounds else { return }
        if !ready {
            ready = true
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        }
        if cache[name] == nil, let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            cache[name] = try? AVAudioPlayer(contentsOf: url)
            cache[name]?.prepareToPlay()
        }
        guard let p = cache[name] else { return }
        p.currentTime = 0
        p.play()
    }
    /// Звук питомца при записи операции.
    static func tx() { play(CompanionCatalog.def(CompanionEngine.petID).soundTx) }
    /// Звук питомца при получении опыта, уровня, угощения.
    static func xp() { play(CompanionCatalog.def(CompanionEngine.petID).soundXp) }
}

// MARK: - Движение (та же математика, что на Android)

struct PetPose {
    var rot = 0.0, dy = 0.0, sx = 1.0, sy = 1.0
}

enum PetMotion {
    static func pose(_ m: CompanionMotionSpec, mood: CompanionMood, t: Double) -> PetPose {
        let tau = 2 * Double.pi
        var amp = 1.0
        switch mood {
        case .happy: amp = 1.0
        case .calm: amp = 0.55
        case .sad: amp = 0.12
        case .sleepy: amp = 0
        }
        if m.period > 0 && mood != .sleepy {
            let ph = (t.truncatingRemainder(dividingBy: m.period)) / m.period
            let a = ph < m.duty ? sin(Double.pi * ph / m.duty) : 0
            amp *= a
        }
        var p = PetPose()
        p.rot = m.rot * amp * sin(tau * m.rotHz * t)
        p.dy = -m.bob * amp * abs(sin(tau * m.bobHz * t))
        let sq = m.squash * amp * sin(tau * m.squashHz * t)
        p.sx = 1 - sq
        p.sy = 1 + sq
        switch mood {
        case .happy:
            p.dy -= 0.03 * abs(sin(tau * 1.1 * t))
        case .sad:
            p.sy *= 0.97
            p.dy += 0.01
        case .sleepy:
            let br = 0.015 * sin(tau * 0.25 * t)
            p.sx = 1 - br
            p.sy = 1 + br
            p.rot = 3
        case .calm:
            break
        }
        return p
    }
}

// MARK: - Питомец

struct PetView: View {
    let pet: CompanionDef
    var mood: CompanionMood = .calm
    var animated: Bool = true

    var body: some View {
        let live = animated && Motion.moves
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !live)) { tl in
            let t = live ? tl.date.timeIntervalSinceReferenceDate : 0.3
            let pose = live ? PetMotion.pose(pet.motion, mood: mood, t: t) : PetPose()
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    Image(pet.asset)
                        .resizable().scaledToFit()
                        .frame(width: s, height: s)
                        .scaleEffect(x: pose.sx, y: pose.sy, anchor: .bottom)
                        .rotationEffect(.degrees(pose.rot), anchor: .bottom)
                        .offset(y: s * pose.dy)
                    overlays(s: s, t: t)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityLabel(Text("\(pet.name), \(mood.title.lowercased())"))
    }

    @ViewBuilder private func overlays(s: CGFloat, t: Double) -> some View {
        let tau = 2 * Double.pi
        ZStack {
            if mood == .happy {
                ForEach(0..<2, id: \.self) { k in
                    let a = 0.5 + 0.5 * sin(tau * 0.8 * t + Double(k) * 2.1)
                    Text("✦").font(.system(size: s * (0.12 + 0.05 * a)))
                        .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.2))
                        .opacity(0.4 + 0.6 * a)
                        .position(x: s * (k == 0 ? 0.84 : 0.14), y: s * (k == 0 ? 0.18 : 0.3))
                }
            }
            if mood == .sad {
                let f = (t * 0.5).truncatingRemainder(dividingBy: 1)
                Capsule().fill(Color(red: 0.35, green: 0.62, blue: 0.95))
                    .frame(width: s * 0.05, height: s * 0.08)
                    .opacity(1 - f)
                    .position(x: s * 0.72, y: s * (0.25 + 0.2 * f))
            }
            if mood == .sleepy {
                ForEach(0..<3, id: \.self) { k in
                    let f = (t * 0.4 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z").font(.system(size: s * (0.1 + 0.08 * f), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .opacity(1 - f)
                        .position(x: s * (0.72 + 0.1 * f), y: s * (0.3 - 0.25 * f))
                }
            }
            if pet.motion.juggle && mood != .sleepy {
                ForEach(0..<3, id: \.self) { k in
                    let a = tau * (t * 0.9 + Double(k) / 3)
                    Circle().fill(Color(red: 1, green: 0.8, blue: 0.2))
                        .overlay(Circle().stroke(Color(red: 0.8, green: 0.55, blue: 0.1), lineWidth: 1))
                        .frame(width: s * 0.08, height: s * 0.08)
                        .position(x: s * (0.5 + 0.28 * cos(a)), y: s * (0.1 + 0.08 * sin(a)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Блок на главной

struct CompanionBlock: View {
    @EnvironmentObject var router: Router
    let txs: [Tx]
    @AppStorage("budget") private var budget: Double = 0
    @AppStorage("pet.id") private var petID: String = CompanionCatalog.defaultID
    @AppStorage("pet.fed") private var fed: Int = 0
    @AppStorage("pet.fedDay") private var fedDay: Int = -1
    @State private var chat = false
    @State private var picker = false
    @State private var said: String? = nil

    private var pet: CompanionDef { CompanionCatalog.def(petID) }

    var body: some View {
        let ops = txs.filter { $0.kind != .tr }.map {
            CompanionOp(date: $0.date, isExpense: $0.kind == .exp, cat: $0.cat, amount: $0.amount, counts: countsInTotals($0))
        }
        let st = CompanionEngine.compute(ops: ops, budget: budget, pet: pet, fed: fed, fedDay: fedDay)
        return VStack(alignment: .leading, spacing: 8) {
            BlockHeader(title: "Напарник", action: "Сменить") { picker = true }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    PetView(pet: pet, mood: st.mood)
                        .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(pet.name) · \(st.mood.title)").font(.headline)
                        Text(said ?? st.phrase).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 6) {
                    HStack {
                        Text("Уровень \(st.level)").font(.footnote.weight(.semibold))
                        Spacer()
                        Text("\(st.xpInLevel)/\(st.xpNeed) XP").font(.footnote).foregroundStyle(.secondary)
                    }
                    Bar(value: st.progress, color: Color(hex: pet.accentHex), height: 6)
                }
                HStack(spacing: 10) {
                    Button { feed(st) } label: {
                        Text("Угостить (\(st.treats))").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(st.treats > 0 ? Theme.accent : Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(st.treats > 0 ? Theme.onAccent : Color.secondary)
                    }
                    .buttonStyle(.plain).disabled(st.treats == 0)
                    Button { Haptic.tap(); chat = true } label: {
                        Text("Поговорить").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .onChange(of: st.level) { old, new in
            if old > 0 && new > old { CompanionSound.xp(); Haptic.success() }
        }
        .sheet(isPresented: $chat) { AdvisorChat(pet: pet, mood: st.mood) }
        .sheet(isPresented: $picker) {
            NavigationStack {
                PetPickerView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { picker = false } } }
            }
        }
    }

    private func feed(_ st: CompanionState) {
        guard CompanionEngine.feed(state: st) else { return }
        Haptic.success()
        CompanionSound.xp()
        said = pet.feedLine
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            said = nil
        }
    }
}

// MARK: - Выбор напарника

struct PetPickerView: View {
    @AppStorage("pet.id") private var petID: String = CompanionCatalog.defaultID

    private var current: CompanionDef { CompanionCatalog.def(petID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    PetView(pet: current, mood: .happy).frame(width: 150, height: 150)
                    Text(current.name).font(.title3.weight(.semibold))
                    Text(current.role).font(.subheadline).foregroundStyle(.secondary)
                    Text(current.blurb).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Звук: \(current.sound)").font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    Button { CompanionSound.play(current.soundTx) } label: {
                        Label("Послушать", systemImage: "speaker.wave.2.fill").font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).padding(.top, 2)
                }
                .padding(.horizontal, 12)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(CompanionCatalog.all) { p in
                        Button { Haptic.select(); petID = p.id } label: {
                            VStack(spacing: 4) {
                                PetView(pet: p, mood: .calm, animated: false).frame(height: 72)
                                Text(p.name).font(.footnote.weight(.semibold)).lineLimit(1)
                            }
                            .padding(8).frame(maxWidth: .infinity)
                            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(p.id == petID ? Theme.accent : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Напарник")
        .navigationBarTitleDisplayMode(.inline)
    }
}
