import SwiftUI

let petPalette: [(a: String, b: String)] = [
    ("FFB86B", "FF8A5B"), ("9BE7C4", "3FC9A5"), ("C4B5FD", "8C7BF2"),
    ("FFC2D9", "F472B6"), ("A5D8FF", "4C9AF0"), ("FDE68A", "F5B83D")
]

extension Store {
    var pet: PetState? { data.pets.first }

    func hatchPet(name: String) {
        guard data.pets.isEmpty else { return }
        var p = PetState()
        p.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Малыш" : name.trimmingCharacters(in: .whitespaces)
        data.pets = [p]
        success()
    }

    func updatePet(_ f: (inout PetState) -> Void) {
        guard var p = pet else { return }
        f(&p)
        data.pets = [p]
    }

    /// Опыт растёт от всего, что вы делаете вместе.
    var petXP: Int {
        data.signals.count + data.tracks.count + data.jar.count + data.messages.count / 2
            + data.photos.count * 3 + data.matches.count * 2 + data.moods.count
    }
    var petLevel: Int { Int(Double(petXP / 3).squareRoot()) + 1 }
    var petLevelProgress: Double {
        let lvl = petLevel
        let lo = (lvl - 1) * (lvl - 1) * 3, hi = lvl * lvl * 3
        return Double(petXP - lo) / Double(max(hi - lo, 1))
    }
}

enum PetMood { case happy, hungry, starving }

