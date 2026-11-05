import SwiftUI

// MARK: - Вопрос дня

private let dayQuestions: [String] = [
    "Какой момент за последний месяц ты хочешь пережить ещё раз?",
    "За что ты мне больше всего благодарен(на)?",
    "Куда бы ты поехал(а) со мной завтра, если бы не нужно было думать о деньгах?",
    "Что я делаю такого, отчего тебе становится спокойно?",
    "Какая наша общая привычка тебе нравится больше всего?",
    "Чему ты хочешь научиться вместе?",
    "Какое наше первое воспоминание самое тёплое?",
    "Что тебя в последнее время беспокоит и я могу помочь?",
    "Каким ты видишь наш идеальный выходной?",
    "Что бы ты изменил(а) в нашем быту?",
    "Какая песня напоминает тебе обо мне?",
    "Какая мечта у тебя самая смелая?",
    "Что мы должны попробовать в этом году?",
    "Когда ты почувствовал(а), что я «свой человек»?",
    "Какое моё качество ты ценишь больше всего?",
    "Какой фильм мы обязаны посмотреть вместе?",
    "Что тебя во мне удивляет до сих пор?",
    "Что бы ты хотел(а), чтобы я делал(а) чаще?",
    "Какой подарок от меня был самым запоминающимся?",
    "Как ты представляешь нас через 10 лет?",
    "Какое блюдо мы должны научиться готовить вместе?",
    "Что тебе нужно от меня в трудный день?",
    "Какой маленький ритуал мы могли бы завести?",
    "О чём мы давно не разговаривали, а стоило бы?"
]

struct QuestionView: View {
    @EnvironmentObject var store: Store
    @State private var reveal = false

    private var key: String { Date().dayKey }
    private var question: String {
        let d = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return dayQuestions[d % dayQuestions.count]
    }
    private var idx: Int? { store.data.answers.firstIndex { $0.id == key } }
    private var answer: DayAnswer { idx.map { store.data.answers[$0] } ?? DayAnswer(id: key) }

    var body: some View {
        Screen {
            Text(question).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(18).card()
            field(.me)
            field(.partner)
            let both = !answer.me.isEmpty && !answer.partner.isEmpty
            Button {
                withAnimation { reveal.toggle() }
            } label: { Text(reveal ? "Скрыть ответы" : "Показать ответы").bigButton() }
            .disabled(!both).opacity(both ? 1 : 0.4)
            if reveal && both {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.name(.me)).font(.caption.weight(.semibold)).foregroundStyle(store.meColor)
                    Text(answer.me)
                    Divider()
                    Text(store.name(.partner)).font(.caption.weight(.semibold)).foregroundStyle(store.partnerColor)
                    Text(answer.partner)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).card()
            }
            Text("Ответы скрыты, пока не ответят оба.").font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Вопрос дня")
    }

    private func field(_ w: Who) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.name(w)).font(.caption.weight(.semibold)).foregroundStyle(store.color(w))
            TextField("Ваш ответ", text: Binding(
                get: { w == .me ? answer.me : answer.partner },
                set: { v in
                    var a = answer
                    if w == .me { a.me = v } else { a.partner = v }
                    if let i = idx { store.data.answers[i] = a } else { store.data.answers.append(a) }
                }), axis: .vertical)
                .lineLimit(2...6)
        }
        .padding(16).card()
    }
}

// MARK: - Тест на совместимость

