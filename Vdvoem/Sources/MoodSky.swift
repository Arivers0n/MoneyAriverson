import SwiftUI

// MARK: - Настроение: «две луны» и лента дней

func moodOf(_ i: Int) -> JarMood { jarMoods[min(max(i, 0), jarMoods.count - 1)] }

/// Светящийся шар человека: кольцо из цветов его настроений за сутки, внутри фото.
struct MoodOrb: View {
    @EnvironmentObject var store: Store
    let who: Who
    var size: CGFloat = 112

    private var recent: [JarBall] {
        store.data.jar.filter { $0.who == who && Date().timeIntervalSince($0.date) < 86400 }.sorted { $0.date < $1.date }
    }
    private var last: JarBall? { store.data.jar.filter { $0.who == who }.max { $0.date < $1.date } }

    private var ringColors: [Color] {
        if recent.isEmpty { return [Color.gray.opacity(0.35), Color.gray.opacity(0.15), Color.gray.opacity(0.35)] }
        var cs: [Color] = recent.suffix(6).map { Color(hex: moodOf($0.mood).hex) }
        if cs.count == 1 { cs.append(cs[0].opacity(0.55)) }
        cs.append(cs[0])
        return cs
    }

    var body: some View {
        let accent: Color = last.map { Color(hex: moodOf($0.mood).hex) } ?? store.color(who)
        VStack(spacing: 6) {
            LiveTimeline(fps: 24) { date in
                let t = date.timeIntervalSinceReferenceDate
                let phase = who == .me ? 0.0 : 1.7
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [accent.opacity(0.5), accent.opacity(0)], center: .center, startRadius: size * 0.3, endRadius: size * 0.95))
                        .frame(width: size * 1.9, height: size * 1.9)
                        .scaleEffect(1 + 0.05 * CGFloat(sin(t * 1.3 + phase)))
                    Circle()
                        .strokeBorder(AngularGradient(colors: ringColors, center: .center, angle: .degrees(t * 22)), lineWidth: 8)
                        .frame(width: size, height: size)
                    AvatarFace(who: who, size: size - 24)
                    if let l = last {
                        Text(moodOf(l.mood).emoji).font(.system(size: size * 0.2))
                            .frame(width: size * 0.34, height: size * 0.34)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().stroke(accent, lineWidth: 2))
                            .offset(x: size * 0.36, y: size * 0.36)
                    }
                }
                .frame(width: size * 1.25, height: size * 1.25)
            }
            Text(store.name(who)).font(.subheadline.weight(.semibold))
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var caption: String {
        guard let l = last else { return "ещё не отмечал(а)" }
        return moodOf(l.mood).title + " · " + l.date.agoText
    }
}

/// Колонка одного дня: сверху цвета ваших настроений, снизу — партнёра.
struct MoodDayColumn: View {
    let day: Date
    let mine: [Int]
    let theirs: [Int]
    let selected: Bool
    let isToday: Bool

