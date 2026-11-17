import SwiftUI

// MARK: - 9. «Два окна»: свет — настроение, новое светится, пока не увидишь

struct TodayOkna: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    @AppStorage("seenPartnerStatus") private var seen = ""
    @Environment(\.todayPalette) private var pal
    private var muted: Color { pal.muted }
    /// Свет нового в окне — тёплый, в цвет партнёра.
    private var amber: Color { pal.dark ? HSB.mix(store.partnerColor, Color(hex: "FFC46B"), 0.35) : store.partnerColor }

    private var isNew: Bool {
        guard let s = store.statusNow(.partner) else { return false }
        return s.id.uuidString != seen
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                window(.me)
                window(.partner)
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                NavigationLink { ModuleView(module: .chat) } label: {
                    Text("Ответить").font(.body.weight(.semibold)).foregroundStyle(amber.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 48).background(amber, in: Capsule())
                }
                .buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    Text("Обнять").font(.body.weight(.semibold)).foregroundStyle(pal.partnerText)
                        .frame(maxWidth: .infinity).frame(height: 48).background(amber.opacity(pal.dark ? 0.2 : 0.13), in: Capsule())
                }
                .buttonStyle(PressStyle())
            }

            VStack(spacing: 0) {
                if let m = store.lastPartnerMessage {
                    NavigationLink { ModuleView(module: .chat) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.kind == "voice" ? "Голосовое сообщение" : m.text).font(.body).foregroundStyle(pal.ink).lineLimit(1)
                                Text("\(store.name(.partner)), \(m.date.agoText)").font(.footnote).foregroundStyle(muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 58).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    Rectangle().fill(pal.line).frame(height: 1)
                }
                ForEach(store.openTasks.prefix(2)) { t in
                    TaskCheckRow(task: t, accent: pal.partnerText, ink: pal.ink, muted: pal.faint).padding(.horizontal, 16)
                    Rectangle().fill(pal.line).frame(height: 1)
                }
                if let (e, d) = store.nextEvent {
                    NavigationLink { ModuleView(module: .calendar) } label: {
                        HStack {
                            Text(e.title).font(.body).foregroundStyle(pal.ink).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(inDaysText(d)).font(.subheadline).foregroundStyle(muted)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 50).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .background(pal.card.opacity(pal.dark ? 0.45 : 0.8), in: RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    @ViewBuilder private func window(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let mood = store.lastMood(who)
        let light = mood.map { Color(hex: moodOf($0.mood).hex) } ?? (pal.dark ? pal.deep.hsb(dB: 0.1) : pal.field)
        let glow = who == .partner && isNew
        // Рама: ночью — тёмное дерево в тон темы, днём — белая.
        let frameColor = pal.dark ? pal.deep.hsb(dB: 0.06) : pal.card
        let shape = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 10, style: .continuous)
        let content = VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RadialGradient(colors: [light.hsb(dS: -0.25, dB: 0.3), light, light.hsb(dS: 0.1, dB: -0.45)],
                               center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 170)
                frameColor.frame(width: 6)
                frameColor.frame(height: 6).offset(y: -12)
                Group {
                    if let st, let e = st.emoji, !e.isEmpty {
                        Text(e).font(.system(size: 34))
                            .frame(width: 66, height: 66).background(Color.white.opacity(0.16), in: Circle())
                    } else if let st {
                        Image(systemName: statusKind(st.kind).symbol).font(.system(size: 50, weight: .light))
                            .foregroundStyle(light.hsb(dS: 0.2, dB: -0.6))
                    } else {
                        Image(systemName: pal.dark ? "moon.zzz" : "sun.haze").font(.system(size: 40, weight: .light)).foregroundStyle(pal.faint)
                    }
                }
            }
            .frame(height: 214)
            .clipShape(shape)
            .overlay(shape.strokeBorder(frameColor, lineWidth: 7))
            .overlay(shape.strokeBorder(pal.dark ? Color.black.opacity(0.45) : pal.line, lineWidth: 2).padding(-1))
            .shadow(color: pal.shadow, radius: 10, y: 8)
            .shadow(color: glow ? amber.opacity(0.55) : .clear, radius: 18)
            .overlay(shape.stroke(amber.opacity(glow ? 0.6 : 0), lineWidth: 3).padding(-4))
            .animation(Motion.spring, value: glow)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(st?.title ?? (who == .me ? "Поставить статус" : "Свет не горит"))
                        .font(.body.weight(.semibold)).foregroundStyle(pal.ink).lineLimit(1)
                    if glow { Circle().fill(amber).frame(width: 8, height: 8).accessibilityLabel("новое") }
                }
                Text(caption(who, st: st, mood: mood)).font(.subheadline).foregroundStyle(muted).lineLimit(2)
            }
        }
        if who == .me {
            Button { showStatus = true; store.tap() } label: { content }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { content }
                .buttonStyle(PressStyle())
                .simultaneousGesture(TapGesture().onEnded { if let s = st { seen = s.id.uuidString } })
                .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
        }
    }

    private func caption(_ who: Who, st: StatusItem?, mood: JarBall?) -> String {
        var parts = [who == .me ? "Я" : store.name(who)]
        if let st, !st.detailLine.isEmpty { parts.append(st.detailLine) }
        if let mood { parts.append(moodOf(mood.mood).title.lowercased()) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - 10. «Рация»: удерживай и скажи

struct TodayRacia: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @Binding var showStatus: Bool
    @StateObject private var voice = VoiceRecorder()
    @State private var holding = false
    @State private var sending = false
    @Environment(\.todayPalette) private var pal
    private var ink: Color { pal.ink }
    private var muted: Color { pal.muted }
    /// Кнопка рации — твой цвет: говоришь ты.
    private var orange: Color { store.meColor }

    var body: some View {
        VStack(spacing: 14) {
            partnerCard.padding(.top, 14)
            if let v = store.data.messages.last(where: { $0.from == .partner && $0.kind == "voice" }) {
                HStack {
                    VoiceBubble(m: v)
                    Spacer(minLength: 0)
                }
            }
            talk.padding(.top, 8)
            HStack(spacing: 8) {
                Button { store.hug() } label: { chip("Обнять") }.buttonStyle(PressStyle())
                Button { showStatus = true; store.tap() } label: { chip("Мой статус") }.buttonStyle(PressStyle())
                NavigationLink { ModuleView(module: .tasks) } label: {
                    chip(store.openTasks.isEmpty ? "Дела" : "Дела: \(store.openTasks.count)")
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var partnerCard: some View {
        let st = store.statusNow(.partner)
        let mood = store.lastMood(.partner).map { ", настроение: " + moodOf($0.mood).title.lowercased() } ?? ""
        return NavigationLink { StatusFeedView() } label: {
            HStack(spacing: 14) {
                AvatarFace(who: .partner, size: 56)
                    .overlay(Circle().stroke(pal.card, lineWidth: 3).padding(-3))
                    .overlay(Circle().stroke(store.partnerColor, lineWidth: 2).padding(-5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.name(.partner) + (st.map { ": " + $0.title.lowercased() } ?? ""))
                        .font(.body.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
                    Text((st.map { [$0.detailLine, $0.started.agoText].filter { !$0.isEmpty }.joined(separator: ", ") } ?? "пока без статуса") + mood)
                        .font(.subheadline).foregroundStyle(muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(pal.card, in: RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous))
            .shadow(color: pal.shadow, radius: 10, y: 6)
        }
        .buttonStyle(PressStyle())
    }

    private var talk: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(orange.opacity(0.18), lineWidth: 1.5).frame(width: 216, height: 216)
                    .scaleEffect(holding ? 1 + 0.12 * voice.level : 1)
                Circle().stroke(orange.opacity(0.28), lineWidth: 1.5).frame(width: 180, height: 180)
                    .scaleEffect(holding ? 1 + 0.07 * voice.level : 1)
                VStack(spacing: 6) {
                    if sending {
                        ProgressView().tint(orange.onAccent)
                    } else {
                        Image(systemName: "mic.fill").font(.system(size: 32, weight: .semibold))
                        Text(holding ? mmss(voice.seconds) : "Удерживай").font(.callout.weight(.semibold)).monospacedDigit()
                    }
                }
                .foregroundStyle(orange.onAccent)
                .frame(width: 156, height: 156)
                .background(RadialGradient(colors: [orange.hsb(dS: -0.15, dB: 0.15), orange], center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: 90), in: Circle())
                .shadow(color: orange.opacity(0.38), radius: 17, y: 16)
                .scaleEffect(holding ? 0.94 : 1)
                .animation(Motion.press, value: holding)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !holding, !sending else { return }
                            holding = true
                            store.tap()
                            Task {
                                let ok = await voice.start()
                                if !ok { holding = false; Toasts.shared.show("Нет доступа к микрофону", symbol: "mic.slash.fill") }
                            }
                        }
                        .onEnded { _ in
                            guard holding else { return }
                            holding = false
                            Task { await sendVoice() }
                        }
                )
                .accessibilityLabel("Удерживайте, чтобы сказать \(store.name(.partner))")
            }
            .frame(width: 216, height: 216)
            Text(holding ? "Отпусти, чтобы отправить" : "\(store.name(.partner)) услышит сразу")
                .font(.subheadline).foregroundStyle(muted)
                .contentTransition(.opacity)
                .animation(Motion.curve(0.2), value: holding)
        }
        .frame(maxWidth: .infinity)
    }

    private func sendVoice() async {
        let wave = voice.wave()
        guard let (url, d) = voice.stop(keep: true), let data = try? Data(contentsOf: url) else { return }
        sending = true
        defer { sending = false; try? FileManager.default.removeItem(at: url) }
        do {
            let r = try await sync.upload(data: data, name: "voice.m4a", mime: "audio/mp4")
            var m = ChatMessage(text: "🎤 Голосовое", from: .me)
            m.media = r.id; m.file = r.file; m.kind = "voice"; m.dur = d; m.wave = wave
            store.data.messages.append(m)
            store.sfx(.send)
            Toasts.shared.show("Голосовое отправлено", symbol: "waveform")
        } catch {
            Toasts.shared.show("Не отправилось, проверь интернет", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func mmss(_ s: Double) -> String {
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(pal.card, in: Capsule())
            .overlay(Capsule().strokeBorder(pal.line, lineWidth: pal.dark ? 1 : 0))
    }
}

// MARK: - 11. «Острова»: два цветных острова

private struct LobeMe: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 390, sy = r.height / 470
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 300 * sx, y: 0))
        p.addCurve(to: CGPoint(x: 196 * sx, y: 180 * sy), control1: CGPoint(x: 285 * sx, y: 66 * sy), control2: CGPoint(x: 210 * sx, y: 104 * sy))
        p.addCurve(to: CGPoint(x: 0, y: 300 * sy), control1: CGPoint(x: 184 * sx, y: 248 * sy), control2: CGPoint(x: 120 * sx, y: 284 * sy))
        p.closeSubpath()
        return p
    }
}

private struct LobePartner: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 390, sy = r.height / 470
        var p = Path()
        p.move(to: CGPoint(x: 390 * sx, y: 112 * sy))
        p.addLine(to: CGPoint(x: 390 * sx, y: 470 * sy))
        p.addCurve(to: CGPoint(x: 150 * sx, y: 440 * sy), control1: CGPoint(x: 320 * sx, y: 476 * sy), control2: CGPoint(x: 220 * sx, y: 466 * sy))
        p.addCurve(to: CGPoint(x: 118 * sx, y: 330 * sy), control1: CGPoint(x: 90 * sx, y: 414 * sy), control2: CGPoint(x: 70 * sx, y: 372 * sy))
        p.addCurve(to: CGPoint(x: 248 * sx, y: 214 * sy), control1: CGPoint(x: 168 * sx, y: 288 * sy), control2: CGPoint(x: 236 * sx, y: 282 * sy))
        p.addCurve(to: CGPoint(x: 390 * sx, y: 112 * sy), control1: CGPoint(x: 258 * sx, y: 160 * sy), control2: CGPoint(x: 320 * sx, y: 120 * sy))
        p.closeSubpath()
        return p
    }
}

