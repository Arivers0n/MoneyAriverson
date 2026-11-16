import SwiftUI

// MARK: - 5. «Погода»: настроение каждого — его половина неба

struct TodayPogoda: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    private let muted = Color.white.opacity(0.75)

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    sky(.me)
                    Rectangle().fill(Color.white.opacity(0.28)).frame(width: 1)
                    sky(.partner)
                }
                Button { store.hug() } label: {
                    Label("Отправить тепло", systemImage: "sun.max.fill")
                        .font(.body.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 20).frame(height: 48)
                        .background(Color.white.opacity(0.26), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .padding(.bottom, 18)
            }
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            day
            HStack(alignment: .top, spacing: 10) {
                NavigationLink { ModuleView(module: .chat) } label: {
                    module(title: store.lastPartnerMessage == nil ? "Чат" : "\(store.name(.partner)) пишет") {
                        Text(store.lastPartnerMessage.map { $0.kind == "voice" ? "Голосовое сообщение" : $0.text } ?? "Напиши первым")
                            .font(.body.weight(.medium)).foregroundStyle(.white).lineLimit(3).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Text(store.lastPartnerMessage?.date.agoText ?? "").font(.caption).foregroundStyle(muted)
                    }
                }
                .buttonStyle(PressStyle())
                module(title: "Вместе") {
                    Text(store.daysTogether.formatted(.number.locale(ruLocale)))
                        .font(.system(size: 34, weight: .light)).tracking(-0.6).foregroundStyle(.white)
                    Spacer(minLength: 4)
                    Text(store.nextEvent.map { $0.0.title.lowercased() + " " + inDaysText($0.1) } ?? daysWord(store.daysTogether) + " вместе")
                        .font(.caption).foregroundStyle(muted).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    @ViewBuilder private func sky(_ who: Who) -> some View {
        let w = moodWeather(store.lastMood(who)?.mood)
        let st = store.statusNow(who)
        let battery = store.battery(who).map { ", заряд \(Int($0.level * 100))%" } ?? ""
        let mood = store.lastMood(who).map { moodOf($0.mood).title.lowercased() } ?? "настроение не отмечено"
        let content = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: w.top), Color(hex: w.bottom)], startPoint: .top, endPoint: .bottom)
            if w.sunny {
                Circle().fill(RadialGradient(colors: [Color(hex: "FFECAA").opacity(0.95), Color(hex: "FFD678").opacity(0.3), .clear],
                                             center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 180, height: 180).offset(x: who == .me ? -40 : 50, y: -20)
            } else {
                VStack(spacing: 70) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(width: 200, height: 64).blur(radius: 14).offset(x: -30)
                    Capsule().fill(Color.white.opacity(0.14)).frame(width: 190, height: 56).blur(radius: 16).offset(x: 40)
                    Capsule().fill(Color.white.opacity(0.16)).frame(width: 220, height: 70).blur(radius: 18).offset(x: -10)
                }
                .padding(.top, 70)
            }
            VStack(spacing: 0) {
                Text(who == .me ? "Я" : store.name(who)).font(.title3.weight(.medium)).lineLimit(1)
                Text(w.word).font(.system(size: 44, weight: .thin)).tracking(-0.8).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 4)
                Text(st?.title ?? "Без статуса").font(.callout.weight(.semibold)).lineLimit(1).padding(.top, 8)
                if let st, !st.detailLine.isEmpty {
                    Text(st.detailLine).font(.subheadline).opacity(0.88).lineLimit(1).padding(.top, 2)
                }
                Text(mood + battery).font(.footnote).opacity(0.85).multilineTextAlignment(.center).lineLimit(2).padding(.top, 10)
            }
            .foregroundStyle(.white)
            .shadow(color: Color(hex: "142040").opacity(0.25), radius: 6, y: 1)
            .padding(.horizontal, 10).padding(.top, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        if who == .me {
            Button { showStatus = true; store.tap() } label: { content }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { content }.buttonStyle(PressStyle())
        }
    }

    private var day: some View {
        let entries = Array(store.dayEntries().reversed().suffix(8))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Ваш день").font(.footnote.weight(.medium)).foregroundStyle(muted)
            if entries.isEmpty {
                Text("Сегодня пока тихо").font(.subheadline).foregroundStyle(.white).frame(minHeight: 50)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(entries) { e in
                            VStack(spacing: 7) {
                                Text(timeText(e.date)).font(.footnote.weight(.medium).monospacedDigit()).foregroundStyle(.white)
                                Circle().fill(Color(hex: e.hex)).frame(width: 10, height: 10)
                                Text((e.who == .me ? "Я: " : String(store.name(e.who).prefix(1)) + ": ") + e.title.lowercased())
                                    .font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            }
                            .frame(width: 82)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func module<C: View>(title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(muted).lineLimit(1)
            c()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - 6. «Фотобудка»: две полоски кадров дня

struct TodayFoto: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                strip(.me).rotationEffect(.degrees(-3))
                strip(.partner).rotationEffect(.degrees(2.5)).padding(.top, -10)
            }
            .padding(.horizontal, 26).padding(.top, 18)

            if let m = store.lastPartnerMessage {
                NavigationLink { ModuleView(module: .chat) } label: {
                    HStack(spacing: 12) {
                        AvatarFace(who: .partner, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.kind == "voice" ? "Голосовое сообщение" : m.text).font(.body.weight(.medium)).foregroundStyle(.white).lineLimit(1)
                            Text(m.date.agoText + ", ответить").font(.caption).foregroundStyle(Color(hex: "F2C9D3"))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 58)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 20)
            }

            VStack(spacing: 8) {
                Button { showStatus = true; store.tap() } label: {
                    ZStack {
                        Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(Color.white).frame(width: 62, height: 62).shadow(color: .black.opacity(0.35), radius: 8, y: 6)
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Снять кадр дня")
                Text("Кадр дня").font(.footnote.weight(.medium)).foregroundStyle(Color(hex: "F7DCE3"))
            }
        }
        .padding(.bottom, 24)
    }

    private func strip(_ who: Who) -> some View {
        let entries = Array(store.dayEntries(who).prefix(3))
        return VStack(spacing: 8) {
            ForEach(entries) { e in photoFrame(e) }
            ForEach(entries.count..<3, id: \.self) { _ in emptyFrame(who) }
            Text(who == .me ? store.name(.me) : store.name(who))
                .font(.custom("Noteworthy-Bold", size: 16)).foregroundStyle(Color(hex: "2A1A1F"))
                .lineLimit(1).padding(.top, 2).padding(.bottom, 6)
        }
        .padding([.horizontal, .top], 8)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "FAF8F4"))
        .shadow(color: Color(hex: "140008").opacity(0.45), radius: 15, y: 14)
    }

    private func photoFrame(_ e: DayEntry) -> some View {
        let c = Color(hex: e.hex)
        return ZStack(alignment: .bottomLeading) {
            if let s = e.status, s.hasPhoto, let m = s.media, let f = s.file {
                RemoteImage(media: m, file: f, thumb: "320x320").frame(maxWidth: .infinity).frame(height: 100).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
            } else {
                LinearGradient(colors: [c.hsb(dS: -0.1, dB: 0.08), c.hsb(dS: 0.05, dB: -0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Group {
                    if let em = e.emoji, !em.isEmpty { Text(em).font(.system(size: 40)) }
                    else { Image(systemName: e.symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.white.opacity(0.6)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
            }
            Text(e.title + ", " + timeText(e.date)).font(.caption.weight(.semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8).padding(8)
        }
        .frame(height: 100)
        .clipped()
    }

    @ViewBuilder private func emptyFrame(_ who: Who) -> some View {
        if who == .me {
            Button { showStatus = true; store.tap() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    Text("Твой кадр").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Color(hex: "6B4552"))
                .frame(maxWidth: .infinity).frame(height: 100)
                .background(Color(hex: "EDE8E1"))
                .overlay(Rectangle().strokeBorder(Color(hex: "6B4552").opacity(0.25), lineWidth: 1.5))
            }
            .buttonStyle(PressStyle())
        } else {
            Text("Пока пусто").font(.footnote).foregroundStyle(Color(hex: "8C7A80"))
                .frame(maxWidth: .infinity).frame(height: 100)
                .background(Color(hex: "EDE8E1"))
        }
    }
}

// MARK: - 7. «До встречи»: билет с датой следующей встречи

struct TodayBilet: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    @State private var editMeeting = false
    private let ink = Color(hex: "142033")
    private let muted = Color(hex: "4E5B6E")
    private let accent = Color(hex: "E2483D")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ticket.padding(.top, 14)
            HStack(spacing: 10) {
                NavigationLink { ModuleView(module: .chat) } label: {
                    Text("Ответить").font(.body.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48).background(accent, in: Capsule())
                }
                .buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    Text("Обнять").font(.body.weight(.semibold)).foregroundStyle(Color(hex: "B8352C"))
                        .frame(maxWidth: .infinity).frame(height: 48).background(accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.top, 14)

            Text("Сейчас").font(.title3.weight(.bold)).foregroundStyle(ink).padding(.top, 24).padding(.leading, 4)
            VStack(spacing: 0) {
                if let m = store.lastPartnerMessage {
                    NavigationLink { ModuleView(module: .chat) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.kind == "voice" ? "Голосовое сообщение" : m.text).font(.body).foregroundStyle(ink).lineLimit(1)
                                Text("\(store.name(.partner)), \(m.date.agoText)").font(.footnote).foregroundStyle(muted)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: "A9B3C1"))
                        }
                        .padding(.horizontal, 16).frame(minHeight: 60).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    Divider().padding(.leading, 16)
                }
                let tasks = Array(store.openTasks.prefix(3))
                ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                    TaskCheckRow(task: t, accent: accent, ink: ink, muted: Color(hex: "A9B3C1")).padding(.horizontal, 16)
                    if i < tasks.count - 1 { Divider().padding(.leading, 50) }
                }
                if tasks.isEmpty && store.lastPartnerMessage == nil {
                    Text("Сейчас всё спокойно").font(.body).foregroundStyle(muted).frame(maxWidth: .infinity, minHeight: 56)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 8)

            week.padding(.top, 20)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .sheet(isPresented: $editMeeting) { MeetingSheet().environmentObject(store) }
    }

    private var ticket: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                side(.me, align: .leading)
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Rectangle().fill(.clear).frame(height: 1)
                            .overlay(Line().stroke(Color(hex: "9AA6B8"), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 5])))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "9AA6B8"))
                    }
                    if let km = store.distanceKm() {
                        Text(km.kmText).font(.footnote.weight(.semibold)).foregroundStyle(muted).lineLimit(1)
                    }
                }
                .frame(width: 70).padding(.top, 12)
                side(.partner, align: .trailing)
            }
            .padding(18)
            .background(
                Canvas { ctx, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var p = Path(); p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        ctx.stroke(p, with: .color(Color(hex: "2F6FC4").opacity(0.05)), lineWidth: 1.5)
                        x += 7
                    }
                }
            )
            ZStack {
                Line().stroke(Color(hex: "D4DBE4"), style: StrokeStyle(lineWidth: 2, dash: [6, 5])).frame(height: 2).padding(.horizontal, 14)
                HStack {
                    Circle().fill(Color(hex: "EDF1F5")).frame(width: 24, height: 24).offset(x: -12)
                    Spacer()
                    Circle().fill(Color(hex: "EDF1F5")).frame(width: 24, height: 24).offset(x: 12)
                }
            }
            .frame(height: 24)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Следующая встреча").font(.footnote.weight(.semibold)).foregroundStyle(muted)
                    if let (e, d) = store.nextMeeting {
                        Text(d == 0 ? "сегодня!" : inDaysText(d)).font(.system(size: 34, weight: .bold)).tracking(-0.6).foregroundStyle(ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(e.date.formatted(Date.FormatStyle().locale(ruLocale).day().month(.wide)) + ", вы вместе \(store.daysTogether.formatted(.number.locale(ruLocale))) \(daysWord(store.daysTogether))")
                            .font(.footnote).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.85)
                    } else {
                        Text("Когда увидитесь?").font(.system(size: 28, weight: .bold)).tracking(-0.5).foregroundStyle(ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("Вы вместе \(store.daysTogether.formatted(.number.locale(ruLocale))) \(daysWord(store.daysTogether))")
                            .font(.footnote).foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 4)
                Button { editMeeting = true; store.tap() } label: {
                    Text(store.nextMeeting == nil ? "Указать" : "Изменить").font(.body.weight(.semibold)).foregroundStyle(accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 18).padding(.bottom, 16).padding(.top, 4)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: ink.opacity(0.10), radius: 14, y: 12)
    }

    @ViewBuilder private func side(_ who: Who, align: HorizontalAlignment) -> some View {
        let st = store.statusNow(who)
        let label = VStack(alignment: align, spacing: 4) {
            Text(who == .me ? "Я" : store.name(who)).font(.body.weight(.bold))
                .foregroundStyle(store.color(who).boosted(minS: 0.5, minB: 0.55)).lineLimit(1)
            Text(st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") } ?? (who == .me ? "Поставить статус" : "Без статуса"))
                .font(.body.weight(.semibold)).foregroundStyle(ink).lineLimit(2)
                .multilineTextAlignment(align == .leading ? .leading : .trailing)
            if let st, !st.detailLine.isEmpty {
                Text(st.detailLine).font(.subheadline).foregroundStyle(muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
        if who == .me {
            Button { showStatus = true; store.tap() } label: { label }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { label }.buttonStyle(PressStyle())
        }
    }

    /// Неделя настроений: каждый день в одном масштабе, две точки — вы.
    private var week: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Неделя настроений").font(.footnote.weight(.semibold)).foregroundStyle(muted).padding(.leading, 4)
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    VStack(spacing: 6) {
                        ForEach(Who.allCases, id: \.self) { w in
                            let m = store.data.jar.filter { $0.who == w && cal.isDate($0.date, inSameDayAs: d) }.max { $0.date < $1.date }
                            Circle().fill(m.map { Color(hex: moodOf($0.mood).hex) } ?? Color(hex: "D4DBE4")).frame(width: 14, height: 14)
                        }
                        Text(d.formatted(Date.FormatStyle().locale(ruLocale).weekday(.abbreviated)))
                            .font(.caption2).foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Горизонтальная линия по середине рамки.
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - 8. «Кассета»: стороны А и Б

struct TodayKasseta: View {
    @EnvironmentObject var store: Store
    @Binding var showStatus: Bool
    @State private var side: Who = .partner
    private let ink = Color(hex: "1A2340")
    private let blue = Color(hex: "2A4BA0")
    private let muted = Color(hex: "535C78")

    var body: some View {
        VStack(spacing: 14) {
            Picker("Чья сторона", selection: $side) {
                Text("Сторона А, я").tag(Who.me)
                Text("Сторона Б, \(store.name(.partner))").tag(Who.partner)
            }
            .pickerStyle(.segmented)
            .padding(.top, 12)

            inlay
                .id(side)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))

            VStack(spacing: 0) {
                row(title: "Мой статус: " + (store.statusNow(.me)?.title.lowercased() ?? "нет"), action: "Сменить", accent: true) { showStatus = true; store.tap() }
                Divider().padding(.leading, 16)
                NavigationLink { ModuleView(module: .tasks) } label: {
                    rowLabel(title: store.openTasks.isEmpty ? "Дел нет" : "Дела: \(store.openTasks.count)",
                             detail: store.openTasks.first?.title ?? "", accent: false)
                }
                .buttonStyle(PressStyle())
                if let (e, d) = store.nextEvent {
                    Divider().padding(.leading, 16)
                    NavigationLink { ModuleView(module: .calendar) } label: {
                        rowLabel(title: e.title, detail: inDaysText(d), accent: false)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .animation(Motion.spring, value: side)
        .onChange(of: side) { _, _ in store.tap() }
    }

    private var inlay: some View {
        let st = store.statusNow(side)
        let entries = Array(store.dayEntries(side).filter { $0.status?.id != st?.id }.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                store.partnerColor.frame(maxWidth: .infinity)
                Color(hex: "E9B949").frame(maxWidth: .infinity)
                store.meColor.frame(maxWidth: .infinity)
            }
            .frame(height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("Сейчас играет").font(.footnote.weight(.semibold)).foregroundStyle(muted)
                Text(st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") } ?? "Тишина")
                    .font(.custom("Noteworthy-Bold", size: 28)).foregroundStyle(blue).lineLimit(2).padding(.top, 2)
                Text(st.map { [side == .me ? "Я" : store.name(side), $0.detailLine, $0.started.agoText].filter { !$0.isEmpty }.joined(separator: ", ") }
                     ?? (side == .me ? "Поставь статус" : "\(store.name(side)) пока без статуса"))
                    .font(.subheadline).foregroundStyle(muted).lineLimit(1).padding(.bottom, 8)
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    HStack {
                        Text(e.title).font(.custom("Noteworthy-Bold", size: 18)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(timeText(e.date)).font(.subheadline.monospacedDigit()).foregroundStyle(i == 0 ? muted : Color(hex: "8A93AD"))
                    }
                    .foregroundStyle(i == 0 ? blue : Color(hex: "8A93AD"))
                    .frame(height: 32)
                    .overlay(alignment: .bottom) { Rectangle().fill(blue.opacity(0.14)).frame(height: 1) }
                }
                if entries.isEmpty {
                    Text("Других треков сегодня нет").font(.custom("Noteworthy-Bold", size: 17)).foregroundStyle(Color(hex: "8A93AD")).frame(height: 32)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            HStack(spacing: 8) {
                if side == .partner {
                    NavigationLink { ModuleView(module: .chat) } label: { button("Ответить", filled: true) }.buttonStyle(PressStyle())
                    Button { store.hug() } label: { button("Обнять", filled: false) }.buttonStyle(PressStyle())
                } else {
                    Button { showStatus = true; store.tap() } label: { button("Сменить статус", filled: true) }.buttonStyle(PressStyle())
                    NavigationLink { JarView() } label: { button("Настроение", filled: false) }.buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: ink.opacity(0.08), radius: 12, y: 10)
    }

    private func button(_ t: String, filled: Bool) -> some View {
        Text(t).font(.body.weight(.semibold)).foregroundStyle(filled ? .white : blue).lineLimit(1)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(filled ? blue : blue.opacity(0.10), in: Capsule())
    }

    private func row(title: String, action: String, accent: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) { rowLabel(title: title, detail: action, accent: accent) }.buttonStyle(PressStyle())
    }

    private func rowLabel(title: String, detail: String, accent: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.body).foregroundStyle(ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(detail).font(.subheadline.weight(accent ? .semibold : .regular)).foregroundStyle(accent ? blue : muted).lineLimit(1)
        }
        .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
    }
}
