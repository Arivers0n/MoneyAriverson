import SwiftUI
import SwiftData

// MARK: - Операция вручную

struct TxForm: View {
    let tx: Tx?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    @Query(sort: \Account.created) private var accs: [Account]
    @AppStorage("lastAcc") private var lastAcc = ""

    @State private var kind: TxKind = .exp
    @State private var amount = ""
    @State private var cat = "food"
    @State private var acc: UUID?
    @State private var to: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var err: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $kind) {
                        Text("Расход").tag(TxKind.exp)
                        Text("Доход").tag(TxKind.inc)
                        if accs.count >= 2 { Text("Перевод").tag(TxKind.tr) }
                    }
                    .pickerStyle(.segmented)
                    AmountField(text: $amount)
                }
                if kind != .tr {
                    Section("Категория") {
                        FlowLayout {
                            ForEach(Catalog.list(kind)) { c in
                                Chip(title: c.name, color: c.color, selected: cat == c.id) { cat = c.id }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !accs.isEmpty {
                    Section(kind == .tr ? "Откуда" : "Счёт") {
                        FlowLayout {
                            ForEach(accs) { a in Chip(title: a.name, color: Color(hex: a.hex), selected: acc == a.uid) { acc = a.uid } }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if kind == .tr {
                    Section("Куда") {
                        FlowLayout {
                            ForEach(accs.filter { $0.uid != acc }) { a in Chip(title: a.name, color: Color(hex: a.hex), selected: to == a.uid) { to = a.uid } }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                    TextField("Заметка", text: $note)
                }
                if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
                if tx != nil {
                    Section {
                        Button("Удалить операцию", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(tx == nil ? "Новая операция" : "Операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).fontWeight(.semibold) }
            }
            .confirmationDialog("Удалить операцию?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let tx { ctx.delete(tx); try? ctx.save() }
                    dismiss()
                }
            }
            .onChange(of: kind) { _, k in if k != .tr { cat = Catalog.valid(cat, for: k) } }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let t = tx {
            kind = t.kind; amount = Fmt.input(t.amount); cat = t.cat; acc = t.accID; to = t.toID; date = t.date; note = t.note
        } else {
            acc = accs.first { $0.uid.uuidString == lastAcc }?.uid ?? accs.first?.uid
        }
    }

    private func save() {
        guard let v = parseAmount(amount), v > 0 else { err = "Введите сумму больше нуля."; return }
        if kind == .tr && (acc == nil || to == nil || acc == to) { err = "Выберите два разных счёта."; return }
        if let t = tx {
            t.kind = kind; t.amount = v; t.cat = kind == .tr ? "" : cat; t.accID = acc; t.toID = kind == .tr ? to : nil
            t.date = date.noon; t.note = note
        } else {
            ctx.insert(Tx(kind: kind, amount: v, cat: kind == .tr ? "" : cat, note: note, date: date, accID: acc, toID: kind == .tr ? to : nil))
        }
        if let acc { lastAcc = acc.uuidString }
        try? ctx.save()
        dismiss()
        router.say(tx == nil ? "Добавлено" : "Сохранено")
    }
}

// MARK: - Счёт

struct AccountForm: View {
    let account: Account?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accs: [Account]
    @State private var name = ""
    @State private var start = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if account == nil {
                    Section {
                        FlowLayout {
                            ForEach(["Карта", "Наличные", "Накопительный", "Кредитка"], id: \.self) { p in
                                Chip(title: p, selected: name == p) { name = p }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    TextField("Название", text: $name)
                    TextField("Сколько на нём сейчас, ₽", text: $start).keyboardType(.numbersAndPunctuation)
                } footer: { Text("Баланс дальше считается сам по операциям с этим счётом.") }
                if account != nil {
                    Section { Button("Удалить счёт", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(account == nil ? "Новый счёт" : "Счёт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        let s = parseAmount(start) ?? 0
                        if let a = account { a.name = n; a.start = s }
                        else { ctx.insert(Account(name: n, start: s, hex: Theme.palette[accs.count % Theme.palette.count])) }
                        try? ctx.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Операции останутся, но без счёта. Удалить?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let a = account { ctx.delete(a); try? ctx.save() }
                    dismiss()
                }
            }
            .onAppear {
                if let a = account { name = a.name; start = Fmt.input(a.start) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Голосом

struct VoiceSheet: View {
    let autoStart: Bool
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechRecognizer()
    @State private var working = false
    @State private var err: String?
    @FocusState private var editing: Bool

    let examples = [
        "Вчера посидели в кафе на 2300, домой на такси за 400",
        "Пришла зарплата 85 тысяч, сразу отложил пятёрку на отпуск",
        "Заплатил по кредиту в Сбер, восемь с половиной",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(speech.isRecording ? "Говорите, я слушаю…" : (speech.transcript.isEmpty ? "Нажмите и расскажите, что было с деньгами" : "Проверьте текст и нажмите «Разобрать»"))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    micButton

                    ZStack(alignment: .topLeading) {
                        if speech.transcript.isEmpty {
                            Text("Например: утром заправился где-то на полторы тыщи, потом в пятёрочке взял продуктов рублей на восемьсот")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5).padding(.vertical, 8)
                        }
                        TextEditor(text: $speech.transcript)
                            .focused($editing)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                    }
                    .font(.title3)
                    .padding(10)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let e = speech.error ?? err { Text(e).font(.subheadline).foregroundStyle(Theme.exp) }

                    Button(action: parse) {
                        HStack {
                            if working { ProgressView().tint(Theme.onAccent) }
                            Text(working ? "Claude разбирает…" : "Разобрать")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)

                    if !Keychain.hasKey {
                        Text("Без ключа Claude API работает простой разбор: «кофе 250, такси 400». Чтобы понимать разговорную речь, добавьте ключ в настройках.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ЧТО МОЖНО СКАЗАТЬ").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
                        ForEach(examples, id: \.self) { e in
                            Button { speech.transcript = e } label: {
                                Text(e).font(.subheadline).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Голосом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { speech.stop(); dismiss() } }
            }
            .task {
                if autoStart { await speech.start() }
            }
            .onDisappear { speech.stop() }
        }
    }

    private var micButton: some View {
        Button {
            editing = false
            Task { await speech.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: 150, height: 150)
                    .scaleEffect(speech.isRecording ? 1 + CGFloat(speech.level) * 0.5 : 0.85)
                    .animation(.easeOut(duration: 0.12), value: speech.level)
                Circle()
                    .fill(speech.isRecording ? Theme.exp : Theme.accent)
                    .frame(width: 104, height: 104)
                    .shadow(color: (speech.isRecording ? Theme.exp : Theme.accent).opacity(0.35), radius: 14, y: 6)
                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isRecording ? "Остановить запись" : "Начать запись")
    }

    private func parse() {
        speech.stop()
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        working = true; err = nil
        Task {
            defer { working = false }
            do {
                let items = try await Brain.parseSpeech(text, ctx: ctx)
                if items.isEmpty { err = "Не нашёл ни одной суммы. Попробуйте сказать иначе."; return }
                router.show(.review(ReviewPayload(items: items, subtitle: "Из вашего рассказа")))
            } catch {
                let local = LocalParser.parse(text)
                if local.isEmpty { err = error.localizedDescription }
                else { router.show(.review(ReviewPayload(items: local, subtitle: "Разобрал без Claude — проверьте категории"))) }
            }
        }
    }
}

// MARK: - Проверка распознанного

struct ReviewSheet: View {
    let payload: ReviewPayload
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.created) private var accs: [Account]
    @Query private var debts: [Debt]
    @Query private var goals: [Goal]
    @AppStorage("lastAcc") private var lastAcc = ""
    @State private var items: [ParsedItem] = []
    @State private var acc: UUID?

    var onCount: Int { items.filter { $0.on }.count }

    var body: some View {
        NavigationStack {
            List {
                if !payload.subtitle.isEmpty {
                    Section { Text(payload.subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                if !accs.isEmpty {
                    Section("Счёт") {
                        FlowLayout {
                            ForEach(accs) { a in Chip(title: a.name, color: Color(hex: a.hex), selected: acc == a.uid) { acc = a.uid } }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    ForEach($items) { $it in
                        ReviewRow(item: $it, debts: debts, goals: goals)
                    }
                }
            }
            .navigationTitle(items.count == 1 ? "Проверьте" : "Проверьте \(items.count) \(plural(items.count, "запись", "записи", "записей"))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(onCount == 0 ? "Ничего не выбрано" : "Добавить \(onCount)")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(onCount == 0)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
            }
            .onAppear {
                if items.isEmpty { items = payload.items }
                acc = accs.first { $0.uid.uuidString == lastAcc }?.uid ?? accs.first?.uid
            }
        }
    }

    private func save() {
        for i in items.indices { items[i].amount = parseAmount(items[i].amountText) ?? 0 }
        let res = Saver.apply(items, account: acc, ctx: ctx)
        if let acc { lastAcc = acc.uuidString }
        router.finishSave(res)
    }
}

struct ReviewRow: View {
    @Binding var item: ParsedItem
    let debts: [Debt]
    let goals: [Goal]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { item.on.toggle() } label: {
                Image(systemName: item.on ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(item.on ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                switch item.kind {
                case .debt: debtHeader
                case .goal: goalHeader
                case .tx: categoryMenu
                }
                HStack {
                    DatePicker("", selection: $item.date, displayedComponents: .date).labelsHidden()
                    Spacer()
                    TextField("0", text: $item.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.headline)
                        .frame(maxWidth: 120)
                    Text("₽").foregroundStyle(.secondary)
                }
                if item.kind == .tx {
                    TextField("Заметка", text: $item.note).font(.subheadline)
                }
            }
        }
        .opacity(item.on ? 1 : 0.5)
        .padding(.vertical, 4)
    }

    private var categoryMenu: some View {
        Menu {
            Section("Расходы") {
                ForEach(Catalog.expense) { c in Button(c.name) { item.type = .exp; item.cat = c.id } }
            }
            Section("Доходы") {
                ForEach(Catalog.income) { c in Button(c.name) { item.type = .inc; item.cat = c.id } }
            }
        } label: {
            let c = Catalog.cat(item.cat)
            HStack(spacing: 8) {
                IconBadge(symbol: c.symbol, color: c.color, size: 28)
                Text(c.name).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                Text(item.type == .inc ? "доход" : "расход").font(.caption).foregroundStyle(item.type == .inc ? Theme.inc : Color.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var debtHeader: some View {
        if let d = debts.first(where: { $0.uid == item.debtID }) {
            HStack(spacing: 8) {
                IconBadge(symbol: "building.columns.fill", color: d.type.color, size: 28)
                Text("\(d.isOut ? "Платёж" : "Вам вернули"): \(d.name)").font(.body.weight(.semibold))
            }
            if let ni = d.nextInst {
                Text("Отметится платёж \(ni.i + 1) из \(ni.n) (срок \(DF.short(ni.due))) и попадёт в \(d.isOut ? "расходы" : "доходы")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var goalHeader: some View {
        if let g = goals.first(where: { $0.uid == item.goalID }) {
            HStack(spacing: 8) {
                IconBadge(symbol: "banknote.fill", color: Color(hex: g.hex), size: 28)
                Text("\(item.sign < 0 ? "Взять из" : "Положить в") «\(g.name)»").font(.body.weight(.semibold))
            }
        }
    }
}
