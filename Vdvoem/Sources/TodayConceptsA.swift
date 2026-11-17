import SwiftUI

// MARK: - 1. «Письмо»: одна фраза о вас двоих

struct TodayPismo: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    private let ink = Color(hex: "1C2433")
    private let body2 = Color(hex: "4A5260")
    private let muted = Color(hex: "59616E")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sentence.padding(.top, 10)
            Text(daysLine).font(.system(size: 17)).foregroundStyle(body2).lineSpacing(3).padding(.top, 14)
            HStack(spacing: 10) {
                Button { showStatus = true; store.tap() } label: {
                    Text(store.statusNow(.me) == nil ? "Поставить статус" : "Сменить статус")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: "F7F8F5"))
                        .padding(.horizontal, 20).frame(height: 46).background(ink, in: Capsule())
                }
                .buttonStyle(PressStyle())
                NavigationLink { ModuleView(module: .chat) } label: {
                    Text("Написать").font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                        .padding(.horizontal, 20).frame(height: 46)
                        .background(Color.white.opacity(0.8), in: Capsule())
                        .overlay(Capsule().strokeBorder(ink.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressStyle())
            }
            .padding(.top, 22)

            Text("Сегодня у вас").font(.system(size: 20, weight: .semibold)).foregroundStyle(ink).padding(.top, 34)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    if let m = store.lastPartnerMessage { messageSlip(m) }
                    moodSlip
                    sleepSlip
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -24)

            let tasks = Array(store.openTasks.prefix(4))
            if !tasks.isEmpty {
                Text("Дела").font(.system(size: 20, weight: .semibold)).foregroundStyle(ink).padding(.top, 14)
                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                        TaskCheckRow(task: t, accent: Color(hex: "2F7FC4"), ink: ink, muted: muted)
                        if i < tasks.count - 1 { Divider().overlay(ink.opacity(0.06)) }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var sentence: some View {
        let p = store.statusNow(.partner)
        let m = store.statusNow(.me)
        let dot = Text(Image(systemName: "circle.fill")).font(.system(size: 13))
        var t = dot.foregroundColor(store.partnerColor) + Text(" " + store.name(.partner))
        if let p {
            t = t + Text(" — «\(p.title)»") + Text(p.detailLine.isEmpty ? "." : ", \(p.detailLine).")
        } else {
            t = t + Text(" пока без статуса.")
        }
        t = t + Text(" ") + dot.foregroundColor(store.meColor)
        if let m {
            t = t + Text(" Ты — «\(m.title)»") + Text(m.detailLine.isEmpty ? "." : ", \(m.detailLine).")
        } else {
            t = t + Text(" А у тебя статуса нет.")
        }
        return t.font(.custom("TimesNewRomanPSMT", size: 32))
            .foregroundColor(ink).lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(Motion.spring, value: store.data.statuses)
    }

    private var daysLine: String {
        let n = store.daysTogether
        var s = "Вы вместе \(n.formatted(.number.locale(ruLocale))) \(daysWord(n))."
        if let (e, d) = store.nextEvent {
            let w = inDaysText(d)
            s += " " + w.prefix(1).uppercased() + w.dropFirst() + " — " + e.title.lowercased() + "."
        }
        return s
    }

    private func slip<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding(16)
            .frame(width: 214, height: 150, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(hex: "3C485C").opacity(0.10), radius: 12, y: 8)
    }

    private func messageSlip(_ m: ChatMessage) -> some View {
        NavigationLink { ModuleView(module: .chat) } label: {
            slip {
                VStack(alignment: .leading, spacing: 0) {
                    Text("«\(m.kind == "voice" ? "Голосовое" : m.text)»")
                        .font(.custom("TimesNewRomanPSMT", size: 20)).foregroundStyle(ink).lineLimit(3).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    HStack {
                        Text("\(store.name(.partner)), \(m.date.agoText)").font(.footnote).foregroundStyle(muted).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("Ответить").font(.footnote.weight(.semibold)).foregroundStyle(store.partnerColor.boosted(minS: 0.5, minB: 0.6))
                    }
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private var moodSlip: some View {
        NavigationLink { JarView() } label: {
            slip {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        ForEach(Who.allCases, id: \.self) { w in
                            let mm = store.lastMood(w)
                            MoodMarble(color: mm.map { Color(hex: moodOf($0.mood).hex) } ?? Color.gray.opacity(0.4), ring: store.color(w), d: 34)
                        }
                    }
                    Spacer(minLength: 6)
                    Text("Настроение").font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                    Text(moodLine).font(.footnote).foregroundStyle(muted).lineLimit(2)
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private var moodLine: String {
        var parts: [String] = []
        if let a = store.lastMood(.me) { parts.append("ты — " + moodOf(a.mood).title.lowercased()) }
        if let b = store.lastMood(.partner) { parts.append(store.name(.partner) + " — " + moodOf(b.mood).title.lowercased()) }
        return parts.isEmpty ? "Отметь, как ты" : parts.joined(separator: ", ")
    }

    private var sleepSlip: some View {
        NavigationLink { SleepView() } label: {
            slip {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 24)).foregroundStyle(Color(hex: "6F86D6"))
                    Spacer(minLength: 6)
                    Text("Сон").font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                    let e = store.lastSleep(of: .me)
                    Text(e.map { hoursText($0.hours) } ?? "Записать, как спал").font(.footnote).foregroundStyle(muted).lineLimit(1)
                }
            }
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - 2. «Двое»: зеркальные половины

struct TodayDvoe: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    @State private var reply = ""
    @FocusState private var typing: Bool
    private let muted = Color(hex: "A9B4CC")

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                HStack(spacing: 8) {
                    half(.me)
                    half(.partner)
                }
                medal
            }
            .frame(height: 360)

            if let m = store.lastPartnerMessage { messageBlock(m) }

            HStack(spacing: 8) {
                NavigationLink { ModuleView(module: .tasks) } label: {
                    chip(title: tasksTitle, detail: store.openTasks.contains { $0.priority > 0 } ? "есть важное" : "без спешки",
                         detailColor: store.meColor.boosted(minS: 0.4, minB: 0.85))
                }
                .buttonStyle(PressStyle())
                NavigationLink { ModuleView(module: .calendar) } label: {
                    chip(title: store.nextEvent?.0.title ?? "Календарь", detail: store.nextEvent.map { inDaysText($0.1) } ?? "дат пока нет", detailColor: muted)
                }
                .buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var tasksTitle: String {
        let n = store.openTasks.count
        if n == 0 { return "Дел нет" }
        let w = (n % 10 == 1 && n % 100 != 11) ? "дело" : ((2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "дела" : "дел")
        return "\(n) \(w)"
    }

    @ViewBuilder private func half(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let c = store.color(who)
        let mood = store.lastMood(who)
        let shape = UnevenRoundedRectangle(topLeadingRadius: who == .me ? 30 : 14, bottomLeadingRadius: who == .me ? 30 : 14,
                                           bottomTrailingRadius: who == .me ? 14 : 30, topTrailingRadius: who == .me ? 14 : 30, style: .continuous)
        let lead = who == .me
        let content = VStack(alignment: lead ? .leading : .trailing, spacing: 0) {
            HStack(spacing: 10) {
                AvatarFace(who: who, size: 52)
                    .overlay(Circle().stroke(Color(hex: "0E1730"), lineWidth: 3).padding(-3))
                    .overlay(Circle().stroke(c, lineWidth: 2).padding(-5))
                Text(who == .me ? "Я" : store.name(who)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    .layoutPriority(1)
            }
            .environment(\.layoutDirection, lead ? .leftToRight : .rightToLeft)
            Spacer(minLength: 12)
            Group {
                if let st, let e = st.emoji, !e.isEmpty {
                    Text(e).font(.system(size: 50))
                } else if let st {
                    Image(systemName: statusKind(st.kind).symbol).font(.system(size: 42, weight: .medium))
                        .foregroundStyle(Color(hex: statusKind(st.kind).hex).boosted(minS: 0.45, minB: 0.9))
                } else {
                    Image(systemName: who == .me ? "plus.circle" : "moon.stars").font(.system(size: 40, weight: .light)).foregroundStyle(muted)
                }
            }
            .frame(height: 54)
            Text(st?.title ?? (who == .me ? "Поставить статус" : "Без статуса"))
                .font(.system(size: 23, weight: .bold)).tracking(-0.3).lineLimit(2).minimumScaleFactor(0.75)
                .multilineTextAlignment(lead ? .leading : .trailing)
                .padding(.top, 14)
            if let st, !st.detailLine.isEmpty {
                Text(st.detailLine).font(.subheadline).foregroundStyle(Color(hex: "C7CEDD")).lineLimit(2)
                    .multilineTextAlignment(lead ? .leading : .trailing).padding(.top, 4)
            }
            Spacer(minLength: 8)
            Text(st.map { $0.started.agoText } ?? " ").font(.footnote).foregroundStyle(muted)
            HStack(spacing: 8) {
                if let mood {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: moodOf(mood.mood).hex)).frame(width: 8, height: 8)
                        Text(moodOf(mood.mood).title.lowercased()).lineLimit(1)
                    }
                }
                BatteryChip(who: who)
            }
            .font(.caption).foregroundStyle(Color(hex: "C7CEDD")).padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: lead ? .topLeading : .topTrailing)
        .background(LinearGradient(colors: [c.opacity(0.26), c.opacity(0.06)], startPoint: .top, endPoint: .bottom), in: shape)
        .overlay(shape.strokeBorder(c.opacity(0.25), lineWidth: 1))
        if who == .me {
            Button { showStatus = true; store.tap() } label: { content }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { content }.buttonStyle(PressStyle())
                .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
        }
    }

    private var medal: some View {
        let n = store.daysTogether
        return VStack(spacing: 1) {
            BeatingHeart(size: 15)
            Text(n.formatted(.number.locale(ruLocale))).font(.system(size: 17, weight: .bold)).tracking(-0.3)
                .contentTransition(.numericText())
            Text(daysWord(n)).font(.system(size: 11)).foregroundStyle(muted)
        }
        .frame(width: 78, height: 78)
        .background(Color(hex: "0E1730"), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.45), radius: 13, y: 10)
        .offset(y: -32)
        .allowsHitTesting(false)
    }

    private func messageBlock(_ m: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                AvatarFace(who: .partner, size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.kind == "voice" ? "Голосовое сообщение" : m.text).font(.body)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(store.partnerColor.opacity(0.22), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                    Text(m.date.agoText).font(.caption).foregroundStyle(muted).padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                TextField("Ответить…", text: $reply)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .foregroundStyle(.white)
                    .tint(store.meColor)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(store.meColor.onAccent)
                        .frame(width: 34, height: 34)
                        .background(store.meColor, in: Circle())
                        .opacity(reply.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
                .buttonStyle(PressStyle())
                .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Отправить")
            }
            .padding(.leading, 16).padding(.trailing, 6).frame(height: 46)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func send() {
        store.sendText(reply)
        reply = ""
        typing = false
    }

    private func chip(title: String, detail: String, detailColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - 3. «Сцена»: вы двое и шторка с главным

struct TodayScena: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    private let ink = Color(hex: "1B2160")
    private let muted = Color(hex: "5A5F8C")

    var body: some View {
        VStack(spacing: 0) {
            scene.frame(height: 350)
            panel
        }
    }

    private var scene: some View {
        GeometryReader { g in
            let w = g.size.width
            let me = CGPoint(x: w * 0.23, y: 232)
            let you = CGPoint(x: w * 0.75, y: 168)
            ZStack {
                Path { p in
                    p.move(to: me)
                    p.addCurve(to: you, control1: CGPoint(x: me.x + 60, y: me.y + 90), control2: CGPoint(x: you.x - 50, y: you.y + 120))
                }
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 7]))

                bubble(.partner, light: true).position(x: min(you.x - 10, w - 108), y: you.y - 108)
                person(.partner).position(you)
                bubble(.me, light: false).position(x: max(me.x + 30, 100), y: me.y - 104)
                person(.me).position(me)

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(store.partnerColor.boosted(minS: 0.3, minB: 0.95))
                    Text("\(store.daysTogether.formatted(.number.locale(ruLocale))) \(daysWord(store.daysTogether))")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 12).frame(height: 32)
                .background(Color(hex: "1B2672").opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .position(x: w * 0.52, y: 300)
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder private func person(_ who: Who) -> some View {
        let face = VStack(spacing: 8) {
            AvatarFace(who: who, size: 100)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 4))
                .shadow(color: Color(hex: "1E145A").opacity(0.45), radius: 20, y: 16)
            Text(who == .me ? "Я" : store.name(who)).font(.subheadline.weight(.semibold))
        }
        if who == .me {
            Button { showStatus = true; store.tap() } label: { face }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { face }.buttonStyle(PressStyle())
                .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
        }
    }

    private func bubble(_ who: Who, light: Bool) -> some View {
        let st = store.statusNow(who)
        let title = st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") } ?? (who == .me ? "Поставь статус" : "Без статуса")
        let sub = st.map { $0.detailLine.isEmpty ? $0.started.agoText : $0.detailLine + ", " + $0.started.agoText } ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).lineLimit(1)
            if !sub.isEmpty { Text(sub).font(.caption).opacity(0.85).lineLimit(2) }
        }
        .foregroundStyle(light ? ink : .white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 200, alignment: .leading)
        .background(light ? AnyShapeStyle(Color.white.opacity(0.94)) : AnyShapeStyle(Color.white.opacity(0.2)),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "141450").opacity(0.22), radius: 13, y: 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(ink.opacity(0.18)).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Button { showStatus = true; store.tap() } label: {
                    pill("Мой статус", fill: ink, text: .white)
                }.buttonStyle(PressStyle())
                NavigationLink { JarView() } label: {
                    pill("Настроение", fill: ink.opacity(0.07), text: ink)
                }.buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    pill("Обнять", fill: store.partnerColor.opacity(0.16), text: store.partnerColor.hsb(dS: 0.1, dB: -0.25))
                }.buttonStyle(PressStyle())
            }
            .padding(.top, 14)
            VStack(spacing: 0) {
                ForEach(Array(store.todayNowRows.enumerated()), id: \.element.id) { i, r in
                    NavigationLink { ModuleView(module: r.module) } label: {
                        HStack(spacing: 12) {
                            let c = Color(hex: r.hex).boosted(minS: 0.5, minB: 0.6)
                            Image(systemName: r.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(c)
                                .frame(width: 36, height: 36).background(c.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.body.weight(.medium)).foregroundStyle(ink).lineLimit(1)
                                Text(r.detail).font(.footnote).foregroundStyle(muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.3))
                        }
                        .frame(minHeight: 58).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    if i < store.todayNowRows.count - 1 { Divider() }
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .top)
        .background(Color(hex: "F7F5FC"), in: UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous))
        .shadow(color: Color(hex: "141450").opacity(0.25), radius: 20, y: -6)
        .environment(\.colorScheme, .light)
    }

    private func pill(_ t: String, fill: Color, text: Color) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(text).lineLimit(1)
            .padding(.horizontal, 16).frame(height: 40)
            .background(fill, in: Capsule())
    }
}

