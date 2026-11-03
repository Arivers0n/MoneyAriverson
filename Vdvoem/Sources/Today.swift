import SwiftUI

// MARK: - Общие украшения

/// Плавно «дышащий» значок: покачивается и слегка вращается.
struct FloatingGlyph: View {
    let symbol: String
    var size: CGFloat = 90
    var color: Color = .white
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 10)
                .offset(y: CGFloat(sin(t * 1.6)) * 7)
                .rotationEffect(.degrees(sin(t * 1.1) * 4))
        }
    }
}

/// Стеклянные пузыри вокруг центра (как в ориентирах).
struct BubbleField: View {
    let colors: [Color]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<7, id: \.self) { i in
                    let r = CGFloat(10 + (i * 7) % 22)
                    let ang = Double(i) * 0.9 + t * (0.18 + Double(i % 3) * 0.05)
                    let rad: CGFloat = 70 + CGFloat((i * 13) % 40)
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.9), colors[i % colors.count].opacity(0.75)],
                                             center: .init(x: 0.3, y: 0.3), startRadius: 1, endRadius: r * 1.4))
                        .frame(width: r * 2, height: r * 2)
                        .offset(x: CGFloat(cos(ang)) * rad * 1.3, y: CGFloat(sin(ang)) * rad * 0.8)
                }
            }
        }
    }
}

