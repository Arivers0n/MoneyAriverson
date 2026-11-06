import SwiftUI
import PhotosUI

struct Avatar: View {
    @EnvironmentObject var store: Store
    let who: Who
    var size: CGFloat = 54
    var body: some View {
        let st = store.statusNow(who)
        let ring = st.map { Color(hex: statusKind($0.kind).hex) } ?? store.color(who)
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(store.color(who))
                Text(String(store.name(who).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(ring, lineWidth: 2).padding(-4))
            if let st {
                Group {
                    if let e = st.emoji, !e.isEmpty {
                        Text(e).font(.system(size: size * 0.26))
                    } else {
                        Image(systemName: statusKind(st.kind).symbol).font(.system(size: size * 0.24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size * 0.42, height: size * 0.42)
                .background(ring, in: Circle()).overlay(Circle().stroke(Pal.bg, lineWidth: 2))
                .offset(x: 4, y: 4)
            }
        }
        .padding(6)
    }
}

// MARK: - Экран «Сегодня»

struct TodayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @State private var showStatus = false
    @State private var history = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                nowCard
                if let mine = store.statusNow(.me) { statusHero(mine, who: .me) } else { askCard }
                if let theirs = store.statusNow(.partner) { statusHero(theirs, who: .partner) }
                tiles
                infoRow
                batteryRow
                historyBlock
            }
            .padding(.horizontal, 16).padding(.bottom, 24).padding(.top, 4)
            .animation(Motion.spring, value: store.data.statuses)
            }
            .scrollIndicators(.hidden)
            .dockScroll()
        .floatingHeader { header.padding(.horizontal, 16) }
        .background(ThemeBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStatus) { StatusSheet().environmentObject(store) }
        .onAppear { store.location.refresh() }
    }

    // Шапка с аватарами

    private var dateTitle: String {
        let t = Date().formatted(Date.FormatStyle().locale(ruLocale).weekday(.wide).day().month(.wide))
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Есть сообщение от партнёра за последний час.
    private var hasUnread: Bool {
        guard let m = store.data.messages.last, m.from == .partner else { return false }
        return Date().timeIntervalSince(m.date) < 3600
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Сегодня").font(.system(size: 32, weight: .medium))
                Text(dateTitle)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink { ModuleView(module: .chat) } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(store.meColor).frame(width: 44, height: 44)
                    .glass(Circle(), tint: store.glassTint, interactive: true)
                    .overlay(alignment: .topTrailing) {
                        if hasUnread { Circle().fill(store.partnerColor).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Pal.bg, lineWidth: 2)).offset(x: 1, y: -1) }
                    }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Чат")
            HStack(spacing: 4) {
                VStack(spacing: 0) { Avatar(who: .me); Text("Я").font(.caption2.weight(.semibold)) }
                VStack(spacing: 0) { Avatar(who: .partner); Text(store.name(.partner)).font(.caption2.weight(.semibold)).lineLimit(1) }
                    .dialMenu(signalKinds.map { DialItem(id: $0.id, emoji: $0.emoji, title: $0.title) }) { store.sendSignal($0.id) }
            }
        }
        .padding(.top, 4)
    }

    // Главное сейчас: последнее сообщение, дела и ближайшая дата — то, ради чего открывают приложение

    private struct NowRow: Identifiable {
        let id: String
        let symbol: String
        let hex: String
        let title: String
        let detail: String
        let module: Module
    }

    /// Ближайшее наступление даты (для ежегодных — в этом или следующем году).
    private func nextDate(_ e: EventItem) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if !e.yearly { return cal.startOfDay(for: e.date) >= today ? cal.startOfDay(for: e.date) : nil }
        var c = cal.dateComponents([.month, .day], from: e.date)
        for add in 0...1 {
            c.year = cal.component(.year, from: today) + add
            if let d = cal.date(from: c), d >= today { return d }
        }
        return nil
    }

    private func inDays(_ n: Int) -> String {
        switch n {
        case 0: return "сегодня"
        case 1: return "завтра"
        default: return "через \(n) дн."
        }
    }

    private var nowRows: [NowRow] {
        var rows: [NowRow] = []
        if let m = store.data.messages.last(where: { $0.from == .partner }) {
            rows.append(NowRow(id: "msg", symbol: "bubble.left.fill", hex: "6EA8FF",
                               title: "\(store.name(.partner)): \(m.text)", detail: m.date.agoText, module: .chat))
        }
        let open = store.data.tasks.filter { !$0.done && $0.owner != .partner }
        if !open.isEmpty {
            let urgent = open.filter { $0.priority > 0 }.count
            rows.append(NowRow(id: "tasks", symbol: "checklist", hex: "3DBE8B",
                               title: "Дел впереди: \(open.count)",
                               detail: urgent > 0 ? "из них важных: \(urgent)" : "ничего срочного", module: .tasks))
        }
        let cal = Calendar.current
        let next = store.data.events.compactMap { e -> (EventItem, Date)? in nextDate(e).map { (e, $0) } }
            .min { $0.1 < $1.1 }
        if let (e, d) = next {
            let n = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: d).day ?? 0
            rows.append(NowRow(id: "event", symbol: "calendar", hex: "FF9E5E",
                               title: e.title, detail: inDays(n), module: .calendar))
        }
        return rows
    }

    @ViewBuilder private var nowCard: some View {
        let rows = nowRows
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    NavigationLink { ModuleView(module: r.module) } label: {
                        HStack(spacing: 12) {
                            let c = Color(hex: r.hex).boosted(minS: 0.5, minB: 0.75)
                            Image(systemName: r.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(c)
                                .frame(width: 34, height: 34).background(c.opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(r.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    if i < rows.count - 1 { Divider().padding(.leading, 62) }
                }
            }
            .card()
        }
    }

    // Что случилось?

    private var askCard: some View {
        VStack(spacing: 16) {
            PairMark(size: 44)
            VStack(spacing: 4) {
                Text("Ваш статус").font(.title3.weight(.medium))
                Text("\(store.name(.partner)) увидит его сразу. Он держится, пока вы его не смените")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button { showStatus = true; store.tap() } label: {
                Label("Добавить статус", systemImage: "plus").bigButton()
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 24).frame(maxWidth: .infinity).card()
    }

    // Большая карточка статуса

    private func statusHero(_ s: StatusItem, who: Who) -> some View {
        let k = statusKind(s.kind)
        let c = Color(hex: k.hex).boosted(minS: 0.55, minB: 0.8)
        let shape = RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous)
        let extra = [s.place, s.note].filter { !$0.isEmpty }.joined(separator: " · ")
        return Button {
            if who == .me { showStatus = true; store.tap() }
        } label: {
            VStack(spacing: 0) {
                if s.hasPhoto, let m = s.media, let f = s.file {
                    RemoteImage(media: m, file: f, thumb: "720x0")
                        .frame(maxWidth: .infinity).frame(height: 190).clipped()
                }
                HStack(spacing: 16) {
                    Group {
                        if let e = s.emoji, !e.isEmpty { Text(e).font(.system(size: 28)) }
                        else { Image(systemName: k.symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(c) }
                    }
                    .frame(width: 56, height: 56)
                    .background(c.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle().fill(store.color(who)).frame(width: 8, height: 8)
                            Text(who == .me ? "Я" : store.name(who)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(s.title).font(.system(size: 22, weight: .medium)).lineLimit(2)
                        Text(extra.isEmpty ? s.started.agoText : extra + " · " + s.started.agoText)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.opacity(0.08), in: shape)
            .clipShape(shape)
            .modifier(CardBG())
            .overlay(shape.strokeBorder(c.opacity(0.28), lineWidth: 0.5))
        }
        .buttonStyle(PressStyle())
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    // Быстрые разделы

    private var tiles: some View {
        HStack(spacing: 12) {
            tile("Сон", "moon.zzz", "9DB7FF", detail: sleepDetail) { SleepView() }
            tile("Трекер", "chart.bar", "FFC25C", detail: trackerDetail) { TrackerView() }
            tile("Банка", "face.smiling", "7EE0C0", detail: jarDetail) { JarView() }
        }
    }

    private func tile<D: View>(_ title: String, _ icon: String, _ hex: String, detail: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 10) {
                ArtIcon(symbol: icon, color: Color(hex: hex), size: 24)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 32, alignment: .topLeading)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        }
        .buttonStyle(PressStyle())
    }

    private var sleepDetail: String {
        if let e = store.lastSleep(of: .me) { return hoursText(e.hours) }
        return "Записать сон"
    }
    private var trackerDetail: String {
        let n = store.data.counters.reduce(0) { $0 + store.count($1.id, who: nil) }
        return n == 0 ? "Пока пусто" : "Сегодня: \(n)"
    }
    private var jarDetail: String {
        let n = store.data.jar.filter { Calendar.current.isDateInToday($0.date) }.count
        return n == 0 ? "Бросить шарик" : "Шариков: \(n)"
    }

    // Расстояние и дни

    private var infoRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Между нами", systemImage: "location").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if let d = store.distanceKm() {
                    Text(d.kmText).font(.system(size: 28, weight: .medium).monospacedDigit())
                        .contentTransition(.numericText()).animation(Motion.curve(0.3), value: d.kmText)
                } else {
                    Text(store.p.shareLocation ? "Ждём партнёра" : "Скрыто").font(.title3.weight(.medium))
                    Text(store.p.shareLocation ? " " : "Включите в настройках").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).card()
            VStack(alignment: .leading, spacing: 4) {
                Label("Вместе", systemImage: "heart").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                let days = max(0, Calendar.current.dateComponents([.day], from: store.p.start, to: Date()).day ?? 0)
                Text("\(days)").font(.system(size: 28, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText()).animation(Motion.curve(0.3), value: days)
                Text("дней").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).card()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // Батарея

    private var batteryRow: some View {
        HStack(spacing: 12) {
            ForEach(Who.allCases, id: \.self) { w in
                let b = store.data.batteries.first { $0.who == w }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(store.color(w)).frame(width: 8, height: 8)
                        Text(store.name(w)).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                        if b?.charging == true {
                            Image(systemName: "bolt.fill").font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(b.map { "\(Int($0.level * 100))%" } ?? "—").font(.subheadline.weight(.medium).monospacedDigit())
                            .contentTransition(.numericText()).animation(Motion.curve(0.3), value: b?.level)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            if let b {
                                Capsule().fill(batteryColor(b.level))
                                    .frame(width: max(8, g.size.width * CGFloat(b.level)))
                            }
                        }
                    }
                    .frame(height: 8)
                }
                .padding(16).frame(maxWidth: .infinity).card()
            }
        }
    }

    private func batteryColor(_ l: Double) -> Color {
        l < 0.2 ? Color(hex: "EF4444") : (l < 0.5 ? Color(hex: "F5B83D") : Color(hex: "34C38F"))
    }

    // История статусов

    private var historyBlock: some View {
        NavigationLink { StatusFeedView() } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.fill").foregroundStyle(store.meColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("История статусов").font(.subheadline.weight(.semibold))
                    Text("Что вы делали и когда").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14).card()
        }
        .buttonStyle(PressStyle())
    }
}

func hoursText(_ h: Double) -> String {
    let m = Int((h * 60).rounded())
    return "\(m / 60) ч \(m % 60) мин"
}

// MARK: - Выбор статуса

/// Свой статус или готовый, с эмодзи, подписью и фото. Держится, пока его не сменят.
struct StatusSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: StatusKind?
    @State private var customTitle = ""
    @State private var customEmoji = ""
    @State private var note = ""
    @State private var place = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoRaw: Data?
    @State private var keepOldPhoto: (media: String, file: String)?
    @State private var sending = false
    @State private var error: String?

    private var isCustom: Bool { picked?.id == "custom" }
    private var canSend: Bool {
        guard let picked else { return false }
        return picked.id != "custom" || !customTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    customCard
                    if !store.recentCustomStatuses.isEmpty { recent }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(statusKinds) { k in presetTile(k) }
                    }
                    photoCard
                    VStack(spacing: 10) {
                        TextField("Где вы? (по желанию)", text: $place)
                            .padding(16).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                        TextField("Пара слов к статусу", text: $note)
                            .padding(16).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button { Task { await send() } } label: {
                        HStack(spacing: 8) {
                            if sending { ProgressView().tint(store.meColor.onAccent) }
                            Text(sending ? "Отправляю…" : "Поставить статус")
                        }
                        .bigButton().opacity(canSend ? 1 : 0.4)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!canSend || sending)
                    Text("Статус виден партнёру, пока вы его не смените или не уберёте.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if store.statusNow(.me) != nil {
                        Button("Убрать статус", role: .destructive) { store.clearStatus(); dismiss() }
                    }
                }
                .padding(16)
                .animation(Motion.spring, value: picked?.id)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ThemeBackground())
            .navigationTitle("Мой статус")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onChange(of: pickedPhoto) { _, item in
                Task {
                    guard let item, let d = try? await item.loadTransferable(type: Data.self) else { return }
                    photoRaw = d
                    keepOldPhoto = nil
                    withAnimation(Motion.spring) { photo = UIImage(data: d) }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let s = store.statusNow(.me) {
                picked = statusKind(s.kind)
                if s.kind == "custom" { customTitle = s.title; customEmoji = s.emoji ?? "" }
                note = s.note
                place = s.place
                if s.hasPhoto, let m = s.media, let f = s.file { keepOldPhoto = (m, f) }
            }
        }
    }

    // MARK: Свой статус

    private var customCard: some View {
        let on = isCustom
        let c = Color(hex: customStatusKind.hex)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line").foregroundStyle(c)
                Text("Свой статус").font(.subheadline.weight(.semibold))
                Spacer()
            }
            HStack(spacing: 10) {
                TextField("🙂", text: $customEmoji)
                    .font(.system(size: 26)).multilineTextAlignment(.center)
                    .frame(width: 56, height: 52)
                    .background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                    .onChange(of: customEmoji) { _, v in
                        // Только один символ-эмодзи
                        if v.count > 1 { customEmoji = String(v.suffix(1)) }
                        if !v.isEmpty { select(customStatusKind) }
                    }
                TextField("Например: грущу, пишу диплом…", text: $customTitle)
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                    .onChange(of: customTitle) { _, v in if !v.isEmpty { select(customStatusKind) } }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(statusEmojis, id: \.self) { e in
                        Button { customEmoji = e; select(customStatusKind) } label: {
                            Text(e).font(.system(size: 22)).frame(width: 40, height: 40)
                                .background(customEmoji == e ? c.opacity(0.2) : Pal.field, in: Circle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? c.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: store.radius, style: .continuous))
        .card()
        .overlay(RoundedRectangle(cornerRadius: store.radius, style: .continuous).strokeBorder(on ? c : .clear, lineWidth: 2))
    }

    /// Свои статусы, которые уже ставили.
    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Недавние").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.recentCustomStatuses) { s in
                        Button {
                            customTitle = s.title; customEmoji = s.emoji ?? ""; select(customStatusKind)
                        } label: {
                            Text([s.emoji ?? "", s.title].filter { !$0.isEmpty }.joined(separator: " "))
                                .font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                .padding(.horizontal, 14).frame(height: 36)
                                .background(Pal.field, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    // MARK: Готовые

    private func presetTile(_ k: StatusKind) -> some View {
        let on = picked?.id == k.id
        return Button { select(k) } label: {
            VStack(spacing: 6) {
                Image(systemName: k.symbol).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: k.hex)).frame(height: 28)
                Text(k.title).font(.caption2.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(on ? Color(hex: k.hex).opacity(0.22) : Pal.card,
                        in: RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous)
                .stroke(on ? Color(hex: k.hex) : Color.clear, lineWidth: 2))
        }
        .buttonStyle(PressStyle())
    }

    private func select(_ k: StatusKind) {
        guard picked?.id != k.id else { return }
        withAnimation(Motion.curve(0.18)) { picked = k }
        store.tap()
    }

    // MARK: Фото

    private var photoCard: some View {
        let has = photo != nil || keepOldPhoto != nil
        return VStack(spacing: 10) {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous).fill(Pal.card)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 180).clipped()
                    } else if let old = keepOldPhoto {
                        RemoteImage(media: old.media, file: old.file, thumb: "720x0").frame(height: 180)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 22)).foregroundStyle(store.meColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Добавить фото к статусу").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text("Партнёр увидит его на экране «Сегодня»").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .frame(height: has ? 180 : 68)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous))
            }
            .buttonStyle(PressStyle())
            if has {
                Button("Убрать фото") {
                    withAnimation(Motion.spring) { photo = nil; photoRaw = nil; keepOldPhoto = nil; pickedPhoto = nil }
                }
                .font(.footnote)
            }
        }
    }

    // MARK: Отправка

    private func send() async {
        guard let picked, canSend else { return }
        sending = true
        error = nil
        var ph = keepOldPhoto
        if let raw = photoRaw {
            do { ph = try await store.uploadStatusPhoto(raw) }
            catch { self.error = SyncEngine.human(error); sending = false; return }
        }
        if picked.id == "custom" {
            store.setStatus(picked, title: customTitle, emoji: customEmoji, note: note, place: place, photo: ph)
        } else {
            store.setStatus(picked, note: note, place: place, photo: ph)
        }
        sending = false
        dismiss()
    }
}

