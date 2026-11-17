import SwiftUI

// MARK: - 12. «Виджеты»: плитки как на экране «Домой»

struct TodayWidgets: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool

    var body: some View {
        VStack(spacing: 12) {
            partnerWidget
            HStack(spacing: 12) {
                meWidget
                togetherWidget
            }
            HStack(spacing: 12) {
                moodWidget
                sleepWidget
            }
            tasksWidget
            if let (e, d) = store.nextMeeting ?? store.nextEvent { eventWidget(e, d) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }

    /// Подпись виджета: значок в цвете + короткое слово, как у системных виджетов.
    private func label(_ title: String, _ symbol: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.4)
        }
        .foregroundStyle(c)
        .lineLimit(1)
    }

    private var partnerWidget: some View {
        let st = store.statusNow(.partner)
        let mood = store.lastMood(.partner)
        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink { StatusFeedView() } label: {
                HStack(alignment: .top, spacing: 14) {
                    StoryAvatar(who: .partner, size: 62)
                    VStack(alignment: .leading, spacing: 3) {
                        label(store.name(.partner) + (st.map { " · " + $0.started.agoText } ?? ""), "person.fill", pal.partnerText)
                        Text(st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") } ?? "Без статуса")
                            .font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(pal.ink)
                            .lineLimit(2).minimumScaleFactor(0.8)
                        if let st, !st.detailLine.isEmpty {
                            Text(st.detailLine).font(.subheadline).foregroundStyle(pal.ink2).lineLimit(1)
                        }
                        HStack(spacing: 10) {
                            if let mood {
                                HStack(spacing: 5) {
                                    Circle().fill(Color(hex: moodOf(mood.mood).hex)).frame(width: 8, height: 8)
                                    Text(moodOf(mood.mood).title.lowercased()).lineLimit(1)
                                }
                            }
                            BatteryChip(who: .partner)
                            if let km = store.distanceKm() {
                                Text(km.kmText).lineLimit(1)
                            }
                        }
                        .font(.caption).foregroundStyle(pal.muted).padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }

            if let m = store.lastPartnerMessage {
                Rectangle().fill(pal.line).frame(height: 1)
                NavigationLink { ModuleView(module: .chat) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: m.kind == "voice" ? "waveform" : "bubble.left.fill").font(.footnote).foregroundStyle(pal.partnerText)
                        Text(m.kind == "voice" ? "Голосовое сообщение" : m.text).font(.subheadline).foregroundStyle(pal.ink).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(m.date.agoText).font(.caption).foregroundStyle(pal.muted).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            HStack(spacing: 8) {
                NavigationLink { ModuleView(module: .chat) } label: {
                    TodayPill(title: "Ответить", symbol: "arrowshape.turn.up.left.fill", fill: store.partnerColor, text: store.partnerColor.onAccent,
                              height: 40, font: .subheadline.weight(.semibold))
                }
                .buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    TodayPill(title: "Обнять", symbol: "heart.fill", fill: store.partnerColor.opacity(pal.dark ? 0.22 : 0.13), text: pal.partnerText,
                              height: 40, font: .subheadline.weight(.semibold))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(16)
        .card()
    }

    private func square<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 156, maxHeight: 156, alignment: .topLeading)
            .card()
    }

    private var meWidget: some View {
        let st = store.statusNow(.me)
        return Button { showStatus = true; store.tap() } label: {
            square {
                HStack(alignment: .top) {
                    StoryAvatar(who: .me, size: 44)
                    Spacer(minLength: 4)
                    label("Я", "person.fill", pal.meText)
                }
                Spacer(minLength: 6)
                Text(st.map { [$0.emoji ?? "", $0.title].filter { !$0.isEmpty }.joined(separator: " ") } ?? "Поставить статус")
                    .font(.system(size: 19, weight: .bold)).tracking(-0.3).foregroundStyle(pal.ink)
                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                Text(st.map { $0.detailLine.isEmpty ? $0.started.agoText : $0.detailLine } ?? "Как ты сейчас?")
                    .font(.caption).foregroundStyle(pal.muted).lineLimit(1).padding(.top, 2)
            }
        }
        .buttonStyle(PressStyle())
    }

    private var togetherWidget: some View {
        let n = store.daysTogether
        let m = store.nextMilestone
        return NavigationLink { ModuleView(module: .days) } label: {
            square {
                label("Вместе", "heart.fill", pal.partnerText)
                Spacer(minLength: 4)
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle().stroke(pal.line, lineWidth: 5)
                        Circle().trim(from: 0, to: max(0.02, m.progress))
                            .stroke(AngularGradient(colors: [store.meColor, store.partnerColor, store.meColor], center: .center),
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        BeatingHeart(size: 14)
                    }
                    .frame(width: 46, height: 46)
                    Spacer(minLength: 0)
                }
                Text(n.formatted(.number.locale(ruLocale)))
                    .font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-0.6).foregroundStyle(pal.ink)
                    .contentTransition(.numericText()).padding(.top, 6)
                Text("\(daysWord(n)) · до \(m.day) ещё \(m.left)").font(.caption).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(PressStyle())
    }

    private var moodWidget: some View {
        NavigationLink { JarView() } label: {
            square {
                label("Настроение", "sparkles", pal.meText)
                Spacer(minLength: 6)
                HStack(spacing: -6) {
                    ForEach(Who.allCases, id: \.self) { w in
                        let mm = store.lastMood(w)
                        MoodMarble(color: mm.map { Color(hex: moodOf($0.mood).hex) } ?? pal.faint.opacity(0.5), ring: store.color(w), d: 40)
                    }
                }
                Spacer(minLength: 6)
                Text(store.lastMood(.partner).map { store.name(.partner) + ": " + moodOf($0.mood).title.lowercased() } ?? "Отметь, как ты")
                    .font(.footnote.weight(.medium)).foregroundStyle(pal.ink).lineLimit(1)
                Text(store.lastMood(.me).map { "Ты: " + moodOf($0.mood).title.lowercased() } ?? "Ты: не отмечено")
                    .font(.caption).foregroundStyle(pal.muted).lineLimit(1)
            }
        }
        .buttonStyle(PressStyle())
    }

    private var sleepWidget: some View {
        let e = store.lastSleep(of: .me)
        let p = store.lastSleep(of: .partner)
        return NavigationLink { SleepView() } label: {
            square {
                label("Сон", "moon.zzz.fill", pal.meText)
                Spacer(minLength: 6)
                Text(e.map { hoursText($0.hours) } ?? "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-0.5).foregroundStyle(pal.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(e == nil ? "Записать, как спал" : "твой сон").font(.caption).foregroundStyle(pal.muted).lineLimit(1)
                Spacer(minLength: 4)
                Text(p.map { store.name(.partner) + ": " + hoursText($0.hours) } ?? store.name(.partner) + ": нет записи")
                    .font(.caption).foregroundStyle(pal.ink2).lineLimit(1)
            }
        }
        .buttonStyle(PressStyle())
    }

    private var tasksWidget: some View {
        let tasks = Array(store.openTasks.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                label("Дела", "checklist", pal.meText)
                Spacer()
                NavigationLink { ModuleView(module: .tasks) } label: {
                    Text(store.openTasks.isEmpty ? "Открыть" : "Все \(store.openTasks.count)")
                        .font(.footnote.weight(.semibold)).foregroundStyle(pal.meText).frame(minHeight: 30)
                }
                .buttonStyle(PressStyle())
            }
            if tasks.isEmpty {
                Text("Всё сделано, можно отдыхать").font(.subheadline).foregroundStyle(pal.muted).frame(minHeight: 40)
            } else {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { i, t in
                    TaskCheckRow(task: t, accent: pal.meText, ink: pal.ink, muted: pal.faint, font: .subheadline)
                    if i < tasks.count - 1 { Rectangle().fill(pal.line).frame(height: 1).padding(.leading, 34) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .card()
    }

    private func eventWidget(_ e: EventItem, _ d: Int) -> some View {
        NavigationLink { ModuleView(module: .calendar) } label: {
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(e.date.formatted(Date.FormatStyle().locale(ruLocale).month(.abbreviated)).uppercased())
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(store.partnerColor.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 18).background(store.partnerColor)
                    Text(e.date.formatted(Date.FormatStyle().locale(ruLocale).day()))
                        .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(pal.ink)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 54, height: 58)
                .background(pal.field)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    label(e.meeting == true ? "До встречи" : "Скоро", "calendar", pal.partnerText)
                    Text(e.title).font(.body.weight(.semibold)).foregroundStyle(pal.ink).lineLimit(1)
                    Text(inDaysText(d)).font(.subheadline).foregroundStyle(pal.muted)
                }
                Spacer(minLength: 0)
                Text(d == 0 ? "!" : "\(d)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(pal.partnerText)
                    .contentTransition(.numericText())
            }
            .padding(14)
            .card()
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - 13. «Журнал»: обложка о вас двоих

struct TodayJournal: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool

    private let serif = "Georgia"
    private let serifBold = "Georgia-Bold"
    private let serifItalic = "Georgia-Italic"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            cover.padding(.top, 22)
            portrait.padding(.top, 20)
            contents.padding(.top, 26)
            HStack(spacing: 10) {
                NavigationLink { ModuleView(module: .chat) } label: {
                    TodayPill(title: "Ответить", fill: pal.ink, text: pal.bg)
                }
                .buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    Text("Обнять").font(.body.weight(.semibold)).foregroundStyle(pal.ink)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .overlay(Capsule().strokeBorder(pal.ink, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }

    private var issueDate: String {
        Date().formatted(Date.FormatStyle().locale(ruLocale).weekday(.wide).day().month(.wide)).uppercased()
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text("Вдвоём").font(.custom(serifBold, size: 60)).tracking(-2.2).foregroundStyle(pal.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("№ \(store.daysTogether.formatted(.number.locale(ruLocale)))").font(.custom(serifBold, size: 17)).foregroundStyle(pal.partnerText)
                    Text("день вместе").font(.custom(serifItalic, size: 13)).foregroundStyle(pal.muted)
                }
            }
            Rectangle().fill(pal.ink).frame(height: 2)
            HStack {
                Text(issueDate).font(.system(size: 11, weight: .semibold)).tracking(1.2)
                Spacer(minLength: 6)
                if let km = store.distanceKm() {
                    Text("МЕЖДУ ВАМИ " + km.kmText.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2)
                }
            }
            .foregroundStyle(pal.ink2).lineLimit(1).minimumScaleFactor(0.8)
            Rectangle().fill(pal.ink).frame(height: 0.8)
        }
    }

    private var cover: some View {
        let st = store.statusNow(.partner)
        return NavigationLink { StatusFeedView() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("ГЛАВНОЕ").font(.system(size: 12, weight: .bold)).tracking(1.6).foregroundStyle(pal.partnerText)
                Text(coverTitle(st))
                .font(.custom(serif, size: 38)).tracking(-0.8).lineSpacing(-2)
                .foregroundStyle(pal.ink).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Text(coverDeck(st)).font(.custom(serifItalic, size: 18)).foregroundStyle(pal.ink2).lineSpacing(2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
    }

    private func coverTitle(_ st: StatusItem?) -> String {
        guard let st else { return store.name(.partner) + " пока молчит" }
        let emoji: String = (st.emoji ?? "").isEmpty ? "" : " " + (st.emoji ?? "")
        return "\(store.name(.partner)): «\(st.title)»\(emoji)"
    }

    private func coverDeck(_ st: StatusItem?) -> String {
        var parts: [String] = []
        if let st {
            if !st.detailLine.isEmpty { parts.append(st.detailLine.prefix(1).uppercased() + st.detailLine.dropFirst()) }
            parts.append("Обновлено " + st.started.agoText)
        } else {
            parts.append("Самое время спросить, как прошёл день")
        }
        if let m = store.lastMood(.partner) { parts.append("Настроение — " + moodOf(m.mood).title.lowercased()) }
        return parts.joined(separator: ". ") + "."
    }

    /// «Фото номера»: оба на обложке, подпись курсивом.
    private var portrait: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.r(6), style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                LinearGradient(colors: [pal.wash(store.meColor, pal.dark ? 0.45 : 0.35), pal.wash(store.partnerColor, pal.dark ? 0.5 : 0.4)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                GrainDots(color: pal.ink.opacity(0.06))
                HStack(spacing: -22) {
                    AvatarFace(who: .me, size: 112).overlay(Circle().stroke(pal.bg, lineWidth: 4))
                    AvatarFace(who: .partner, size: 112).overlay(Circle().stroke(pal.bg, lineWidth: 4)).offset(y: 14)
                }
                .shadow(color: pal.shadow, radius: 14, y: 10)
            }
            .frame(height: 190)
            .clipShape(shape)
            Text("На фото: \(store.name(.me)) и \(store.name(.partner)), \(store.startText)")
                .font(.custom(serifItalic, size: 13)).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private struct CoverLine: Identifiable {
        let id: String
        let title: String
        let tail: String
        let action: () -> Void
        let link: Module?
    }

    private var lines: [CoverLine] {
        var out: [CoverLine] = []
        if let st = store.statusNow(.me) {
            out.append(CoverLine(id: "me", title: "\(store.name(.me)): «\(st.title)»", tail: st.detailLine, action: { showStatus = true; store.tap() }, link: nil))
        } else {
            out.append(CoverLine(id: "me", title: "Колонка автора: как ты сегодня?", tail: "поставить статус", action: { showStatus = true; store.tap() }, link: nil))
        }
        if let m = store.lastPartnerMessage {
            out.append(CoverLine(id: "msg", title: "Письмо дня: «\(m.kind == "voice" ? "голосовое" : m.text)»", tail: m.date.agoText, action: {}, link: .chat))
        }
        let tasks = store.openTasks
        if !tasks.isEmpty {
            let more = tasks.count > 1 ? " и ещё \(tasks.count - 1)" : ""
            out.append(CoverLine(id: "tasks", title: "Дела: " + tasks[0].title.lowercased() + more, tail: tasks.contains { $0.priority > 0 } ? "есть важное" : "", action: {}, link: .tasks))
        }
        if let (e, d) = store.nextEvent {
            out.append(CoverLine(id: "event", title: e.title, tail: inDaysText(d), action: {}, link: .calendar))
        }
        out.append(CoverLine(id: "mood", title: "Прогноз настроения", tail: moodTail, action: {}, link: .mood))
        return out
    }

    private var moodTail: String {
        var p: [String] = []
        if let a = store.lastMood(.me) { p.append("ты — " + moodOf(a.mood).title.lowercased()) }
        if let b = store.lastMood(.partner) { p.append(store.name(.partner) + " — " + moodOf(b.mood).title.lowercased()) }
        return p.isEmpty ? "пока не отмечено" : p.joined(separator: ", ")
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("В ЭТОМ ВЫПУСКЕ").font(.system(size: 12, weight: .bold)).tracking(1.6).foregroundStyle(pal.ink)
                .padding(.bottom, 6)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                let row = HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(String(format: "%02d", i * 3 + 2)).font(.custom(serifBold, size: 22)).foregroundStyle(i % 2 == 0 ? pal.meText : pal.partnerText)
                        .frame(width: 32, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.title).font(.custom(serif, size: 18)).foregroundStyle(pal.ink).lineLimit(2).multilineTextAlignment(.leading)
                        if !l.tail.isEmpty { Text(l.tail).font(.footnote).foregroundStyle(pal.muted).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
                Group {
                    if let m = l.link {
                        NavigationLink { ModuleView(module: m) } label: { row }
                    } else {
                        Button(action: l.action) { row }
                    }
                }
                .buttonStyle(PressStyle())
                if i < lines.count - 1 { Rectangle().fill(pal.line).frame(height: 1) }
            }
        }
    }
}

// MARK: - 14. «Лента дня»: день обоих на одной линии времени

struct TodayLenta: View {
    @EnvironmentObject var store: Store
    @Environment(\.todayPalette) private var pal
    @Binding var showStatus: Bool

    private struct Item: Identifiable {
        let id: String
        let date: Date
        let who: Who
        let title: String
        let detail: String
        let hex: String?
        let emoji: String?
        let symbol: String
        let module: Module?
    }

    private var items: [Item] {
        let cal = Calendar.current
        var out: [Item] = store.dayEntries().map { e in
            Item(id: e.id, date: e.date, who: e.who, title: e.title,
                 detail: e.status?.detailLine ?? "настроение",
                 hex: e.hex, emoji: e.emoji, symbol: e.symbol, module: e.status == nil ? .mood : nil)
        }
        for m in store.data.messages.suffix(30) where cal.isDateInToday(m.date) {
            out.append(Item(id: "m" + m.id.uuidString, date: m.date, who: m.from,
                            title: m.kind == "voice" ? "Голосовое" : m.text, detail: "сообщение",
                            hex: nil, emoji: nil, symbol: m.kind == "voice" ? "waveform" : "bubble.left.fill", module: .chat))
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(14))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                now(.me)
                now(.partner)
            }
            timeline
            HStack(spacing: 8) {
                Button { showStatus = true; store.tap() } label: {
                    TodayPill(title: "Мой статус", fill: store.meColor, text: store.meColor.onAccent, height: 44, font: .subheadline.weight(.semibold))
                }
                .buttonStyle(PressStyle())
                NavigationLink { JarView() } label: {
                    TodayPill(title: "Настроение", fill: pal.card, text: pal.ink, height: 44, font: .subheadline.weight(.semibold))
                }
                .buttonStyle(PressStyle())
                Button { store.hug() } label: {
                    TodayPill(title: "Обнять", fill: store.partnerColor.opacity(pal.dark ? 0.24 : 0.14), text: pal.partnerText, height: 44, font: .subheadline.weight(.semibold))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    @ViewBuilder private func now(_ who: Who) -> some View {
        let st = store.statusNow(who)
        let content = HStack(spacing: 10) {
            StoryAvatar(who: who, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(who == .me ? "Я" : store.name(who)).font(.caption.weight(.semibold))
                    .foregroundStyle(who == .me ? pal.meText : pal.partnerText).lineLimit(1)
                Text(st?.title ?? (who == .me ? "Поставить" : "Без статуса")).font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .card()
        if who == .me {
            Button { showStatus = true; store.tap() } label: { content }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { content }.buttonStyle(PressStyle())
        }
    }

    private var timeline: some View {
        let list = items
        return VStack(spacing: 0) {
            HStack {
                Text("Я").foregroundStyle(pal.meText)
                Spacer()
                Text("Сегодня").foregroundStyle(pal.muted)
                Spacer()
                Text(store.name(.partner)).foregroundStyle(pal.partnerText)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 6).padding(.bottom, 12)

            if list.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sun.horizon").font(.system(size: 28, weight: .light)).foregroundStyle(pal.faint)
                    Text("День только начинается").font(.subheadline).foregroundStyle(pal.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, it in
                    row(it, first: i == 0, last: i == list.count - 1)
                }
            }
        }
        .padding(14)
        .card()
    }

    private func row(_ it: Item, first: Bool, last: Bool) -> some View {
        let c = it.hex.map { Color(hex: $0) } ?? store.color(it.who)
        return HStack(alignment: .center, spacing: 8) {
            Group { if it.who == .me { bubble(it, c) } else { Color.clear.frame(height: 1) } }
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(spacing: 3) {
                Text(timeText(it.date)).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(pal.muted)
                Circle().fill(c).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(pal.card, lineWidth: 2.5).padding(-2))
            }
            .frame(width: 46)
            .background(alignment: .center) {
                VStack(spacing: 0) {
                    Rectangle().fill(first ? Color.clear : pal.faint.opacity(0.45)).frame(width: 2)
                    Rectangle().fill(last ? Color.clear : pal.faint.opacity(0.45)).frame(width: 2)
                }
            }
            Group { if it.who == .partner { bubble(it, c) } else { Color.clear.frame(height: 1) } }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func bubble(_ it: Item, _ c: Color) -> some View {
        let lead = it.who == .partner
        let glyph = Group {
            if let e = it.emoji, !e.isEmpty {
                Text(e).font(.system(size: 15))
            } else {
                Image(systemName: it.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(TodayPalette.readable(c, dark: pal.dark))
            }
        }
        let text = VStack(alignment: lead ? .leading : .trailing, spacing: 1) {
            Text(it.title).font(.subheadline.weight(.medium)).foregroundStyle(pal.ink).lineLimit(2)
                .multilineTextAlignment(lead ? .leading : .trailing)
            if !it.detail.isEmpty { Text(it.detail).font(.caption2).foregroundStyle(pal.muted).lineLimit(1) }
        }
        let chip = HStack(spacing: 6) {
            if lead { glyph; text } else { text; glyph }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(c.opacity(pal.dark ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
        .padding(.vertical, 5)
        if let m = it.module {
            NavigationLink { ModuleView(module: m) } label: { chip }.buttonStyle(PressStyle())
        } else if it.who == .me {
            Button { showStatus = true; store.tap() } label: { chip }.buttonStyle(PressStyle())
        } else {
            NavigationLink { StatusFeedView() } label: { chip }.buttonStyle(PressStyle())
        }
    }
}