private struct CQ { let q: String; let a: [String] }
private let compatQuestions: [CQ] = [
    CQ(q: "Идеальный вечер пятницы", a: ["Дома с фильмом", "Ресторан или бар", "Прогулка", "Гости"]),
    CQ(q: "Отпуск мечты", a: ["Море и ничего не делать", "Города и музеи", "Горы и походы", "Дорожное приключение"]),
    CQ(q: "Утро выходного", a: ["Спать до обеда", "Завтрак в кафе", "Спорт", "Дела по дому"]),
    CQ(q: "Как решаете спор", a: ["Сразу обсуждаем", "Берём паузу", "Шутим", "Пишем сообщения"]),
    CQ(q: "Деньги — это", a: ["Копить", "Тратить на впечатления", "Вкладывать", "Баланс"]),
    CQ(q: "Питомец", a: ["Кошка", "Собака", "Другое", "Никого"]),
    CQ(q: "Идеальный подарок", a: ["Вещь", "Впечатление", "Сделанное руками", "Сюрприз"]),
    CQ(q: "Как говорите «люблю»", a: ["Словами", "Поступками", "Подарками", "Объятиями"]),
    CQ(q: "Переезд", a: ["В другой город", "В другую страну", "Остаёмся", "Дом за городом"]),
    CQ(q: "Музыка в машине", a: ["Попса", "Рок", "Рэп", "Что угодно"])
]

struct CompatView: View {
    @EnvironmentObject var store: Store
    @State private var phase = 0            // 0 старт, 1 я, 2 партнёр, 3 итог
    @State private var q = 0
    @State private var mine: [Int] = []
    @State private var theirs: [Int] = []

    var body: some View {
        Screen {
            switch phase {
            case 0: start
            case 1, 2: question
            default: result
            }
        }
        .navigationTitle("Тест на совместимость")
    }