// MARK: - Сон

struct SleepRing: View {
    let hours: Double?
    let quality: Int
    let color: Color
    var size: CGFloat = 130
    @State private var shown = false

    var body: some View {
        let q = min(max(quality, 1), 5)
        let c = hours == nil ? Color.gray.opacity(0.4) : Color(hex: sleepHexes[q])
        ZStack {
            Circle().stroke(c.opacity(0.18), lineWidth: size * 0.11)
            Circle().trim(from: 0, to: shown ? CGFloat(min((hours ?? 0) / 10, 1)) : 0)
                .stroke(c, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if let hours {
                    Text(String(format: "%.1f", hours).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: size * 0.26, weight: .medium))
                    Text("часов").font(.system(size: size * 0.09)).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: size * 0.3, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(Motion.curve(0.9)) { shown = true } }
    }
}

struct SleepView: View {
    @EnvironmentObject var store: Store
    @State private var bed = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date().addingTimeInterval(-86400)) ?? Date()
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quality = 4
    @State private var manualQuality = false

    private var hours: Double { max(0, wake.timeIntervalSince(bed) / 3600) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ForEach(Who.allCases, id: \.self) { w in
                        let e = store.lastSleep(of: w)
                        VStack(spacing: 8) {
                            Text(store.name(w)).font(.caption.weight(.medium)).foregroundStyle(store.color(w))
                            SleepRing(hours: e?.hours, quality: e?.quality ?? 3, color: store.color(w), size: 118)
                            if let e {
                                Text(sleepTitles[min(max(e.quality, 1), 5)]).font(.caption.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(Color(hex: sleepHexes[min(max(e.quality, 1), 5)]).opacity(0.2), in: Capsule())
                            } else {
                                Text("нет данных").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16).card()
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Записать мой сон").font(.headline)
                    DatePicker("Лёг(ла)", selection: $bed, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Проснулся(ась)", selection: $wake, displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text("Всего").foregroundStyle(.secondary)
                        Spacer()
                        Text(hoursText(hours)).font(.headline)
                    }
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { q in
                            Button {
                                quality = q; manualQuality = true; store.tap()
                            } label: {
                                Text(sleepTitles[q]).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundStyle(quality == q ? .white : .primary)
                                    .background(quality == q ? Color(hex: sleepHexes[q]) : Color(hex: sleepHexes[q]).opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    Button {
                        store.saveSleep(bed: bed, wake: wake, quality: quality)
                    } label: { Text("Сохранить").bigButton().opacity(hours < 0.5 ? 0.4 : 1) }
                        .disabled(hours < 0.5)
                }
                .padding(16).card()
                .onChange(of: hours) { _, h in if !manualQuality { quality = sleepQuality(forHours: h) } }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Последние 7 дней").font(.headline)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(lastDays(), id: \.self) { day in
                            VStack(spacing: 6) {
                                HStack(alignment: .bottom, spacing: 3) {
                                    column(store.sleep(of: .me, day: day), .me)
                                    column(store.sleep(of: .partner, day: day), .partner)
                                }
                                .frame(height: 110, alignment: .bottom)
                                Text(shortDay(day)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(16).card()
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Сон")
        .animation(Motion.curve(0.2), value: quality)
        .onAppear {
            if let e = store.sleep(of: .me, day: Date().dayKey) {
                bed = e.bedtime; wake = e.wake; quality = e.quality; manualQuality = true
            } else {
                quality = sleepQuality(forHours: hours)
            }
        }
    }

    private func column(_ e: SleepEntry?, _ w: Who) -> some View {
        let h = CGFloat(min((e?.hours ?? 0) / 12, 1)) * 110
        return RoundedRectangle(cornerRadius: Theme.r(5), style: .continuous)
            .fill(e == nil ? Color.gray.opacity(0.15) : store.color(w))
            .frame(width: 12, height: max(6, h))
    }

    private func lastDays() -> [String] {
        (0..<7).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())!.dayKey }
    }

    private func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        return parts.count == 3 ? "\(parts[2]).\(parts[1])" : key
    }
}

// MARK: - Трекер

struct TrackerView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var title = ""
    @State private var emoji = "⭐️"
    @State private var hex = "8C7BF2"
    @State private var bump: UUID?
    private let palette = ["38BDF8", "F43F5E", "F59E0B", "A0674B", "8C7BF2", "10B981", "E0457B", "64748B"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(store.data.counters) { c in counterCard(c) }
                Button { adding = true } label: {
                    Label("Новый счётчик", systemImage: "plus.circle.fill").bigButton()
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Трекер")
        .sheet(isPresented: $adding) { addSheet }
    }

    private func counterCard(_ c: TrackerCounter) -> some View {
        let tint = Color(hex: c.hex)
        let deep = tint.hsb(dS: 0.05, dB: -0.2)
        let total = store.count(c.id, who: nil)
        let st = store.streak(c.id)
        let shape = RoundedRectangle(cornerRadius: Theme.r(24), style: .continuous)
        return VStack(spacing: 16) {
            HStack {
                Text(c.emoji).font(.title)
                Text(c.title).font(.title3.weight(.medium)).foregroundStyle(.white)
                Spacer()
                if st > 0 {
                    Text("\(st) дн. подряд").font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4).background(.white.opacity(0.18), in: Capsule())
                }
            }
            Button {
                bump = c.id
                withAnimation(Motion.curve(0.2)) { store.addTrack(c.id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { bump = nil }
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 160, height: 160)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    Text("\(total)").font(.system(size: 64, weight: .medium).monospacedDigit()).foregroundStyle(deep)
                        .contentTransition(.numericText())
                }
                .scaleEffect(bump == c.id ? 0.97 : 1)
            }
            .buttonStyle(PressStyle())
            HStack(spacing: 8) {
                ForEach(Who.allCases, id: \.self) { w in
                    HStack(spacing: 8) {
                        Circle().fill(store.color(w)).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 1.5))
                        Text("\(store.name(w)): \(store.count(c.id, who: w))").font(.footnote.weight(.medium)).lineLimit(1)
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(.white.opacity(0.18), in: Capsule())
                }
                Button { withAnimation { store.undoTrack(c.id) } } label: {
                    Image(systemName: "arrow.uturn.backward").font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .frame(width: 40, height: 36).background(.white.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(deep, in: shape)
        .contextMenu {
            Button("Удалить счётчик", role: .destructive) {
                store.data.counters.removeAll { $0.id == c.id }
                store.data.tracks.removeAll { $0.counter == c.id }
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $title)
                TextField("Эмодзи", text: $emoji)
                HStack {
                    ForEach(palette, id: \.self) { h in
                        Circle().fill(Color(hex: h)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.primary, lineWidth: hex == h ? 2.5 : 0).padding(-3))
                            .onTapGesture { hex = h }
                    }
                }
            }
            .navigationTitle("Новый счётчик")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { adding = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        store.data.counters.append(TrackerCounter(title: t, emoji: String(emoji.prefix(2)), hex: hex))
                        title = ""
                        adding = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
