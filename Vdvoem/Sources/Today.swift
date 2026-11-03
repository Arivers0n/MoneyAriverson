import SwiftUI

// MARK: - Экран «Сегодня»

struct TodayView: View {
    @EnvironmentObject var store: Store
    @State private var showStatus = false

    var body: some View {
        Screen {
            statusCard(.partner)
            statusCard(.me)
            distanceCard
            NavigationLink { SleepView() } label: { sleepCard }.buttonStyle(.plain)
            NavigationLink { TrackerView() } label: { trackerCard }.buttonStyle(.plain)
            NavigationLink { JarView() } label: { jarCard }.buttonStyle(.plain)
        }
        .navigationTitle("Сегодня")
        .sheet(isPresented: $showStatus) { StatusSheet().environmentObject(store) }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.data.statuses)
        .onAppear { store.location.refresh() }
    }

    // Статус

    private func statusCard(_ w: Who) -> some View {
        let s = store.statusNow(w)
        let k = s.map { statusKind($0.kind) }
        let tint = k.map { Color(hex: $0.hex) } ?? store.color(w)
        return Button {
            if w == .me { showStatus = true; store.tap() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 56, height: 56)
                    Image(systemName: k?.symbol ?? "plus").font(.system(size: 24, weight: .semibold)).foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.name(w)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(s?.title ?? (w == .me ? "Выбрать статус" : "Статус не задан"))
                        .font(.title3.weight(.bold)).foregroundStyle(.primary)
                    if let s {
                        let extra = [s.place, s.note].filter { !$0.isEmpty }.joined(separator: " · ")
                        Text(extra.isEmpty ? s.started.agoText : extra + " · " + s.started.agoText)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    } else if w == .me {
                        Text("Партнёр увидит его сразу").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if w == .me { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .padding(14).card()
        }
        .buttonStyle(.plain)
    }

    private var distanceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.fill").font(.title2).foregroundStyle(store.meColor)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Между вами").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let d = store.distanceKm() {
                    Text(d.kmText).font(.title3.weight(.bold))
                } else {
                    Text(store.p.shareLocation ? "Ждём геопозицию партнёра" : "Расстояние скрыто")
                        .font(.headline)
                    if !store.p.shareLocation {
                        Text("Включите в Настройки → Пара → Показывать местоположение")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(14).card()
    }

    // Сон

    private var sleepCard: some View {
        let mine = store.lastSleep(of: .me)
        let theirs = store.lastSleep(of: .partner)
        return HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(Color(hex: "7C6BE0")).frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Сон").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    sleepChip(.me, mine)
                    sleepChip(.partner, theirs)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14).card()
    }

    private func sleepChip(_ w: Who, _ e: SleepEntry?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(store.color(w)).frame(width: 8, height: 8)
            if let e {
                Text(hoursText(e.hours)).font(.subheadline.weight(.bold))
            } else {
                Text("—").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // Трекер

    private var trackerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ТРЕКЕР СЕГОДНЯ").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                ForEach(store.data.counters.prefix(4)) { c in
                    VStack(spacing: 4) {
                        Text(c.emoji).font(.title2)
                        Text("\(store.count(c.id, who: nil))").font(.headline.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color(hex: c.hex).opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(14).card()
    }

    // Банка

    private var jarCard: some View {
        let today = store.data.jar.filter { Calendar.current.isDateInToday($0.date) }
        return HStack(spacing: 14) {
            Image(systemName: "flask.fill").font(.title2).foregroundStyle(Color(hex: "46C2A5")).frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Банка настроения").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: -6) {
                    ForEach(today.suffix(8)) { b in
                        Circle().fill(Color(hex: jarMoods[min(b.mood, jarMoods.count - 1)].hex))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Pal.card, lineWidth: 2))
                    }
                    if today.isEmpty { Text("Сегодня шариков ещё нет").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14).card()
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

struct SleepView: View {
    @EnvironmentObject var store: Store
    @State private var bed = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date().addingTimeInterval(-86400)) ?? Date()
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quality = 4
    @State private var manualQuality = false

    private var hours: Double { max(0, wake.timeIntervalSince(bed) / 3600) }

    var body: some View {
        Screen {
            HStack(spacing: 12) {
                ForEach(Who.allCases, id: \.self) { w in
                    let e = store.lastSleep(of: w)
                    VStack(spacing: 6) {
                        Text(store.name(w)).font(.caption.weight(.semibold)).foregroundStyle(store.color(w))
                        if let e {
                            Text(hoursText(e.hours)).font(.headline)
                            Text(sleepTitles[min(max(e.quality, 1), 5)])
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color(hex: sleepHexes[min(max(e.quality, 1), 5)]).opacity(0.2), in: Capsule())
                        } else {
                            Text("нет данных").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16).card()
                }
            }

            SectionTitle("Записать мой сон")
            VStack(spacing: 14) {
                DatePicker("Лёг(ла)", selection: $bed, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Проснулся(ась)", selection: $wake, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Text("Всего").foregroundStyle(.secondary)
                    Spacer()
                    Text(hoursText(hours)).font(.headline)
                }
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { q in
                        Button {
                            quality = q; manualQuality = true; store.tap()
                        } label: {
                            Text(sleepTitles[q]).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(Color(hex: sleepHexes[q]).opacity(quality == q ? 0.3 : 0.1), in: Capsule())
                                .overlay(Capsule().stroke(quality == q ? Color(hex: sleepHexes[q]) : .clear, lineWidth: 1.5))
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

            SectionTitle("Последние 7 дней")
            VStack(spacing: 8) {
                ForEach(lastDays(), id: \.self) { day in
                    HStack(spacing: 10) {
                        Text(shortDay(day)).font(.caption).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                        VStack(spacing: 4) {
                            bar(store.sleep(of: .me, day: day), .me)
                            bar(store.sleep(of: .partner, day: day), .partner)
                        }
                    }
                }
            }
            .padding(16).card()
        }
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

    private func bar(_ e: SleepEntry?, _ w: Who) -> some View {
        GeometryReader { g in
            let frac = min(1, (e?.hours ?? 0) / 12)
            ZStack(alignment: .leading) {
                Capsule().fill(Pal.field)
                if e != nil { Capsule().fill(store.color(w)).frame(width: max(8, g.size.width * frac)) }
            }
        }
        .frame(height: 8)
    }

    private func lastDays() -> [String] {
        (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())!.dayKey }
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
    private let palette = ["38BDF8", "F43F5E", "F59E0B", "A0674B", "8C7BF2", "10B981", "E0457B", "64748B"]

    var body: some View {
        Screen {
            ForEach(store.data.counters) { c in
                let tint = Color(hex: c.hex)
                VStack(spacing: 12) {
                    HStack {
                        Text(c.emoji).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.headline)
                            let st = store.streak(c.id)
                            Text(st > 0 ? "🔥 \(st) дн. подряд" : "Серия начнётся сегодня")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        ForEach(Who.allCases, id: \.self) { w in
                            VStack(spacing: 2) {
                                Text("\(store.count(c.id, who: w))").font(.title2.weight(.bold).monospacedDigit())
                                    .contentTransition(.numericText())
                                Text(store.name(w)).font(.caption2).foregroundStyle(store.color(w)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            withAnimation { store.addTrack(c.id) }
                        } label: {
                            Label("Добавить", systemImage: "plus")
                                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        Button {
                            withAnimation { store.undoTrack(c.id) }
                        } label: {
                            Image(systemName: "arrow.uturn.backward").font(.subheadline.weight(.bold))
                                .frame(width: 48).padding(.vertical, 12)
                                .background(Pal.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14).card()
                .contextMenu {
                    Button("Удалить счётчик", role: .destructive) {
                        store.data.counters.removeAll { $0.id == c.id }
                        store.data.tracks.removeAll { $0.counter == c.id }
                    }
                }
            }
            Button { adding = true } label: {
                Label("Новый счётчик", systemImage: "plus.circle.fill").bigButton()
            }
        }
        .navigationTitle("Трекер")
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.data.tracks.count)
        .sheet(isPresented: $adding) {
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
}

// MARK: - Банка настроения

struct JarView: View {
    @EnvironmentObject var store: Store
    @State private var note = ""

    private var balls: [JarBall] {
        store.data.jar.sorted { $0.date < $1.date }.suffix(60).map { $0 }
    }

    var body: some View {
        Screen {
            jar.frame(height: 300).padding(.top, 8)

            SectionTitle("Бросить шарик")
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(jarMoods) { m in
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                store.addBall(mood: m.id, note: note)
                            }
                            note = ""
                        } label: {
                            VStack(spacing: 4) {
                                Text(m.emoji).font(.system(size: 30))
                                Text(m.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.primary)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color(hex: m.hex).opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("Пара слов (по желанию)", text: $note)
                    .padding(12).background(Pal.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14).card()

            SectionTitle("Последние")
            ForEach(store.data.jar.sorted { $0.date > $1.date }.prefix(15)) { b in
                let m = jarMoods[min(b.mood, jarMoods.count - 1)]
                HStack(spacing: 12) {
                    Text(m.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.name(b.who)) — \(m.title)").font(.subheadline.weight(.semibold))
                        if !b.note.isEmpty { Text(b.note).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(b.date.agoText).font(.caption).foregroundStyle(.secondary)
                }
                .padding(12).card()
            }
        }
        .navigationTitle("Банка настроения")
    }

    private var jar: some View {
        GeometryReader { g in
            let w = g.size.width
            let jarW = min(w - 40, 300)
            let r: CGFloat = 17
            let perRow = max(1, Int((jarW - 30) / (r * 2)))
            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Pal.card)
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 2)
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    ForEach(Array(balls.enumerated()), id: \.element.id) { i, b in
                        let row = i / perRow
                        let col = i % perRow
                        let xOff: CGFloat = row % 2 == 0 ? 0 : r
                        let jitter = CGFloat(Int(b.id.uuid.0) % 7) - 3
                        Circle()
                            .fill(Color(hex: jarMoods[min(b.mood, jarMoods.count - 1)].hex))
                            .overlay(Circle().fill(.white.opacity(0.28)).frame(width: r * 0.7).offset(x: -r * 0.25, y: -r * 0.3))
                            .frame(width: r * 2 - 2, height: r * 2 - 2)
                            .offset(x: 14 + xOff + CGFloat(col) * r * 2 + jitter * 0.4,
                                    y: -(12 + CGFloat(row) * (r * 1.8)))
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                if balls.isEmpty {
                    Text("Банка пуста").foregroundStyle(.secondary)
                }
            }
            .frame(width: jarW, height: g.size.height)
            .frame(maxWidth: .infinity)
        }
    }
}