struct PetView: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var hearts: [UUID] = []
    @State private var jump = false

    private var mood: PetMood {
        guard let p = store.pet else { return .happy }
        let h = Date().timeIntervalSince(p.lastFed) / 3600
        return h < 8 ? .happy : (h < 18 ? .hungry : .starving)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let p = store.pet { alive(p) } else { egg }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Питомец")
    }

    private var egg: some View {
        VStack(spacing: 16) {
            Text("🥚").font(.system(size: 120)).padding(.top, 30)
                .rotationEffect(.degrees(jump ? 6 : -6))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: jump)
                .onAppear { jump = true }
            Text("Вылупите питомца").font(.title2.weight(.heavy))
            Text("Он будет расти от того, что вы делаете вместе: сообщений, сигналов, фото, игр.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            TextField("Имя питомца", text: $name)
                .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
            Button { store.hatchPet(name: name) } label: { Text("Вылупить").bigButton() }
        }
        .padding(18).card()
    }

    private func alive(_ p: PetState) -> some View {
        let pal = petPalette[min(p.colorIndex, petPalette.count - 1)]
        let scale = min(1.25, 0.9 + Double(store.petLevel) * 0.04)
        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(p.name).font(.system(size: 28, weight: .heavy, design: .rounded))
                Text("Уровень \(store.petLevel)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ProgressView(value: store.petLevelProgress).tint(Color(hex: pal.b)).frame(width: 180)
            }
            ZStack {
                Ellipse().fill(.black.opacity(0.12)).frame(width: 150, height: 22).offset(y: 120)
                PetBody(a: Color(hex: pal.a), b: Color(hex: pal.b), mood: mood)
                    .scaleEffect(scale)
                    .offset(y: jump ? -26 : 0)
                    .animation(.interpolatingSpring(stiffness: 170, damping: 9), value: jump)
                    .onTapGesture { cuddle() }
                ForEach(hearts, id: \.self) { _ in
                    Text("💗").font(.title).transition(.move(edge: .top).combined(with: .opacity)).offset(x: CGFloat.random(in: -60...60), y: -110)
                }
            }
            .frame(height: 290)

            Text(statusLine(p)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 12) {
                action("🍎", "Покормить") {
                    store.updatePet { $0.lastFed = Date(); $0.fedBy = .me }
                    store.success(); bounce()
                }
                action("🤍", "Погладить") { cuddle() }
                action("🎾", "Играть") {
                    store.updatePet { $0.lastPlayed = Date() }
                    store.tap(); bounce()
                }
            }

            HStack(spacing: 10) {
                ForEach(petPalette.indices, id: \.self) { i in
                    Circle().fill(LinearGradient(colors: [Color(hex: petPalette[i].a), Color(hex: petPalette[i].b)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.primary, lineWidth: p.colorIndex == i ? 2.5 : 0).padding(-3))
                        .onTapGesture { store.updatePet { $0.colorIndex = i }; store.tap() }
                }
            }
        }
        .padding(18).card()
    }

    private func statusLine(_ p: PetState) -> String {
        switch mood {
        case .happy: return "\(p.name) доволен. В последний раз кормил(а) \(store.name(p.fedBy)) — \(p.lastFed.agoText)."
        case .hungry: return "\(p.name) проголодался — \(p.lastFed.agoText) его никто не кормил."
        case .starving: return "\(p.name) очень голоден! Покормите его скорее."
        }
    }

    private func action(_ emoji: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Text(emoji).font(.system(size: 30))
                Text(title).font(.caption.weight(.bold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .glass(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func bounce() {
        jump = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { jump = false }
    }

    private func cuddle() {
        store.updatePet { $0.lastCuddled = Date() }
        store.tap()
        bounce()
        let id = UUID()
        withAnimation(.easeOut(duration: 0.6)) { hearts.append(id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { hearts.removeAll { $0 == id } }
    }
}

/// Нарисованный питомец: мягкий «комочек» с глазами, щёчками и ротиком.
struct PetBody: View {
    let a: Color, b: Color
    let mood: PetMood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let breathe = 1 + CGFloat(sin(t * 2)) * 0.025
            let blink = (Int(t * 10) % 40) == 0
            ZStack {
                Capsule().fill(b).frame(width: 34, height: 60).rotationEffect(.degrees(-24)).offset(x: -52, y: -108)
                Capsule().fill(b).frame(width: 34, height: 60).rotationEffect(.degrees(24)).offset(x: 52, y: -108)
                RoundedRectangle(cornerRadius: Theme.r(90), style: .continuous)
                    .fill(LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 190, height: 170)
                    .shadow(color: b.opacity(0.5), radius: 16, y: 12)
                RoundedRectangle(cornerRadius: Theme.r(40), style: .continuous).fill(.white.opacity(0.25)).frame(width: 70, height: 26).rotationEffect(.degrees(-20)).offset(x: -45, y: -52)
                HStack(spacing: 46) { eye(blink); eye(blink) }.offset(y: -12)
                HStack(spacing: 96) { Circle().fill(Color(hex: "FF8FB1").opacity(0.6)).frame(width: 24, height: 16); Circle().fill(Color(hex: "FF8FB1").opacity(0.6)).frame(width: 24, height: 16) }.offset(y: 14)
                mouth.offset(y: 22)
            }
            .scaleEffect(x: breathe, y: 2 - breathe)
        }
    }

    private func eye(_ blink: Bool) -> some View {
        ZStack {
            Ellipse().fill(.white).frame(width: 30, height: blink ? 4 : 38)
            if !blink { Circle().fill(Color(hex: "2B2440")).frame(width: 16, height: 16).offset(y: mood == .happy ? 0 : 5)
                Circle().fill(.white).frame(width: 6, height: 6).offset(x: -3, y: -4) }
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .happy:
            Path { p in p.move(to: CGPoint(x: -18, y: 0)); p.addQuadCurve(to: CGPoint(x: 18, y: 0), control: CGPoint(x: 0, y: 22)) }
                .stroke(Color(hex: "2B2440"), style: StrokeStyle(lineWidth: 5, lineCap: .round)).frame(width: 40, height: 24)
        case .hungry:
            Capsule().fill(Color(hex: "2B2440")).frame(width: 22, height: 6)
        case .starving:
            Path { p in p.move(to: CGPoint(x: -16, y: 14)); p.addQuadCurve(to: CGPoint(x: 16, y: 14), control: CGPoint(x: 0, y: -8)) }
                .stroke(Color(hex: "2B2440"), style: StrokeStyle(lineWidth: 5, lineCap: .round)).frame(width: 40, height: 24)
        }
    }
}
