import SwiftUI

// Все цвета — из TodayPalette (тема + режим + цвета пары). Скругления — через Theme.r, чтобы следовать теме.

// MARK: - 1. «Письмо»: одна фраза о вас двоих

struct TodayPismo: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sentence.padding(.top, 10)
            Text(daysLine).font(.system(size: 17)).foregroundStyle(pal.ink2).lineSpacing(3).padding(.top, 14)
            HStack(spacing: 10) {
                Button { showStatus = true; store.tap() } label: {
                    Text(store.statusNow(.me) == nil ? "Поставить статус" : "Сменить статус")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.bg)
                        .padding(.horizontal, 20).frame(height: 46).background(pal.ink, in: Capsule())
                }
                .buttonStyle(PressStyle())
                NavigationLink { ModuleView(module: .chat) } label: {
                    Text("Написать").font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.ink)
                        .padding(.horizontal, 20).frame(height: 46)
                        .background(pal.card.opacity(0.85), in: Capsule())
                        .overlay(Capsule().strokeBorder(pal.line, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
            }
            .padding(.top, 22)

            Text("Сегодня у вас").font(.system(size: 20, weight: .semibold)).foregroundStyle(pal.ink).padding(.top, 34)
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
                Text("Дела").font(.system(size: 20, weight: .semibold)).foregroundStyle(pal.ink).padding(.top, 14)
                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                        TaskCheckRow(task: t, accent: pal.meText, ink: pal.ink, muted: pal.faint)
                        if i < tasks.count - 1 { Rectangle().fill(pal.line).frame(height: 1) }
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
            .foregroundColor(pal.ink).lineSpacing(5)
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
        let shape = RoundedRectangle(cornerRadius: Theme.r(22), style: .continuous)
        return c().padding(16)
            .frame(width: 214, height: 150, alignment: .topLeading)
            .background(pal.card, in: shape)
            .overlay(shape.strokeBorder(pal.line, lineWidth: pal.dark ? 1 : 0))
            .shadow(color: pal.shadow, radius: 12, y: 8)
    }

    private func messageSlip(_ m: ChatMessage) -> some View {
        NavigationLink { ModuleView(module: .chat) } label: {
            slip {
                VStack(alignment: .leading, spacing: 0) {
                    Text("«\(m.kind == "voice" ? "Голосовое" : m.text)»")
                        .font(.custom("TimesNewRomanPSMT", size: 20)).foregroundStyle(pal.ink).lineLimit(3).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    HStack {
                        Text("\(store.name(.partner)), \(m.date.agoText)").font(.footnote).foregroundStyle(pal.muted).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("Ответить").font(.footnote.weight(.semibold)).foregroundStyle(pal.partnerText)
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
                            MoodMarble(color: mm.map { Color(hex: moodOf($0.mood).hex) } ?? pal.faint.opacity(0.5), ring: store.color(w), d: 34)
                        }
                    }
                    Spacer(minLength: 6)
                    Text("Настроение").font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.ink)
                    Text(moodLine).font(.footnote).foregroundStyle(pal.muted).lineLimit(2)
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
                    Image(systemName: "moon.zzz.fill").font(.system(size: 24)).foregroundStyle(pal.meText)
                    Spacer(minLength: 6)
                    Text("Сон").font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.ink)
                    let e = store.lastSleep(of: .me)
                    Text(e.map { hoursText($0.hours) } ?? "Записать, как спал").font(.footnote).foregroundStyle(pal.muted).lineLimit(1)
                }
            }
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - 2. «Двое»: зеркальные половины