struct TodayOstrova: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool
    private var ink: Color { pal.ink }
    /// Острова — цвета пары, смягчённые под фон темы.
    private var meLand: Color { pal.dark ? HSB.mix(pal.bg, store.meColor, 0.62) : HSB.mix(.white, store.meColor, 0.55) }
    private var partnerLand: Color { pal.dark ? HSB.mix(pal.bg, store.partnerColor, 0.62) : HSB.mix(.white, store.partnerColor, 0.5) }

    var body: some View {
        VStack(spacing: 0) {
            map.frame(height: 470)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    NavigationLink { ModuleView(module: .chat) } label: {
                        capsule("Ответить", fill: store.meColor, text: store.meColor.onAccent)
                    }
                    .buttonStyle(PressStyle())
                    Button { store.hug() } label: {
                        capsule("Обнять", fill: store.partnerColor, text: store.partnerColor.onAccent)
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.bottom, 10)
                if let m = store.lastPartnerMessage {
                    NavigationLink { ModuleView(module: .chat) } label: {
                        line(m.kind == "voice" ? "Голосовое сообщение" : m.text, m.date.agoText)
                    }
                    .buttonStyle(PressStyle())
                }
                NavigationLink { ModuleView(module: .tasks) } label: {
                    line(store.openTasks.isEmpty ? "Дел нет" : "Дела: \(store.openTasks.count)", store.openTasks.first?.title ?? "")
                }
                .buttonStyle(PressStyle())
                if let (e, d) = store.nextEvent {
                    NavigationLink { ModuleView(module: .calendar) } label: { line(e.title, inDaysText(d), last: true) }
                        .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .padding(.bottom, 24)
    }

    private var map: some View {
        ZStack(alignment: .topLeading) {
            LobeMe().fill(meLand)
            LobePartner().fill(partnerLand)
            island(.me)
                .frame(maxWidth: 200, alignment: .leading)
                .padding(.leading, 20).padding(.top, 14)
            island(.partner)
                .frame(maxWidth: 210, alignment: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 22).padding(.bottom, 70)
            HStack(spacing: 8) {
                Text("\(store.daysTogether.formatted(.number.locale(ruLocale))) \(daysWord(store.daysTogether))")
                    .font(.subheadline.weight(.semibold))
                Circle().fill(pal.bg).frame(width: 24, height: 24)
                    .overlay(Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(store.partnerColor))
            }
            .foregroundStyle(pal.bg)
            .padding(.leading, 14).padding(.trailing, 6).frame(height: 36)
            .background(ink, in: Capsule())
            .shadow(color: pal.shadow, radius: 7, y: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(x: -40, y: 50)
        }
    }

    @ViewBuilder private func island(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let mood = store.lastMood(who).map { moodOf($0.mood).title.lowercased() }
        let align: HorizontalAlignment = who == .me ? .leading : .trailing
        let top = who == .me ? "Я" : store.name(who) + (st.map { ", " + $0.started.agoText } ?? "")
        let bottom = [st?.detailLine ?? "", mood ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        let label = VStack(alignment: align, spacing: 4) {
            Text(top).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") } ?? (who == .me ? "Твой статус?" : "Тихо"))
                .font(.system(size: 42, weight: .semibold)).tracking(-1.6).lineSpacing(-6)
                .lineLimit(3).minimumScaleFactor(0.7)
                .multilineTextAlignment(who == .me ? .leading : .trailing)
            if !bottom.isEmpty { Text(bottom).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(who == .me ? .leading : .trailing) }
        }
        .foregroundStyle(pal.text(on: who == .me ? meLand : partnerLand))
        if who == .me {
            Button { showStatus = true; store.tap() } label: { label }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { label }.buttonStyle(PressStyle())
        }
    }

    private func capsule(_ t: String, fill: Color, text: Color) -> some View {
        Text(t).font(.body.weight(.semibold)).foregroundStyle(text)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(fill, in: Capsule())
    }

    private func line(_ title: String, _ detail: String, last: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.body).foregroundStyle(ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(detail).font(.subheadline).foregroundStyle(pal.muted).lineLimit(1)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(ink.opacity(0.75)).frame(height: 1.5) } }
        .contentShape(Rectangle())
    }
}
