import SwiftUI

struct TasksView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false

    var body: some View {
        let all = store.data.tasks
        let open = all.filter { !$0.done }
        let free = open.filter { $0.owner == nil }
        let mine = open.filter { $0.owner == .me }
        let theirs = open.filter { $0.owner == .partner }
        let done = all.filter { t in
            guard t.done else { return false }
            if store.scope == .we { return true }
            return store.visible(t.owner)
        }

        Screen {
            if all.isEmpty {
                EmptyState(icon: "checklist", title: "Список дел на двоих",
                           text: "Пишите, что нужно сделать. Любой берёт задачу себе — или ставит её партнёру.",
                           action: "Добавить задачу", onTap: { adding = true },
                           hint: "никто никому не начальник — задачу можно вернуть")
            } else {
                if store.scope == .we { group("Свободные", free, nil) }
                if store.scope != .partner { group(store.name(.me), mine, .me) }
                if store.scope != .me { group(store.name(.partner), theirs, .partner) }
                group("Готово", done, nil, muted: true)
                if free.isEmpty && mine.isEmpty && theirs.isEmpty && done.isEmpty {
                    EmptyState(icon: "tray", title: "Здесь пусто", text: "Для этого фильтра задач нет.")
                }
            }
        }
        // Задача, которую отметили или передали, плавно переезжает в другую группу, а не перескакивает
        .animation(Motion.spring, value: store.data.tasks)
        .navigationTitle("Задачи")
        .pairToolbar(add: { adding = true })
        .sheet(isPresented: $adding) { AddTaskSheet() }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [TaskItem], _ who: Who?, muted: Bool = false) -> some View {
        if !items.isEmpty {
            SectionTitle("\(title) · \(items.count)", color: muted ? .secondary : store.color(who))
            ForEach(items) { t in
                TaskRow(t: store.bind(\.tasks, t), showOwner: muted)
            }
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    @Binding var t: TaskItem
    /// В группах по человеку имя уже в заголовке; показываем его только там, где группа смешанная.
    var showOwner = true

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(Motion.spring) { t.done.toggle() }
                if t.done { store.success() } else { store.tap() }
            } label: {
                DrawnCheck(done: t.done, color: store.color(t.owner ?? .me), size: 26)
            }
            .buttonStyle(PressStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text(t.title).font(.body.weight(.medium))
                    .strikethrough(t.done).foregroundStyle(t.done ? .secondary : .primary)
                HStack(spacing: 6) {
                    if showOwner {
                        if let o = t.owner { Chip(text: store.name(o), color: store.color(o)) }
                        else { Chip(text: "Свободная") }
                    }
                    if let d = t.due {
                        Label(d.formatted(Date.FormatStyle().locale(ruLocale).day().month(.abbreviated)), systemImage: "calendar")
                            .font(.caption).foregroundStyle(d < Date() && !t.done ? Color.red : Color.secondary)
                    }
                    if t.priority > 0 {
                        Text(t.priority == 1 ? "Важная" : "Срочная").font(.caption.weight(.medium)).foregroundStyle(.orange)
                    }
                }
                if !t.note.isEmpty { Text(t.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)

            Menu {
                if t.owner != .me { Button("Взять себе", systemImage: "hand.raised") { t.owner = .me } }
                if t.owner != .partner { Button("Поставить: \(store.name(.partner))", systemImage: "arrowshape.turn.up.right") { t.owner = .partner } }
                if t.owner != nil { Button("Вернуть в свободные", systemImage: "arrow.uturn.backward") { t.owner = nil } }
                Button("Удалить", systemImage: "trash", role: .destructive) {
                    let id = t.id
                    store.data.tasks.removeAll { $0.id == id }
                }
            } label: {
                Image(systemName: "ellipsis").padding(10).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .card()
    }
}

struct AddTaskSheet: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var note = ""
    @State private var owner: Who? = nil
    @State private var hasDue = false
    @State private var due = Date()
    @State private var priority = 0

    var body: some View {
        FormSheet(title: "Новая задача", canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            Section {
                TextField("Что нужно сделать?", text: $title)
                TextField("Заметка", text: $note, axis: .vertical)
            }
            Section("Кому") {
                Picker("Исполнитель", selection: $owner) {
                    Text("Свободная").tag(Who?.none)
                    Text(store.name(.me)).tag(Who?.some(.me))
                    Text(store.name(.partner)).tag(Who?.some(.partner))
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Срок", isOn: $hasDue)
                if hasDue { DatePicker("Когда", selection: $due) }
                Picker("Важность", selection: $priority) {
                    Text("Обычная").tag(0); Text("Важная").tag(1); Text("Срочная").tag(2)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func save() {
        let t = TaskItem(title: title.trimmingCharacters(in: .whitespaces), note: note, owner: owner,
                         due: hasDue ? due : nil, priority: priority)
        store.data.tasks.insert(t, at: 0)
        if hasDue, store.p.notifications {
            Notifier.schedule(id: t.id.uuidString, title: "Задача", body: t.title, at: due)
        }
        store.success()
    }
}
