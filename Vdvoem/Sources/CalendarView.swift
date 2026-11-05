import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var selected = Date()
    @State private var adding = false

    private var cal: Calendar { Calendar.ru }
    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    private func days() -> [Date?] {
        let c = cal
        guard let start = c.date(from: c.dateComponents([.year, .month], from: month)),
              let range = c.range(of: .day, in: .month, for: start) else { return [] }
        let offset = (c.component(.weekday, from: start) - c.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: offset)
        for d in range { out.append(c.date(byAdding: .day, value: d - 1, to: start)) }
        return out
    }

    private func shift(_ n: Int) {
        if let d = cal.date(byAdding: .month, value: n, to: month) { month = d }
        store.tap()
    }

    var body: some View {
        Screen {
            VStack(spacing: 10) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").padding(8) }
                    Spacer()
                    Text(month.formatted(Date.FormatStyle().locale(ruLocale).month(.wide).year()).capitalized).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").padding(8) }
                }
                HStack {
                    ForEach(weekdays, id: \.self) {
                        Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                let cells = days()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                    ForEach(cells.indices, id: \.self) { i in
                        if let d = cells[i] { dayCell(d) } else { Color.clear.frame(height: 42) }
                    }
                }
            }
            .padding(14).card()

            SectionTitle(selected.formatted(Date.FormatStyle().locale(ruLocale).weekday(.wide).day().month(.wide)).capitalized)
            let evs = store.events(on: selected)
            let dueTasks = store.data.tasks.filter { t in
                guard let d = t.due, !t.done else { return false }
                return cal.isDate(d, inSameDayAs: selected)
            }
            if evs.isEmpty && dueTasks.isEmpty {
                Text("В этот день ничего не запланировано")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24).card()
            }
            ForEach(evs) { e in
                HStack(spacing: 12) {
                    Text(e.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.body.weight(.medium))
                        Text(e.yearly ? "каждый год" : e.date.formatted(Date.FormatStyle().locale(ruLocale).hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.data.events.contains(where: { $0.id == e.id }) {
                        Button(role: .destructive) { store.data.events.removeAll { $0.id == e.id } } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14).card()
            }
            ForEach(dueTasks) { t in
                HStack(spacing: 12) {
                    Image(systemName: "checklist").foregroundStyle(store.color(t.owner))
                    Text(t.title).font(.body.weight(.medium))
                    Spacer()
                    Chip(text: "задача", color: store.color(t.owner))
                }
                .padding(14).card()
            }
        }
        .navigationTitle("Календарь")
        .pairToolbar(scope: false, add: { adding = true })
        .sheet(isPresented: $adding) { AddEventSheet(date: selected) }
    }

    private func dayCell(_ d: Date) -> some View {
        let isSel = cal.isDate(d, inSameDayAs: selected)
        let isToday = cal.isDateInToday(d)
        let has = !store.events(on: d).isEmpty
        let hasTask = store.data.tasks.contains { t in
            guard let due = t.due, !t.done else { return false }
            return cal.isDate(due, inSameDayAs: d)
        }
        return Button { selected = d; store.tap() } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: d))")
                    .font(.body.weight(isToday ? .semibold : .regular))
                    .foregroundStyle(isSel ? Pal.bg : (isToday ? store.meColor : Color.primary))
                HStack(spacing: 3) {
                    if has { Circle().fill(isSel ? Pal.bg : store.partnerColor).frame(width: 5, height: 5) }
                    if hasTask { Circle().fill(isSel ? Pal.bg : store.meColor).frame(width: 5, height: 5) }
                    if !has && !hasTask { Color.clear.frame(width: 5, height: 5) }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(isSel ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: min(store.radius, 16), style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AddEventSheet: View {
    @EnvironmentObject var store: Store
    @State var date: Date
    @State private var title = ""
    @State private var emoji = "📌"
    @State private var yearly = false
    @State private var remind = true
    private let emojis = ["📌", "🎂", "💞", "🍽️", "✈️", "🎬", "🎁", "🏠", "🏋️", "👨‍👩‍👧"]

    var body: some View {
        FormSheet(title: "Новое событие", canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            Section {
                TextField("Название", text: $title)
                DatePicker("Когда", selection: $date)
                Toggle("Повторять каждый год", isOn: $yearly)
                if store.p.notifications { Toggle("Напомнить", isOn: $remind) }
            }
            Section("Значок") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.title)
                                .padding(8)
                                .background(e == emoji ? store.meColor.opacity(0.25) : Color.clear, in: Circle())
                                .onTapGesture { emoji = e }
                        }
                    }
                }
            }
        }
    }

    private func save() {
        let e = EventItem(title: title.trimmingCharacters(in: .whitespaces), date: date, emoji: emoji, yearly: yearly)
        store.data.events.append(e)
        if store.p.notifications && remind { Notifier.schedule(id: e.id.uuidString, title: e.emoji + " " + e.title, body: "Скоро", at: date) }
        store.success()
    }
}
