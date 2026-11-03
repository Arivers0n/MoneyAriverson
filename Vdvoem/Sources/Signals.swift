import SwiftUI

// MARK: - Действия

extension Store {
    func sendSignal(_ kind: String) {
        var d = data
        d.signals.append(SignalItem(who: .me, kind: kind))
        let old = Date().addingTimeInterval(-30 * 24 * 3600)
        d.signals.removeAll { $0.date < old }
        data = d
        success()
    }

    func signalCount(_ kind: String, who: Who, today: Bool = false) -> Int {
        data.signals.filter { $0.kind == kind && $0.who == who && (!today || Calendar.current.isDateInToday($0.date)) }.count
    }

    // Батарея
    func updateBattery() {
        let dev = UIDevice.current
        dev.isBatteryMonitoringEnabled = true
        guard dev.batteryLevel >= 0 else { return }
        let level = Double(dev.batteryLevel)
        let charging = dev.batteryState == .charging || dev.batteryState == .full
        let cur = data.batteries.first { $0.who == .me }
        if let cur, abs(cur.level - level) < 0.03, cur.charging == charging, Date().timeIntervalSince(cur.updated) < 900 { return }
        var d = data
        let info = BatteryInfo(id: Who.me.rawValue, who: .me, level: level, charging: charging, updated: Date())
        if let i = d.batteries.firstIndex(where: { $0.who == .me }) { d.batteries[i] = info } else { d.batteries.append(info) }
        data = d
    }
}

// MARK: - Экран «Сигнал»

struct SignalView: View {
    @EnvironmentObject var store: Store
    @State private var pulse = false
    @State private var burst = 0

    private var missMe: Int { store.signalCount("miss", who: .me) }
    private var missThem: Int { store.signalCount("miss", who: .partner) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Скучаю по тебе").font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("\(store.name(.partner)) увидит сердечко сразу, как только откроет приложение")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 6)

                Button {
                    store.sendSignal("miss")
                    burst += 1
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { pulse = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring()) { pulse = false } }
                } label: {
                    ZStack {
                        Circle().fill(Color(hex: "FF5C8A").opacity(0.14)).frame(width: 250, height: 250)
                        Circle().fill(Color(hex: "FF5C8A").opacity(0.2)).frame(width: 205, height: 205)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 130))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: "FF9AB8"), Color(hex: "F43F5E")], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Color(hex: "F43F5E").opacity(0.5), radius: 20, y: 12)
                            .scaleEffect(pulse ? 1.18 : 1)
                        Text("\(missMe + missThem)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .contentTransition(.numericText()).offset(y: -4)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    count(.me, missMe)
                    count(.partner, missThem)
                }

                Text("Другие сигналы").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(signalKinds.dropFirst()) { k in
                        Button { store.sendSignal(k.id) } label: {
                            HStack(spacing: 10) {
                                Text(k.emoji).font(.system(size: 30))
                                Text(k.title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: k.hex).opacity(0.16), in: RoundedRectangle(cornerRadius: store.radius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: store.radius, style: .continuous).stroke(Color(hex: k.hex).opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                let recent = store.data.signals.sorted { $0.date > $1.date }.prefix(8)
                if !recent.isEmpty {
                    Text("Недавние").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(recent)) { s in
                        let k = signalKind(s.kind)
                        HStack(spacing: 12) {
                            Text(k.emoji).font(.title2)
                            Text("\(store.name(s.who)): \(k.title)").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(s.date.agoText).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12).card()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Сигнал")
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.data.signals.count)
    }

    private func count(_ w: Who, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 28, weight: .heavy, design: .rounded)).contentTransition(.numericText())
            Text("\(store.name(w)) скучает").font(.caption).foregroundStyle(store.color(w)).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).card()
    }
}

// MARK: - Всплывающая анимация при получении сигнала

struct SignalOverlay: View {
    @EnvironmentObject var store: Store
    @State private var current: SignalItem?
    @State private var shown = Set<UUID>()
    @State private var rise = false

    var body: some View {
        ZStack {
            if let s = current {
                let k = signalKind(s.kind)
                Color.black.opacity(0.35).ignoresSafeArea().transition(.opacity)
                ForEach(0..<14, id: \.self) { i in
                    Text(k.emoji).font(.system(size: CGFloat(24 + (i * 7) % 30)))
                        .offset(x: CGFloat((i * 53) % 260) - 130, y: rise ? -420 - CGFloat((i * 31) % 160) : 360)
                        .opacity(rise ? 0 : 1)
                        .animation(.easeOut(duration: 2.4).delay(Double(i) * 0.07), value: rise)
                }
                VStack(spacing: 10) {
                    Text(k.emoji).font(.system(size: 110))
                    Text(k.title).font(.title.weight(.heavy)).foregroundStyle(.white)
                    Text("от \(store.name(s.who))").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                .padding(30)
                .glass(RoundedRectangle(cornerRadius: 36, style: .continuous), tint: Color(hex: k.hex).opacity(0.5))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .allowsHitTesting(current != nil)
        .onTapGesture { dismiss() }
        .onChange(of: store.data.signals) { _, list in
            guard let s = list.filter({ $0.who == .partner }).max(by: { $0.date < $1.date }),
                  !shown.contains(s.id), Date().timeIntervalSince(s.date) < 25 else { return }
            shown.insert(s.id)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { current = s }
            rise = false
            DispatchQueue.main.async { rise = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { if current?.id == s.id { dismiss() } }
        }
    }

    private func dismiss() { withAnimation(.easeOut(duration: 0.25)) { current = nil } }
}