    private func fill(_ ms: [Int]) -> LinearGradient {
        var cs: [Color] = ms.map { Color(hex: moodOf($0).hex) }
        if cs.isEmpty { cs = [Color.gray.opacity(0.14), Color.gray.opacity(0.14)] }
        if cs.count == 1 { cs.append(cs[0].opacity(0.75)) }
        return LinearGradient(colors: cs, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill(mine))
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill(theirs))
            }
            .frame(height: 88)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.primary.opacity(0.7) : Color.clear, lineWidth: 1.5)
                    .padding(-3)
            )
            Text(day.formatted(Date.FormatStyle().locale(ruLocale).day()))
                .font(.system(size: 10, weight: isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(isToday ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(selected ? 1.06 : 1)
        .animation(Motion.spring, value: selected)
    }
}

struct JarView: View {
    @EnvironmentObject var store: Store
    @State private var sel = 1
    @State private var note = ""
    @State private var openDay: Date?

    private let cal = Calendar.current

    private var days: [Date] {
        let today = cal.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    private func moods(_ w: Who, on day: Date) -> [Int] {
        store.data.jar.filter { $0.who == w && cal.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }.map { $0.mood }
    }

    private var sameWave: Bool {
        let a = store.data.jar.filter { $0.who == .me }.max { $0.date < $1.date }
        let b = store.data.jar.filter { $0.who == .partner }.max { $0.date < $1.date }
        guard let a, let b else { return false }
        return a.mood == b.mood && Date().timeIntervalSince(a.date) < 86400 && Date().timeIntervalSince(b.date) < 86400
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                orbs
                picker
                ribbon
                if let d = openDay { dayDetail(d) }
                favorites
                history
            }
            .padding(.horizontal, 16).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(ThemeBackground())
        .navigationTitle("Настроение")
    }

    // MARK: Две луны

    private var orbs: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                Capsule()
                    .fill(LinearGradient(colors: [store.meColor.opacity(0.7), store.partnerColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3).padding(.horizontal, 74).padding(.top, 70)
                    .blur(radius: 0.5)
                HStack(alignment: .top, spacing: 0) {
                    MoodOrb(who: .me)
                    MoodOrb(who: .partner)
                }
            }
            if sameWave {
                Label("Вы на одной волне", systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glass(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(Motion.spring, value: sameWave)
    }

    // MARK: Выбор настроения

    private var picker: some View {
        let m = moodOf(sel)
        let c = Color(hex: m.hex)
        return VStack(spacing: 14) {
            Text("Как вы сейчас?").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [c.opacity(0.5), c.opacity(0)], center: .center, startRadius: 8, endRadius: 90))
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(RadialGradient(colors: [c.opacity(0.6), c], center: .topLeading, startRadius: 4, endRadius: 90))
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5))
                Text(m.emoji).font(.system(size: 50)).id(sel)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            .frame(height: 140)
            Text(m.title).font(.title3.weight(.semibold)).contentTransition(.opacity)
            HStack(spacing: 8) {
                ForEach(jarMoods) { mm in chip(mm) }
            }
            TextField("Пара слов (по желанию)", text: $note)
                .padding(12).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous))
            Button {
                store.addBall(mood: sel, note: note)
                note = ""
            } label: { Text("Отметить").bigButton() }
            .buttonStyle(PressStyle())
        }
        .padding(16).card()
        .animation(Motion.spring, value: sel)
    }

    private func chip(_ mm: JarMood) -> some View {
        let on = sel == mm.id
        let c = Color(hex: mm.hex)
        return Button {
            sel = mm.id
            store.tap()
        } label: {
            VStack(spacing: 4) {
                Text(mm.emoji).font(.system(size: 24))
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(c.opacity(on ? 0.9 : 0.18)))
                    .overlay(Circle().stroke(c, lineWidth: on ? 2 : 0).padding(-3))
                    .scaleEffect(on ? 1.1 : 1)
                Text(mm.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(on ? Color.primary : Color.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Лента дней

    private var ribbon: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Две недели").font(.headline)
                Spacer()
                HStack(spacing: 10) {
                    legend(store.meColor, store.name(.me))
                    legend(store.partnerColor, store.name(.partner))
                }
            }
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { d in
                    MoodDayColumn(day: d, mine: moods(.me, on: d), theirs: moods(.partner, on: d),
                                  selected: openDay.map { cal.isDate($0, inSameDayAs: d) } ?? false,
                                  isToday: cal.isDateInToday(d))
                        .onTapGesture {
                            store.tap()
                            withAnimation(Motion.spring) {
                                if let o = openDay, cal.isDate(o, inSameDayAs: d) { openDay = nil } else { openDay = d }
                            }
                        }
                }
            }
            Text("Верхняя полоска — вы, нижняя — партнёр. Нажмите на день, чтобы посмотреть записи.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).card()
    }

    private func legend(_ c: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func dayDetail(_ d: Date) -> some View {
        let list = store.data.jar.filter { cal.isDate($0.date, inSameDayAs: d) }.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 10) {
            Text(d.formatted(Date.FormatStyle().locale(ruLocale).weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.semibold))
            if list.isEmpty {
                Text("В этот день записей нет").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(list) { b in row(b) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    // MARK: Что чаще всего

    private var favorites: some View {
        HStack(spacing: 12) {
            ForEach(Who.allCases, id: \.self) { w in
                let top = topMood(w)
                VStack(spacing: 8) {
                    AvatarFace(who: w, size: 38)
                    Text(top?.emoji ?? "—").font(.system(size: 30))
                    Text(top?.title ?? "нет данных").font(.footnote.weight(.semibold))
                    Text("чаще всего за 2 недели").font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 14).padding(.horizontal, 8).frame(maxWidth: .infinity).card()
            }
        }
    }

    private func topMood(_ w: Who) -> JarMood? {
        let since = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let list = store.data.jar.filter { $0.who == w && $0.date >= since }
        guard !list.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for b in list { counts[b.mood, default: 0] += 1 }
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return moodOf(best.key)
    }

    // MARK: История

    private func row(_ b: JarBall) -> some View {
        let m = moodOf(b.mood)
        return HStack(spacing: 12) {
            AvatarFace(who: b.who, size: 34)
                .overlay(Circle().stroke(Color(hex: m.hex), lineWidth: 2).padding(-2))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.emoji) \(m.title)").font(.subheadline.weight(.semibold))
                if !b.note.isEmpty { Text(b.note).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(b.date.agoText).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последние записи").font(.headline)
            ForEach(store.data.jar.sorted { $0.date > $1.date }.prefix(10)) { b in
                row(b)
                if b.id != store.data.jar.sorted(by: { $0.date > $1.date }).prefix(10).last?.id { Divider() }
            }
            if store.data.jar.isEmpty { Text("Пока пусто — отметьте первое настроение").font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