    private var start: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.circle").font(.system(size: 56)).foregroundStyle(store.partnerColor).padding(.top, 40)
            Text("10 вопросов. Сначала отвечает \(store.name(.me)), потом \(store.name(.partner)) — на одном телефоне, не подглядывая.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let r = store.data.compat {
                Text("Прошлый результат: \(r.percent)% · \(r.date.formatted(.dateTime.day().month()))").font(.subheadline)
            }
            Button { phase = 1; q = 0; mine = []; theirs = [] } label: { Text("Начать").bigButton() }
        }
    }

    private var question: some View {
        let item = compatQuestions[q]
        let w: Who = phase == 1 ? .me : .partner
        return VStack(spacing: 12) {
            Text("\(store.name(w)) · вопрос \(q + 1) из \(compatQuestions.count)")
                .font(.caption.weight(.semibold)).foregroundStyle(store.color(w))
            Text(item.q).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
            ForEach(item.a.indices, id: \.self) { i in
                Button { pick(i) } label: {
                    Text(item.a[i]).font(.body.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).card()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var result: some View {
        let same = zip(mine, theirs).filter { $0.0 == $0.1 }.count
        let pct = same * 100 / compatQuestions.count
        return VStack(spacing: 14) {
            Text("\(pct)%").font(.system(size: 72, weight: .semibold)).padding(.top, 30)
            Text(pct >= 70 ? "Вы на одной волне" : (pct >= 40 ? "Отличный баланс — есть о чём поговорить" : "Противоположности притягиваются"))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            ForEach(compatQuestions.indices, id: \.self) { i in
                HStack {
                    Text(compatQuestions[i].q).font(.subheadline)
                    Spacer()
                    Image(systemName: mine[i] == theirs[i] ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(mine[i] == theirs[i] ? Color.green : Color.secondary)
                }
                .padding(12).card()
            }
            Button { phase = 0 } label: { Text("Готово").bigButton() }
        }
        .onAppear { store.data.compat = CompatResult(percent: pct, date: Date()) }
    }

    private func pick(_ i: Int) {
        store.tap()
        if phase == 1 { mine.append(i) } else { theirs.append(i) }
        if q + 1 < compatQuestions.count { q += 1 }
        else if phase == 1 { phase = 2; q = 0 }
        else { phase = 3 }
    }
}

// MARK: - Капсула времени

struct CapsuleView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var opened: TimeCapsule?

    var body: some View {
        Screen {
            if store.data.capsules.isEmpty {
                EmptyState(icon: "envelope", title: "Капсула времени", text: "Напишите письмо в будущее. Откроется только в выбранный день.",
                           action: "Написать письмо", onTap: { adding = true })
            }
            ForEach(store.data.capsules.sorted { $0.opens < $1.opens }) { c in
                let ready = c.opens <= Date()
                Button { if ready { opened = c } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: ready ? "envelope.open" : "lock.fill").font(.title2).foregroundStyle(store.color(c.from))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title).font(.body.weight(.semibold))
                            Text(ready ? "Можно открыть" : "Откроется \(c.opens.formatted(.dateTime.day().month(.wide).year()))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !ready {
                            Button(role: .destructive) { store.data.capsules.removeAll { $0.id == c.id } } label: {
                                Image(systemName: "trash").foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(14).card()
                }
                .buttonStyle(.plain)
            }
        }
        .pairToolbar(scope: false, add: { adding = true })
        .sheet(isPresented: $adding) { AddCapsuleSheet() }
        .sheet(item: $opened) { c in
            NavigationStack {
                ScrollView { Text(c.text).padding(20).frame(maxWidth: .infinity, alignment: .leading) }
                    .background(Pal.bg.ignoresSafeArea())
                    .navigationTitle(c.title).navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

struct AddCapsuleSheet: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var text = ""
    @State private var date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var from: Who = .me

    var body: some View {
        FormSheet(title: "Письмо в будущее", canSave: !title.isEmpty && !text.isEmpty, onSave: {
            store.data.capsules.append(TimeCapsule(title: title, text: text, opens: date, from: from))
            if store.p.notifications { Notifier.schedule(id: "capsule-\(title)", title: "Капсула времени", body: title, at: date) }
        }) {
            Section {
                TextField("Тема", text: $title)
                TextField("Текст письма", text: $text, axis: .vertical).lineLimit(6...20)
                WhoPicker(who: $from)
            }
            Section("Когда открыть") {
                DatePicker("Дата", selection: $date, in: Date()..., displayedComponents: .date)
            }
        }
    }
}

// MARK: - Голосование

struct VoteView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var voter: Who = .me

    var body: some View {
        Screen {
            WhoPicker(who: $voter).padding(12).card()
            if store.data.polls.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "Решаем вместе", text: "Где ужинать, какой фильм, куда поехать — голосуйте.",
                           action: "Создать голосование", onTap: { adding = true })
            }
            ForEach(store.data.polls) { p in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(p.question).font(.headline)
                        Spacer()
                        Button(role: .destructive) { store.data.polls.removeAll { $0.id == p.id } } label: {
                            Image(systemName: "trash").foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(p.options) { o in
                        Button { vote(p, o) } label: {
                            HStack {
                                Text(o.text)
                                Spacer()
                                HStack(spacing: 4) { ForEach(o.voters, id: \.self) { Circle().fill(store.color($0)).frame(width: 12, height: 12) } }
                                if o.voters.contains(voter) { Image(systemName: "checkmark.circle.fill").foregroundStyle(store.color(voter)) }
                            }
                            .padding(12).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14).card()
            }
        }
        .pairToolbar(scope: false, add: { adding = true })
        .sheet(isPresented: $adding) { AddPollSheet() }
    }

    private func vote(_ p: Poll, _ o: PollOption) {
        guard let pi = store.data.polls.firstIndex(where: { $0.id == p.id }) else { return }
        for oi in store.data.polls[pi].options.indices {
            store.data.polls[pi].options[oi].voters.removeAll { $0 == voter }
        }
        if let oi = store.data.polls[pi].options.firstIndex(where: { $0.id == o.id }) {
            if !o.voters.contains(voter) { store.data.polls[pi].options[oi].voters.append(voter) }
        }
        store.tap()
    }
}

struct AddPollSheet: View {
    @EnvironmentObject var store: Store
    @State private var question = ""
    @State private var options = ["", ""]

    var body: some View {
        FormSheet(title: "Голосование", canSave: !question.isEmpty && options.filter { !$0.isEmpty }.count >= 2, onSave: {
            store.data.polls.insert(Poll(question: question, options: options.filter { !$0.isEmpty }.map { PollOption(text: $0) }), at: 0)
        }) {
            Section { TextField("Вопрос", text: $question) }
            Section("Варианты") {
                ForEach(options.indices, id: \.self) { i in TextField("Вариант \(i + 1)", text: $options[i]) }
                Button("Добавить вариант") { options.append("") }
            }
        }
    }
}

// MARK: - Подарочный радар

struct RadarView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false

    var body: some View {
        let partnerWishes = store.data.wishes.filter { $0.owner == .partner && !$0.got && !$0.reserved }
        Screen {
            if !partnerWishes.isEmpty {
                SectionTitle("Хотелки: \(store.name(.partner))", color: store.partnerColor)
                ForEach(partnerWishes) { w in
                    HStack {
                        Text(w.title).font(.body.weight(.medium))
                        Spacer()
                        if !w.price.isEmpty { Chip(text: w.price + " ₽") }
                    }
                    .padding(14).card()
                }
            }
            SectionTitle("Мои идеи")
            if store.data.gifts.isEmpty {
                EmptyState(icon: "dot.radiowaves.left.and.right", title: "Подарочный радар",
                           text: "Записывайте идеи подарков, когда они приходят. Тайно — их увидите только вы.",
                           action: "Добавить идею", onTap: { adding = true })
            }
            ForEach(store.data.gifts) { g in
                HStack(spacing: 12) {
                    Button {
                        if let i = store.data.gifts.firstIndex(where: { $0.id == g.id }) { store.data.gifts[i].bought.toggle() }
                    } label: {
                        Image(systemName: g.bought ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(g.bought ? store.meColor : Color.secondary)
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.title).strikethrough(g.bought)
                        if !g.occasion.isEmpty { Text(g.occasion).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if !g.price.isEmpty { Chip(text: g.price + " ₽") }
                    Button(role: .destructive) { store.data.gifts.removeAll { $0.id == g.id } } label: {
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(14).card()
            }
        }
        .pairToolbar(scope: false, add: { adding = true })
        .sheet(isPresented: $adding) { AddGiftSheet() }
    }
}

struct AddGiftSheet: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var occasion = ""
    @State private var price = ""

    var body: some View {
        FormSheet(title: "Идея подарка", canSave: !title.isEmpty, onSave: {
            store.data.gifts.append(GiftIdea(title: title, occasion: occasion, price: price))
        }) {
            TextField("Что подарить?", text: $title)
            TextField("Повод (день рождения, годовщина)", text: $occasion)
            TextField("Примерная цена, ₽", text: $price).keyboardType(.numberPad)
        }
    }
}

// MARK: - Наши даты (новое)

struct DaysView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let c = Calendar.current
        let comps = c.dateComponents([.year, .month, .day], from: c.startOfDay(for: store.p.start), to: c.startOfDay(for: Date()))
        let milestones = [100, 200, 365, 500, 730, 1000, 1500, 2000, 3000, 3650]
        Screen {
            VStack(spacing: 6) {
                Text("\(store.daysTogether)").font(.system(size: 72, weight: .semibold))
                Text("дней вместе").foregroundStyle(.secondary)
                Text("\(comps.year ?? 0) г. \(comps.month ?? 0) мес. \(comps.day ?? 0) дн.").font(.footnote.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(24).card()

            SectionTitle("Ближайшие рубежи")
            ForEach(milestones, id: \.self) { m in
                let date = c.date(byAdding: .day, value: m, to: store.p.start) ?? Date()
                let left = m - store.daysTogether
                HStack {
                    Text("\(m) дней").font(.body.weight(.semibold))
                    Spacer()
                    Text(left > 0 ? "через \(left) дн. · \(date.formatted(.dateTime.day().month().year()))" : "было \(date.formatted(.dateTime.day().month().year()))")
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: left > 0 ? "hourglass" : "checkmark.seal.fill").foregroundStyle(left > 0 ? Color.secondary : store.partnerColor)
                }
                .padding(14).card().opacity(left > 0 ? 1 : 0.6)
            }
        }
        .navigationTitle("Наши даты")
    }
}

// MARK: - Настроение (новое)

struct MoodView: View {
    @EnvironmentObject var store: Store
    private let moods = ["😞", "😕", "😐", "🙂", "😍"]

    private func current(_ w: Who) -> Int? {
        store.data.moods.first { $0.day == Date().dayKey && $0.who == w }?.mood
    }

    var body: some View {
        Screen {
            ForEach(Who.allCases, id: \.self) { w in
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Как дела у \(store.name(w))?", color: store.color(w))
                    HStack {
                        ForEach(moods.indices, id: \.self) { i in
                            Button { set(w, i) } label: {
                                Text(moods[i]).font(.system(size: 34)).frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(current(w) == i ? store.color(w).opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14).card()
            }
            SectionTitle("Последние дни")
            let days = Array(Set(store.data.moods.map(\.day))).sorted(by: >).prefix(7)
            if days.isEmpty { Text("Отмечайте настроение каждый день — тут появится история.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(Array(days), id: \.self) { d in
                HStack {
                    Text(d).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(Who.allCases, id: \.self) { w in
                        if let m = store.data.moods.first(where: { $0.day == d && $0.who == w }) {
                            Text(moods[m.mood])
                        } else { Text("·").foregroundStyle(.tertiary) }
                    }
                }
                .padding(14).card()
            }
        }
        .navigationTitle("Настроение")
    }

    private func set(_ w: Who, _ i: Int) {
        let day = Date().dayKey
        let id = day + w.rawValue
        if let idx = store.data.moods.firstIndex(where: { $0.id == id }) { store.data.moods[idx].mood = i }
        else { store.data.moods.append(MoodEntry(id: id, day: day, who: w, mood: i)) }
        store.tap()
    }
}

// MARK: - Идеи свиданий (новое)

private let dateIdeas = [
    "Ужин при свечах дома", "Кино под открытым небом", "Пикник в парке", "Вечер настолок",
    "Кулинарный мастер-класс", "Прогулка по незнакомому району", "Поход на каток", "Фотосессия друг другу",
    "Готовим блюдо другой страны", "Закат на крыше", "Квест-комната", "Тематический вечер: фильмы 90-х",
    "Музей или выставка", "Поездка за город на день", "Вечер без телефонов", "Купить билеты на концерт",
    "Мини-путешествие на выходные", "Спа-вечер дома", "Рисуем портреты друг друга", "Поход по кофейням"
]

struct DatesView: View {
    @EnvironmentObject var store: Store
    @State private var idea = "Нажмите «Крутить»"
    @State private var added = false

    var body: some View {
        Screen {
            VStack(spacing: 18) {
                Text("🎲").font(.system(size: 60))
                Text(idea).font(.title2.weight(.semibold)).multilineTextAlignment(.center).frame(minHeight: 70)
                Button { roll() } label: { Text("Крутить").bigButton() }
                if idea != "Нажмите «Крутить»" {
                    Button {
                        store.data.tasks.insert(TaskItem(title: idea), at: 0)
                        added = true
                        store.success()
                    } label: { Label(added ? "Добавлено в задачи" : "В задачи", systemImage: added ? "checkmark" : "plus") }
                    .disabled(added)
                }
            }
            .frame(maxWidth: .infinity).padding(20).card()
        }
        .navigationTitle("Идеи свиданий")
    }

    private func roll() {
        store.tap()
        added = false
        withAnimation { idea = dateIdeas.randomElement() ?? idea }
    }
}