// MARK: - 4. «Холодильник»: записки на магнитах

struct TodayFridge: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    private let ink = Color(hex: "1F2B26")
    private let muted = Color(hex: "47574F")

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                polaroid.rotationEffect(.degrees(-3))
                VStack(spacing: 22) {
                    note(.partner).rotationEffect(.degrees(2.5))
                    note(.me).rotationEffect(.degrees(-1.5))
                }
            }
            .padding(.top, 14)
            HStack(alignment: .top, spacing: 16) {
                list.rotationEffect(.degrees(1))
                if let (e, d) = store.nextEvent { calendar(e, d).rotationEffect(.degrees(-2)) }
            }
            HStack(spacing: 10) {
                Button { showStatus = true; store.tap() } label: {
                    Label("Оставить записку", systemImage: "pencil.line")
                        .font(.body.weight(.semibold)).foregroundStyle(Color(hex: "F2F7F4"))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(ink, in: Capsule())
                        .shadow(color: ink.opacity(0.28), radius: 9, y: 8)
                }
                .buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    Image(systemName: "heart.fill").font(.system(size: 21)).foregroundStyle(store.partnerColor)
                        .frame(width: 52, height: 52).background(Color.white.opacity(0.75), in: Circle())
                        .shadow(color: ink.opacity(0.14), radius: 7, y: 6)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Обнять")
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func magnet(_ c: Color) -> some View {
        Circle().fill(RadialGradient(colors: [c.hsb(dS: -0.35, dB: 0.25), c], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
    }

    private var polaroid: some View {
        VStack(spacing: 8) {
            ZStack {
                LinearGradient(colors: [store.meColor.opacity(0.7), store.partnerColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: -14) {
                    AvatarFace(who: .me, size: 54).overlay(Circle().stroke(Color(hex: "FBFBF8"), lineWidth: 3))
                    AvatarFace(who: .partner, size: 54).overlay(Circle().stroke(Color(hex: "FBFBF8"), lineWidth: 3)).offset(y: 12)
                }
            }
            .frame(height: 128).clipped()
            Text("\(store.daysTogether.formatted(.number.locale(ruLocale)))-й день")
                .font(.custom("Noteworthy-Bold", size: 17)).foregroundStyle(ink)
                .padding(.bottom, 6)
        }
        .padding([.horizontal, .top], 10)
        .frame(width: 156)
        .background(Color(hex: "FBFBF8"))
        .shadow(color: Color(hex: "1E3C30").opacity(0.22), radius: 11, y: 10)
        .overlay(alignment: .top) { magnet(Color(hex: "F2B705")).offset(y: -12) }
    }

    @ViewBuilder private func note(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let c = store.color(who)
        let card = VStack(alignment: .leading, spacing: 8) {
            Text(st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") + ($0.detailLine.isEmpty ? "" : ". " + $0.detailLine) }
                 ?? (who == .me ? "Оставь записку" : "Пока без записки"))
                .font(.custom("Noteworthy-Bold", size: 18)).foregroundStyle(ink).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(who == .me ? "Я" + (st.map { ", " + $0.started.agoText } ?? "") : store.name(who) + (st.map { ", " + $0.started.agoText } ?? ""))
                .font(.caption).foregroundStyle(muted).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.white.overlay(c.opacity(0.22)))
        .shadow(color: c.hsb(dB: -0.4).opacity(0.18), radius: 10, y: 8)
        .overlay(alignment: .top) { magnet(c).offset(y: -11) }
        if who == .me {
            Button { showStatus = true; store.tap() } label: { card }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { card }.buttonStyle(PressStyle())
        }
    }

    private var list: some View {
        let tasks = Array(store.openTasks.prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(hex: "E9E4CF")).frame(height: 8)
            Text("Дела").font(.custom("Noteworthy-Bold", size: 18)).foregroundStyle(ink).padding(.horizontal, 14).padding(.top, 10)
            if tasks.isEmpty {
                Text("Всё сделано").font(.subheadline).foregroundStyle(muted).padding(.horizontal, 14).padding(.vertical, 10)
            } else {
                ForEach(tasks) { t in
                    TaskCheckRow(task: t, accent: Color(hex: "2B5D4F"), ink: ink, muted: muted, font: .subheadline, compact: true)
                        .padding(.horizontal, 12)
                }
            }
            NavigationLink { ModuleView(module: .tasks) } label: {
                Text("Все дела").font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: "2B5D4F"))
                    .padding(.horizontal, 14).frame(minHeight: 36)
            }
            .buttonStyle(PressStyle())
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FFFEF6"))
        .shadow(color: Color(hex: "1E3C30").opacity(0.2), radius: 11, y: 10)
    }

    private func calendar(_ e: EventItem, _ d: Int) -> some View {
        NavigationLink { ModuleView(module: .calendar) } label: {
            VStack(spacing: 0) {
                Text(e.date.formatted(Date.FormatStyle().locale(ruLocale).month(.wide)))
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 5).background(Color(hex: "C8452E"))
                Text(e.date.formatted(Date.FormatStyle().locale(ruLocale).day()))
                    .font(.system(size: 44, weight: .bold)).tracking(-1).foregroundStyle(ink)
                Text(e.title.lowercased() + ", " + inDaysText(d))
                    .font(.caption).foregroundStyle(muted).multilineTextAlignment(.center).lineLimit(3)
                    .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .frame(width: 120)
            .background(Color.white)
            .shadow(color: Color(hex: "1E3C30").opacity(0.2), radius: 11, y: 10)
        }
        .buttonStyle(PressStyle())
    }
}
