import SwiftUI
import SwiftData

struct LifeView: View {
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var tasks = TaskStore.shared
    @Query(sort: \ShopItem.created) private var shop: [ShopItem]
    @Query(sort: \Habit.created) private var habits: [Habit]
    @Query(sort: \LifeGoal.created) private var goals: [LifeGoal]

    @State private var newShop = ""
    @State private var newTask = ""
    @State private var habitEdit: HabitTarget?
    @State private var goalEdit: LifeGoalTarget?
    @FocusState private var shopFocus: Bool
    @FocusState private var taskFocus: Bool

    let sections = ["Задачи", "Покупки", "Привычки", "Цели"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Дела").font(.system(size: 32, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    SectionSwitcher(titles: sections, selection: $router.life)
                    switch router.life {
                    case 1: shopSection
                    case 2: habitsSection
                    case 3: goalsSection
                    default: tasksSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !shopFocus && !taskFocus {
                    VoiceDock(onScan: { router.tab = 0; router.scanRequest += 1 }, onAdd: addAction)
                }
            }
            .sheet(item: $habitEdit) { t in HabitForm(habit: t.habit) }
            .sheet(item: $goalEdit) { t in LifeGoalForm(goal: t.goal) }
            .task { tasks.refresh() }
            .refreshable { tasks.refresh() }
        }
    }

    private func addAction() {
        switch router.life {
        case 1: shopFocus = true
        case 2: habitEdit = HabitTarget(habit: nil)
        case 3: goalEdit = LifeGoalTarget(goal: nil)
        default: taskFocus = true
        }
    }

    // MARK: Задачи

    @ViewBuilder private var tasksSection: some View {
        if !tasks.authorized {
            VStack(alignment: .leading, spacing: 10) {
                Text("Задачи хранятся в «Напоминаниях» Apple — с их уведомлениями, Siri и виджетами.")
                    .foregroundStyle(.secondary)
                Button(tasks.denied ? "Доступ выключен: Настройки → Лад → Напоминания" : "Разрешить доступ к Напоминаниям") {
                    Task { await tasks.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tasks.denied)
            }
        } else {
            AddField(placeholder: "Новая задача", text: $newTask, focus: $taskFocus) {
                let t = newTask.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                _ = tasks.add(title: t, due: nil, hasTime: false)
                newTask = ""
            }
            if tasks.items.isEmpty {
                EmptyLine(text: "Пусто. Скажите голосом: «завтра в 10 позвонить в банк» или «в субботу забрать посылку».")
            }
            let overdueOrToday = tasks.today
            if !overdueOrToday.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    BlockTitle(text: "Сегодня", symbol: "sun.max")
                    ForEach(overdueOrToday) { t in TaskRow(item: t) }
                }
            }
            if !tasks.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    BlockTitle(text: "На неделе", symbol: "calendar")
                    ForEach(tasks.upcoming) { t in TaskRow(item: t) }
                }
            }
            let noDate = tasks.items.filter { $0.due == nil }
            if !noDate.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    BlockTitle(text: "Без срока", symbol: "tray")
                    ForEach(noDate) { t in TaskRow(item: t) }
                }
            }
        }
    }

    // MARK: Покупки

    @ViewBuilder private var shopSection: some View {
        AddField(placeholder: "Что купить", text: $newShop, focus: $shopFocus) {
            let t = newShop.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return }
            ctx.insert(ShopItem(name: t.capitalizedFirst))
            try? ctx.save()
            newShop = ""
            shopFocus = true
        }
        let left = shop.filter { !$0.done }, bought = shop.filter { $0.done }
        if shop.isEmpty {
            EmptyLine(text: "Список пуст. Скажите: «купить молоко, хлеб и яйца» — и всё появится здесь.")
        }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(left) { s in ShopRow(item: s) }
        }
        if !bought.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BlockTitle(text: "Куплено · \(bought.count)", symbol: "checkmark")
                    Spacer()
                    Button("Записать трату") { router.show(.newTx) }.font(.subheadline.weight(.semibold))
                    Button("Очистить") {
                        for b in bought { ctx.delete(b) }
                        try? ctx.save()
                    }
                    .font(.subheadline).foregroundStyle(.secondary).padding(.leading, 8)
                }
                ForEach(bought) { s in ShopRow(item: s) }
            }
        }
    }

    // MARK: Привычки

    @ViewBuilder private var habitsSection: some View {
        if habits.isEmpty {
            EmptyLine(text: "Добавьте привычку: зал, вода, чтение, без сигарет. Отмечайте касанием или голосом: «сходил в зал».")
        }
        ForEach(habits) { h in
            HabitRow(habit: h) { habitEdit = HabitTarget(habit: h) }
        }
        Button { habitEdit = HabitTarget(habit: nil) } label: { Label("Новая привычка", systemImage: "plus") }
            .font(.subheadline.weight(.semibold))
    }

    // MARK: Цели

    @ViewBuilder private var goalsSection: some View {
        if goals.isEmpty {
            EmptyLine(text: "Большие цели: права, магистратура, ремонт, переезд. Разбейте на шаги и отмечайте прогресс. Денежные копилки — в Кошельке → Планы.")
        }
        ForEach(goals) { g in
            Button { goalEdit = LifeGoalTarget(goal: g) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(g.name).font(.body.weight(.semibold))
                        Spacer()
                        Text("\(Int((g.progress * 100).rounded()))%").foregroundStyle(.secondary)
                    }
                    Bar(value: g.progress, color: Color(hex: g.hex), height: 6)
                    let st = g.steps
                    HStack {
                        Text(st.isEmpty ? "Добавьте шаги" : "\(st.filter { $0.done }.count) из \(st.count) шагов")
                        if let d = g.deadline { Text("· до \(DF.short(d))") }
                        Spacer()
                        if let next = st.first(where: { !$0.done }) { Text("Далее: \(next.title)").lineLimit(1) }
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        Button { goalEdit = LifeGoalTarget(goal: nil) } label: { Label("Новая цель", systemImage: "plus") }
            .font(.subheadline.weight(.semibold))
    }
}

// MARK: - Элементы

struct HabitTarget: Identifiable { let id = UUID(); let habit: Habit? }
struct LifeGoalTarget: Identifiable { let id = UUID(); let goal: LifeGoal? }

struct SectionSwitcher: View {
    let titles: [String]
    @Binding var selection: Int
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(titles.indices, id: \.self) { i in
                    Button { withAnimation(.snappy) { selection = i } } label: {
                        Text(titles[i])
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(selection == i ? Color(.systemBackground) : Color.primary)
                            .background(selection == i ? Theme.ink : Theme.soft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct AddField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "plus").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .focused(focus)
                .submitLabel(.done)
                .onSubmit(onSubmit)
        }
        .padding(12)
        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyLine: View {
    let text: String
    var body: some View { Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

struct ShopRow: View {
    @Environment(\.modelContext) private var ctx
    let item: ShopItem
    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { item.done.toggle() }
                try? ctx.save()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(item.done ? Theme.inc : Color.secondary)
                    Text(item.name).strikethrough(item.done).foregroundStyle(item.done ? Color.secondary : Color.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { ctx.delete(item); try? ctx.save() } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary) }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

struct HabitRow: View {
    @Environment(\.modelContext) private var ctx
    let habit: Habit
    let onEdit: () -> Void
    var body: some View {
        let color = Color(hex: habit.hex)
        let week = (0..<7).reversed().map { Date().addingDays(-$0) }
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    SoftIcon(symbol: habit.symbol, color: color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name).font(.body.weight(.medium)).lineLimit(1)
                        Text(habit.streak > 0 ? "Серия \(habit.streak) \(plural(habit.streak, "день", "дня", "дней"))" : "Начните сегодня")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 5) {
                ForEach(week, id: \.self) { d in
                    let on = habit.isDone(d)
                    Button {
                        habit.toggle(d); try? ctx.save()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 3) {
                            Text(DF.s(d, "EEEEE")).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            Circle().fill(on ? color : color.opacity(0.12)).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(d.sameDay(Date()) ? color : Color.clear, lineWidth: 1.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Формы

struct HabitForm: View {
    let habit: Habit?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var habits: [Habit]
    @State private var name = ""
    @State private var symbol = "figure.run"
    @State private var hex = Theme.palette[0]
    @State private var confirmDelete = false

    let symbols = ["figure.run", "dumbbell.fill", "drop.fill", "book.fill", "bed.double.fill", "leaf.fill", "brain.head.profile",
                   "nosign", "fork.knife", "figure.walk", "pills.fill", "graduationcap.fill", "pencil", "music.note", "heart.fill", "star.fill"]
    let presets: [(String, String)] = [("Зал", "dumbbell.fill"), ("Вода 2 л", "drop.fill"), ("Чтение", "book.fill"), ("Сон до 23:00", "bed.double.fill"),
                                       ("Без сигарет", "nosign"), ("10 000 шагов", "figure.walk"), ("Английский", "graduationcap.fill")]

    var body: some View {
        NavigationStack {
            Form {
                if habit == nil {
                    Section {
                        FlowLayout {
                            ForEach(presets.indices, id: \.self) { i in
                                Chip(title: presets[i].0, selected: name == presets[i].0) { name = presets[i].0; symbol = presets[i].1 }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section { TextField("Название", text: $name) }
                Section("Значок") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(symbols, id: \.self) { s in
                            Image(systemName: s)
                                .font(.body)
                                .frame(width: 34, height: 34)
                                .foregroundStyle(symbol == s ? Color.white : Color(hex: hex))
                                .background(symbol == s ? Color(hex: hex) : Color(hex: hex).opacity(0.12), in: Circle())
                                .onTapGesture { symbol = s }
                        }
                    }
                }
                Section("Цвет") {
                    HStack {
                        ForEach(Theme.palette, id: \.self) { h in
                            Circle().fill(Color(hex: h)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: hex == h ? 2.5 : 0))
                                .onTapGesture { hex = h }
                        }
                    }
                }
                if habit != nil { Section { Button("Удалить привычку", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(habit == nil ? "Новая привычка" : "Привычка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        if let h = habit { h.name = n; h.symbol = symbol; h.hex = hex }
                        else { ctx.insert(Habit(name: n, symbol: symbol, hex: hex)) }
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Удалить привычку и её историю?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let h = habit { ctx.delete(h); try? ctx.save() }; dismiss() }
            }
            .onAppear {
                if let h = habit { name = h.name; symbol = h.symbol; hex = h.hex }
                else { hex = Theme.palette[habits.count % Theme.palette.count] }
            }
        }
    }
}

struct LifeGoalForm: View {
    let goal: LifeGoal?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [LifeGoal]
    @State private var name = ""
    @State private var note = ""
    @State private var hasDeadline = false
    @State private var deadline = Date().addingMonths(3)
    @State private var steps: [GoalStep] = []
    @State private var newStep = ""
    @State private var hex = Theme.palette[0]
    @State private var confirmDelete = false
    @State private var thinking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Цель, например «Получить права»", text: $name)
                    TextField("Зачем это мне (необязательно)", text: $note, axis: .vertical)
                    Toggle("К определённой дате", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Дата", selection: $deadline, displayedComponents: .date) }
                }
                Section {
                    ForEach($steps) { $s in
                        HStack {
                            Button { s.done.toggle() } label: {
                                Image(systemName: s.done ? "checkmark.circle.fill" : "circle").foregroundStyle(s.done ? Theme.inc : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            TextField("Шаг", text: $s.title)
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    HStack {
                        TextField("Новый шаг", text: $newStep).onSubmit(addStep)
                        Button("Добавить", action: addStep).disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if Keychain.hasKey {
                        Button {
                            suggestSteps()
                        } label: {
                            HStack {
                                if thinking { ProgressView() } else { Image(systemName: "sparkles") }
                                Text(thinking ? "Claude думает…" : "Разбить на шаги с Claude")
                            }
                        }
                        .disabled(thinking || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: { Text("Шаги") }
                if goal != nil { Section { Button("Удалить цель", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(goal == nil ? "Новая цель" : "Цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save) }
            }
            .confirmationDialog("Удалить цель?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let g = goal { ctx.delete(g); try? ctx.save() }; dismiss() }
            }
            .onAppear {
                if let g = goal {
                    name = g.name; note = g.note; hasDeadline = g.deadline != nil; deadline = g.deadline ?? deadline; steps = g.steps; hex = g.hex
                } else { hex = Theme.palette[goals.count % Theme.palette.count] }
            }
        }
    }

    private func addStep() {
        let t = newStep.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        steps.append(GoalStep(title: t))
        newStep = ""
    }

    private func suggestSteps() {
        thinking = true
        let prompt = """
        Разбей личную цель на 4–7 конкретных шагов по порядку, каждый — короткое действие (до 60 знаков), по-русски. Учитывай, что человек живёт в России.
        Цель: «\(name)». \(note.isEmpty ? "" : "Контекст: \(note).") \(hasDeadline ? "Срок: \(DF.long(deadline))." : "")
        Ответь только JSON-массивом строк.
        """
        Task {
            defer { thinking = false }
            if let arr = try? await Claude.json(prompt) as? [String] {
                steps.append(contentsOf: arr.prefix(8).map { GoalStep(title: String($0.prefix(80))) })
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let g = goal ?? LifeGoal(name: n, deadline: nil, hex: hex)
        g.name = n; g.note = note; g.deadline = hasDeadline ? deadline.noon : nil; g.steps = steps; g.hex = hex
        if goal == nil { ctx.insert(g) }
        try? ctx.save()
        dismiss()
    }
}