struct TodayDvoe: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool
    @State private var reply = ""
    @FocusState private var typing: Bool

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
                         detailColor: pal.meText)
                }
                .buttonStyle(PressStyle())
                NavigationLink { ModuleView(module: .calendar) } label: {
                    chip(title: store.nextEvent?.0.title ?? "Календарь", detail: store.nextEvent.map { inDaysText($0.1) } ?? "дат пока нет", detailColor: pal.muted)
                }
                .buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(pal.ink)
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
        let big = Theme.r(30), small = Theme.r(14)
        let shape = UnevenRoundedRectangle(topLeadingRadius: who == .me ? big : small, bottomLeadingRadius: who == .me ? big : small,
                                           bottomTrailingRadius: who == .me ? small : big, topTrailingRadius: who == .me ? small : big, style: .continuous)
        let lead = who == .me
        let content = VStack(alignment: lead ? .leading : .trailing, spacing: 0) {
            HStack(spacing: 10) {
                AvatarFace(who: who, size: 52)
                    .overlay(Circle().stroke(pal.bg, lineWidth: 3).padding(-3))
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
                        .foregroundStyle(TodayPalette.readable(Color(hex: statusKind(st.kind).hex), dark: pal.dark))
                } else {
                    Image(systemName: who == .me ? "plus.circle" : "moon.stars").font(.system(size: 40, weight: .light)).foregroundStyle(pal.faint)
                }
            }
            .frame(height: 54)
            Text(st?.title ?? (who == .me ? "Поставить статус" : "Без статуса"))
                .font(.system(size: 23, weight: .bold)).tracking(-0.3).lineLimit(2).minimumScaleFactor(0.75)
                .multilineTextAlignment(lead ? .leading : .trailing)
                .padding(.top, 14)
            if let st, !st.detailLine.isEmpty {
                Text(st.detailLine).font(.subheadline).foregroundStyle(pal.ink2).lineLimit(2)
                    .multilineTextAlignment(lead ? .leading : .trailing).padding(.top, 4)
            }
            Spacer(minLength: 8)
            Text(st.map { $0.started.agoText } ?? " ").font(.footnote).foregroundStyle(pal.muted)
            HStack(spacing: 8) {
                if let mood {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: moodOf(mood.mood).hex)).frame(width: 8, height: 8)
                        Text(moodOf(mood.mood).title.lowercased()).lineLimit(1)
                    }
                }
                BatteryChip(who: who)
            }
            .font(.caption).foregroundStyle(pal.ink2).padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: lead ? .topLeading : .topTrailing)
        .background {
            ZStack {
                shape.fill(pal.card.opacity(pal.dark ? 0.35 : 0.7))
                shape.fill(LinearGradient(colors: [c.opacity(pal.dark ? 0.30 : 0.24), c.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(shape.strokeBorder(c.opacity(pal.dark ? 0.28 : 0.22), lineWidth: 1))
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
            Text(daysWord(n)).font(.system(size: 11)).foregroundStyle(pal.muted)
        }
        .frame(width: 78, height: 78)
        .background(pal.bg, in: Circle())
        .overlay(Circle().stroke(pal.line, lineWidth: 1.5))
        .shadow(color: pal.shadow, radius: 13, y: 10)
        .offset(y: -32)
        .allowsHitTesting(false)
    }

    private func messageBlock(_ m: ChatMessage) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.r(26), style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                AvatarFace(who: .partner, size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.kind == "voice" ? "Голосовое сообщение" : m.text).font(.body)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(store.partnerColor.opacity(pal.dark ? 0.26 : 0.16), in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                    Text(m.date.agoText).font(.caption).foregroundStyle(pal.muted).padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                TextField("Ответить…", text: $reply)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .foregroundStyle(pal.ink)
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
            .background(pal.field.opacity(pal.dark ? 0.8 : 0.9), in: Capsule())
        }
        .padding(14)
        .background(pal.card.opacity(pal.dark ? 0.45 : 0.75), in: shape)
        .overlay(shape.strokeBorder(pal.line, lineWidth: 1))
    }

    private func send() {
        store.sendText(reply)
        reply = ""
        typing = false
    }

    private func chip(title: String, detail: String, detailColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.ink).lineLimit(1)
            Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(pal.card.opacity(pal.dark ? 0.45 : 0.75), in: RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
    }
}

// MARK: - 3. «Сцена»: вы двое и шторка с главным

struct TodayScena: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool

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
                .stroke(pal.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 7]))

                bubble(.partner, solid: true).position(x: min(you.x - 10, w - 108), y: you.y - 108)
                person(.partner).position(you)
                bubble(.me, solid: false).position(x: max(me.x + 30, 100), y: me.y - 104)
                person(.me).position(me)

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(pal.partnerText)
                    Text("\(store.daysTogether.formatted(.number.locale(ruLocale))) \(daysWord(store.daysTogether))")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 12).frame(height: 32)
                .background(pal.card.opacity(pal.dark ? 0.35 : 0.65), in: Capsule())
                .overlay(Capsule().strokeBorder(pal.line, lineWidth: 1))
                .position(x: w * 0.52, y: 300)
            }
            .foregroundStyle(pal.ink)
        }
    }

    @ViewBuilder private func person(_ who: Who) -> some View {
        let face = VStack(spacing: 8) {
            AvatarFace(who: who, size: 100)
                .overlay(Circle().stroke(pal.card.opacity(0.95), lineWidth: 4))
                .shadow(color: pal.shadow, radius: 20, y: 16)
            Text(who == .me ? "Я" : store.name(who)).font(.subheadline.weight(.semibold))
        }
        if who == .me {
            Button { showStatus = true; store.tap() } label: { face }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { face }.buttonStyle(PressStyle())
                .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
        }
    }

    private func bubble(_ who: Who, solid: Bool) -> some View {
        let st = store.statusNow(who)
        let title = st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") } ?? (who == .me ? "Поставь статус" : "Без статуса")
        let sub = st.map { $0.detailLine.isEmpty ? $0.started.agoText : $0.detailLine + ", " + $0.started.agoText } ?? ""
        let shape = RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous)
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).lineLimit(1)
            if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(pal.ink2).lineLimit(2) }
        }
        .foregroundStyle(pal.ink)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 200, alignment: .leading)
        .background(pal.card.opacity(solid ? 0.95 : (pal.dark ? 0.32 : 0.55)), in: shape)
        .overlay(shape.strokeBorder(pal.line, lineWidth: solid ? 0 : 1))
        .shadow(color: pal.shadow, radius: 13, y: 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(pal.ink.opacity(0.18)).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Button { showStatus = true; store.tap() } label: {
                    pill("Мой статус", fill: pal.ink, text: pal.card)
                }.buttonStyle(PressStyle())
                NavigationLink { JarView() } label: {
                    pill("Настроение", fill: pal.ink.opacity(0.07), text: pal.ink)
                }.buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    pill("Обнять", fill: store.partnerColor.opacity(pal.dark ? 0.24 : 0.14), text: pal.partnerText)
                }.buttonStyle(PressStyle())
            }
            .padding(.top, 14)
            VStack(spacing: 0) {
                ForEach(Array(store.todayNowRows.enumerated()), id: \.element.id) { i, r in
                    NavigationLink { ModuleView(module: r.module) } label: {
                        HStack(spacing: 12) {
                            let c = TodayPalette.readable(Color(hex: r.hex), dark: pal.dark)
                            Image(systemName: r.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(c)
                                .frame(width: 36, height: 36).background(c.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title).font(.body.weight(.medium)).foregroundStyle(pal.ink).lineLimit(1)
                                Text(r.detail).font(.footnote).foregroundStyle(pal.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(pal.faint)
                        }
                        .frame(minHeight: 58).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    if i < store.todayNowRows.count - 1 { Rectangle().fill(pal.line).frame(height: 1).padding(.leading, 48) }
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .top)
        .background(pal.card, in: UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous))
        .shadow(color: pal.shadow, radius: 20, y: -6)
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
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool

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
                        .font(.body.weight(.semibold)).foregroundStyle(pal.bg)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(pal.ink, in: Capsule())
                        .shadow(color: pal.shadow, radius: 9, y: 8)
                }
                .buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    Image(systemName: "heart.fill").font(.system(size: 21)).foregroundStyle(store.partnerColor)
                        .frame(width: 52, height: 52).background(pal.card.opacity(0.85), in: Circle())
                        .shadow(color: pal.shadow, radius: 7, y: 6)
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

    /// Бумага записки: светлая в светлой теме, приглушённая — в тёмной.
    private func notePaper(_ c: Color) -> Color {
        pal.dark ? HSB.mix(pal.paper, c, 0.22) : HSB.mix(.white, c, 0.2)
    }

    private var polaroid: some View {
        VStack(spacing: 8) {
            ZStack {
                LinearGradient(colors: [store.meColor.opacity(0.7), store.partnerColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: -14) {
                    AvatarFace(who: .me, size: 54).overlay(Circle().stroke(pal.paper, lineWidth: 3))
                    AvatarFace(who: .partner, size: 54).overlay(Circle().stroke(pal.paper, lineWidth: 3)).offset(y: 12)
                }
            }
            .frame(height: 128).clipped()
            Text("\(store.daysTogether.formatted(.number.locale(ruLocale)))-й день")
                .font(.custom("Noteworthy-Bold", size: 17)).foregroundStyle(pal.ink)
                .padding(.bottom, 6)
        }
        .padding([.horizontal, .top], 10)
        .frame(width: 156)
        .background(pal.paper)
        .shadow(color: pal.shadow, radius: 11, y: 10)
        .overlay(alignment: .top) { magnet(store.meColor).offset(y: -12) }
    }

    @ViewBuilder private func note(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let c = store.color(who)
        let card = VStack(alignment: .leading, spacing: 8) {
            Text(st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") + ($0.detailLine.isEmpty ? "" : ". " + $0.detailLine) }
                 ?? (who == .me ? "Оставь записку" : "Пока без записки"))
                .font(.custom("Noteworthy-Bold", size: 18)).foregroundStyle(pal.ink).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(who == .me ? "Я" + (st.map { ", " + $0.started.agoText } ?? "") : store.name(who) + (st.map { ", " + $0.started.agoText } ?? ""))
                .font(.caption).foregroundStyle(pal.muted).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(notePaper(c))
        .shadow(color: pal.shadow, radius: 10, y: 8)
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
            Rectangle().fill(store.meColor.opacity(0.35)).frame(height: 8)
            Text("Дела").font(.custom("Noteworthy-Bold", size: 18)).foregroundStyle(pal.ink).padding(.horizontal, 14).padding(.top, 10)
            if tasks.isEmpty {
                Text("Всё сделано").font(.subheadline).foregroundStyle(pal.muted).padding(.horizontal, 14).padding(.vertical, 10)
            } else {
                ForEach(tasks) { t in
                    TaskCheckRow(task: t, accent: pal.meText, ink: pal.ink, muted: pal.faint, font: .subheadline, compact: true)
                        .padding(.horizontal, 12)
                }
            }
            NavigationLink { ModuleView(module: .tasks) } label: {
                Text("Все дела").font(.footnote.weight(.semibold)).foregroundStyle(pal.meText)
                    .padding(.horizontal, 14).frame(minHeight: 36)
            }
            .buttonStyle(PressStyle())
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.paper)
        .shadow(color: pal.shadow, radius: 11, y: 10)
    }

    private func calendar(_ e: EventItem, _ d: Int) -> some View {
        NavigationLink { ModuleView(module: .calendar) } label: {
            VStack(spacing: 0) {
                Text(e.date.formatted(Date.FormatStyle().locale(ruLocale).month(.wide)))
                    .font(.caption.weight(.semibold)).foregroundStyle(store.partnerColor.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 5).background(store.partnerColor)
                Text(e.date.formatted(Date.FormatStyle().locale(ruLocale).day()))
                    .font(.system(size: 44, weight: .bold)).tracking(-1).foregroundStyle(pal.ink)
                Text(e.title.lowercased() + ", " + inDaysText(d))
                    .font(.caption).foregroundStyle(pal.muted).multilineTextAlignment(.center).lineLimit(3)
                    .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .frame(width: 120)
            .background(pal.paper)
            .shadow(color: pal.shadow, radius: 11, y: 10)
        }
        .buttonStyle(PressStyle())
    }
}