struct Avatar: View {
    @EnvironmentObject var store: Store
    let who: Who
    var size: CGFloat = 54
    var body: some View {
        let st = store.statusNow(who)
        let ring = st.map { Color(hex: statusKind($0.kind).hex) } ?? store.color(who)
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(LinearGradient(colors: [store.color(who), store.color(who).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(store.name(who).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(ring, lineWidth: 3).padding(-4))
            if let st {
                Image(systemName: statusKind(st.kind).symbol).font(.system(size: size * 0.24, weight: .bold))
                    .foregroundStyle(.white).frame(width: size * 0.42, height: size * 0.42)
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
                header
                if let mine = store.statusNow(.me) { statusHero(mine, who: .me) } else { askCard }
                if let theirs = store.statusNow(.partner) { statusHero(theirs, who: .partner) }
                tiles
                infoRow
                historyBlock
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStatus) { StatusSheet().environmentObject(store) }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.data.statuses)
        .onAppear { store.location.refresh() }
    }

    // Шапка с аватарами

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Сегодня").font(.system(size: 34, weight: .heavy, design: .rounded))
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: -6) {
                VStack(spacing: 0) { Avatar(who: .me); Text("Я").font(.caption2.weight(.semibold)) }
                VStack(spacing: 0) { Avatar(who: .partner); Text(store.name(.partner)).font(.caption2.weight(.semibold)).lineLimit(1) }
            }
        }
        .padding(.top, 8)
    }

    // Что случилось?

    private var askCard: some View {
        VStack(spacing: 8) {
            Text("Что случилось?")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [store.meColor, store.partnerColor], startPoint: .leading, endPoint: .trailing))
            Text("Поделитесь, чем занимаетесь, — \(store.name(.partner)) увидит сразу")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            ZStack {
                BubbleField(colors: [store.meColor, store.partnerColor, Color(hex: "FFB02E"), Color(hex: "46C2A5")])
                FloatingGlyph(symbol: "face.smiling.inverse", size: 84, color: store.meColor)
            }
            .frame(height: 190)
            Button { showStatus = true; store.tap() } label: {
                Label("Статус", systemImage: "plus").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(LinearGradient(colors: [store.meColor, store.meColor.opacity(0.75)], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .shadow(color: store.meColor.opacity(0.4), radius: 10, y: 6)
            }
            .padding(.horizontal, 28)
        }
        .padding(.vertical, 20).frame(maxWidth: .infinity).card()
    }

    // Большая карточка статуса

    private func statusHero(_ s: StatusItem, who: Who) -> some View {
        let k = statusKind(s.kind)
        let c = Color(hex: k.hex)
        let big = who == .me
        return Button {
            if who == .me { showStatus = true; store.tap() }
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [c, c.opacity(0.55), Color.black.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.10)).frame(width: 220).offset(x: 140, y: -90)
                Circle().fill(.white.opacity(0.08)).frame(width: 140).offset(x: -90, y: -50)
                VStack {
                    HStack {
                        Label("Статус · 24 часа", systemImage: "clock").font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.18), in: Capsule())
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(store.color(who)).frame(width: 10, height: 10)
                            Text(who == .me ? "Я" : store.name(who)).font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.18), in: Capsule())
                    }
                    Spacer()
                    FloatingGlyph(symbol: k.symbol, size: big ? 92 : 64)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.system(size: big ? 30 : 24, weight: .heavy, design: .rounded))
                            let extra = [s.place, s.note].filter { !$0.isEmpty }.joined(separator: " · ")
                            Text(extra.isEmpty ? s.started.agoText : extra + " · " + s.started.agoText)
                                .font(.footnote).opacity(0.85).lineLimit(2)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(.white).padding(16)
            }
            .frame(height: big ? 290 : 200)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: c.opacity(0.4), radius: 16, y: 10)
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    // Быстрые разделы

    private var tiles: some View {
        HStack(spacing: 12) {
            tile("Сон", "moon.stars.fill", "7C6BE0", detail: sleepDetail) { SleepView() }
            tile("Трекер", "chart.bar.fill", "F59E0B", detail: trackerDetail) { TrackerView() }
            tile("Банка", "flask.fill", "46C2A5", detail: jarDetail) { JarView() }
        }
    }

    private func tile<D: View>(_ title: String, _ icon: String, _ hex: String, detail: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [Color(hex: hex), Color(hex: hex).opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color(hex: hex).opacity(0.4), radius: 6, y: 4)
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).card()
        }
        .buttonStyle(.plain)
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
                Label("Между нами", systemImage: "location.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let d = store.distanceKm() {
                    Text(d.kmText).font(.system(size: 26, weight: .heavy, design: .rounded))
                } else {
                    Text(store.p.shareLocation ? "Ждём партнёра" : "Скрыто").font(.headline)
                    if !store.p.shareLocation { Text("Включите в настройках").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
            VStack(alignment: .leading, spacing: 4) {
                Label("Вместе", systemImage: "heart.fill").font(.caption.weight(.semibold)).foregroundStyle(store.partnerColor)
                let days = max(0, Calendar.current.dateComponents([.day], from: store.p.start, to: Date()).day ?? 0)
                Text("\(days)").font(.system(size: 26, weight: .heavy, design: .rounded))
                Text("дней").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    // История статусов

    private var historyBlock: some View {
        VStack(spacing: 8) {
            Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { history.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(history ? 180 : 0))
                    Text("История").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            if history {
                let items = store.data.statuses.sorted { $0.started > $1.started }.prefix(12)
                if items.isEmpty { Text("Статусов пока не было").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(items)) { s in
                    let k = statusKind(s.kind)
                    HStack(spacing: 12) {
                        Image(systemName: k.symbol).foregroundStyle(Color(hex: k.hex)).frame(width: 36, height: 36)
                            .background(Color(hex: k.hex).opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(store.name(s.who)) — \(s.title)").font(.subheadline.weight(.semibold))
                            if !s.note.isEmpty { Text(s.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(s.started.agoText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10).card()
                }
            }
        }
    }
}

func hoursText(_ h: Double) -> String {
    let m = Int((h * 60).rounded())
    return "\(m / 60) ч \(m % 60) мин"
}

// MARK: - Выбор статуса

struct StatusSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: StatusKind?
    @State private var note = ""
    @State private var place = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(statusKinds) { k in
                            let on = picked?.id == k.id
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { picked = k }
                                store.tap()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.symbol).font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Color(hex: k.hex)).frame(height: 28)
                                    Text(k.title).font(.caption2.weight(.medium)).foregroundStyle(.primary)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(on ? Color(hex: k.hex).opacity(0.22) : Pal.card,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(on ? Color(hex: k.hex) : Color.clear, lineWidth: 2))
                                .scaleEffect(on ? 1.04 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    VStack(spacing: 10) {
                        TextField("Где вы? (по желанию)", text: $place)
                            .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        TextField("Пара слов к статусу", text: $note)
                            .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button {
                        if let k = picked { store.setStatus(k, note: note, place: place); dismiss() }
                    } label: {
                        Text("Показать партнёру на 24 часа").bigButton().opacity(picked == nil ? 0.4 : 1)
                    }
                    .disabled(picked == nil)
                    if store.statusNow(.me) != nil {
                        Button("Убрать статус", role: .destructive) { store.clearStatus(); dismiss() }
                    }
                }
                .padding(16)
            }
            .background(ThemeBackground())
            .navigationTitle("Мой статус")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .presentationDetents([.large])
        .onAppear {
            if let s = store.statusNow(.me) {
                picked = statusKinds.first { $0.id == s.kind }
                note = s.note
                place = s.place
            }
        }
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
                        .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                    Text("часов").font(.system(size: size * 0.09)).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = true } }
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
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ForEach(Who.allCases, id: \.self) { w in
                        let e = store.lastSleep(of: w)
                        VStack(spacing: 8) {
                            Text(store.name(w)).font(.caption.weight(.bold)).foregroundStyle(store.color(w))
                            SleepRing(hours: e?.hours, quality: e?.quality ?? 3, color: store.color(w), size: 118)
                            if let e {
                                Text(sleepTitles[min(max(e.quality, 1), 5)]).font(.caption.weight(.bold))
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(Color(hex: sleepHexes[min(max(e.quality, 1), 5)]).opacity(0.2), in: Capsule())
                            } else {
                                Text("нет данных").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16).card()
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
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
                                Text(sleepTitles[q]).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .foregroundStyle(quality == q ? .white : .primary)
                                    .background(quality == q ? Color(hex: sleepHexes[q]) : Color(hex: sleepHexes[q]).opacity(0.14), in: Capsule())
                            }
                            .buttonStyle(.plain)
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
                                Text(shortDay(day)).font(.system(size: 9)).foregroundStyle(.secondary)
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
        .animation(.easeInOut(duration: 0.2), value: quality)
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
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
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
        let total = store.count(c.id, who: nil)
        let st = store.streak(c.id)
        return VStack(spacing: 14) {
            HStack {
                Text(c.emoji).font(.title)
                Text(c.title).font(.title3.weight(.heavy)).foregroundStyle(.white)
                Spacer()
                Text(st > 0 ? "🔥 \(st)" : "").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.white.opacity(st > 0 ? 0.22 : 0), in: Capsule())
            }
            Button {
                bump = c.id
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { store.addTrack(c.id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { bump = nil }
            } label: {
                ZStack {
                    Circle().fill(.white.opacity(0.18)).frame(width: 190, height: 190)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0.7)], center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: 120))
                        .frame(width: 150, height: 150)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
                    Text("\(total)").font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                        .contentTransition(.numericText())
                }
                .scaleEffect(bump == c.id ? 1.1 : 1)
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                ForEach(Who.allCases, id: \.self) { w in
                    HStack(spacing: 6) {
                        Circle().fill(store.color(w)).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 1.5))
                        Text("\(store.name(w)): \(store.count(c.id, who: w))").font(.footnote.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(.white.opacity(0.18), in: Capsule())
                }
                Button { withAnimation { store.undoTrack(c.id) } } label: {
                    Image(systemName: "arrow.uturn.backward").font(.footnote.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 38, height: 34).background(.white.opacity(0.18), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: tint.opacity(0.35), radius: 14, y: 8)
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
