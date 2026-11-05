import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: Store
    @State private var step = 0
    private let last = 7

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                HStack(spacing: 6) {
                    ForEach(1...last, id: \.self) { i in
                        Capsule().fill(i <= step ? store.meColor : Color.primary.opacity(0.12))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0: WelcomeStep()
                    case 1: NamesStep()
                    case 2: DateStep()
                    case 3: ColorsStep()
                    case 4: LookStep()
                    case 5: FeaturesStep()
                    case 6: PairStep()
                    default: FinishStep()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 12) {
                if step > 0 {
                    Button { go(-1) } label: {
                        Image(systemName: "chevron.left").font(.headline)
                            .frame(width: 56, height: 56)
                            .background(Pal.card, in: RoundedRectangle(cornerRadius: store.radius, style: .continuous))
                    }
                    .foregroundStyle(.primary)
                }
                Button { next() } label: {
                    Text(step == 0 ? "Начать" : (step == last ? "Готово, поехали" : "Дальше")).bigButton()
                }
                .disabled(!canNext)
                .opacity(canNext ? 1 : 0.4)
            }
            .padding(.horizontal, 24).padding(.bottom, 16).padding(.top, 8)
        }
        .background(Pal.bg.ignoresSafeArea())
        .animation(Motion.curve(0.25), value: step)
    }

    private var canNext: Bool {
        if step == 1 { return !store.p.myName.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func go(_ d: Int) { store.tap(); step = max(0, min(last, step + d)) }

    private func next() {
        if step == last {
            store.data.profile.onboarded = true
            store.success()
            if store.p.notifications { Notifier.setDaily(true) }
        } else {
            go(1)
        }
    }
}

// MARK: - Шаги

private struct Title: View {
    let big: String
    let small: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(big).font(.system(size: 32, weight: .semibold))
            Text(small).font(.body).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

private struct WelcomeStep: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                Circle().fill(store.meColor).frame(width: 120, height: 120).offset(x: -34)
                Circle().fill(store.partnerColor).frame(width: 120, height: 120).offset(x: 34)
                    .blendMode(.plusLighter).opacity(0.9)
            }
            .frame(maxWidth: .infinity).padding(.top, 70).padding(.bottom, 20)
            Text("Вдвоём").font(.system(size: 44, weight: .semibold))
            Text("Общие дела, даты, желания, игры и заметки — всё для двоих в одном приложении. Настроим под вас за минуту.")
                .font(.title3).foregroundStyle(.secondary)
        }
    }
}

private struct NamesStep: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Title(big: "Как вас зовут?", small: "Имена будут в задачах, чате и играх.")
        field("Ваше имя", text: $store.data.profile.myName, color: store.meColor)
        field("Имя второй половинки", text: $store.data.profile.partnerName, color: store.partnerColor)
    }
    private func field(_ ph: String, text: Binding<String>, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 14, height: 14)
            TextField(ph, text: text).font(.title3).textInputAutocapitalization(.words)
        }
        .padding(16).card()
    }
}

private struct DateStep: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Title(big: "Когда всё началось?", small: "Посчитаем дни вместе и напомним про годовщину.")
        DatePicker("Дата", selection: $store.data.profile.start, in: ...Date(), displayedComponents: .date)
            .datePickerStyle(.graphical).padding(8).card()
        Text("Вместе уже \(store.daysTogether) дн.").font(.headline).foregroundStyle(.secondary)
    }
}

private struct ColorsStep: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Title(big: "Ваши цвета", small: "Синий и розовый — по умолчанию. Выберите пару или задайте свои.")
        ForEach(colorPairs) { pair in
            let selected = store.p.myHex == pair.me && store.p.partnerHex == pair.partner
            Button {
                store.data.profile.myHex = pair.me
                store.data.profile.partnerHex = pair.partner
                store.tap()
            } label: {
                HStack(spacing: 14) {
                    HStack(spacing: -8) {
                        Circle().fill(Color(hex: pair.me)).frame(width: 30, height: 30)
                        Circle().fill(Color(hex: pair.partner)).frame(width: 30, height: 30)
                    }
                    Text(pair.id).font(.body.weight(.medium))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(store.meColor) }
                }
                .padding(14).card()
            }
            .buttonStyle(PressStyle())
        }
        VStack(spacing: 4) {
            ColorPicker(store.name(.me), selection: Binding(
                get: { Color(hex: store.p.myHex) }, set: { store.data.profile.myHex = $0.hex }), supportsOpacity: false)
            Divider()
            ColorPicker(store.name(.partner), selection: Binding(
                get: { Color(hex: store.p.partnerHex) }, set: { store.data.profile.partnerHex = $0.hex }), supportsOpacity: false)
        }
        .padding(16).card()
    }
}

struct LookControls: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Тема").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Тема", selection: $store.data.profile.theme) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Шрифт").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Picker("Шрифт", selection: $store.data.profile.design) {
                    ForEach(DesignStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Скругление").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(store.radius)) пт").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Double(store.radius) }, set: { store.setRadius($0) }), in: 0...30, step: 1,
                       onEditingChanged: { editing in if !editing { store.commitRadius() } })
            }
            Toggle("Вибро-отклик", isOn: $store.data.profile.haptics)
        }
    }
}

private struct LookStep: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Title(big: "Внешний вид", small: "Всё меняется сразу — посмотрите на пример ниже.")
        LookControls().padding(16).card()
        Text("Пример").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
        HStack(spacing: 12) {
            Image(systemName: "circle").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Купить цветы к ужину").font(.body.weight(.medium))
                HStack { Chip(text: store.name(.me), color: store.meColor); Chip(text: "Сегодня", color: .secondary) }
            }
            Spacer()
        }
        .padding(14).card()
    }
}

private struct FeaturesStep: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Title(big: "Что вам нужно?", small: "Отключите лишнее — порядок и нижнюю панель можно поменять позже в «Ещё».")
        ForEach(Module.allCases) { m in
            let on = !store.p.disabled.contains(m)
            Button {
                if on { store.data.profile.disabled.append(m) }
                else { store.data.profile.disabled.removeAll { $0 == m } }
                store.tap()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: m.icon).frame(width: 28).foregroundStyle(on ? store.meColor : .secondary)
                    Text(m.title).font(.body.weight(.medium))
                    if m.isNew { Chip(text: "новое", color: store.partnerColor) }
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? store.meColor : .secondary)
                }
                .padding(14).card()
            }
            .buttonStyle(PressStyle())
        }
    }
}

private struct PairStep: View {
    var body: some View {
        Title(big: "Подключите вторую половинку", small: "Один создаёт код, второй вводит его. После этого всё — задачи, чат, статусы и игры — появляется у обоих сразу.")
        PairPanel()
        Text("Этот шаг можно пропустить и подключиться позже в настройках.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

private struct FinishStep: View {
    @EnvironmentObject var store: Store
    @State private var asked = false
    var body: some View {
        Title(big: "Последний штрих", small: "Эти настройки можно изменить в любой момент.")
        VStack(spacing: 14) {
            Toggle("Ежедневный «Вопрос дня» в 20:00", isOn: Binding(
                get: { store.p.notifications },
                set: { on in
                    store.data.profile.notifications = on
                    if on { Task { let ok = await Notifier.request(); if !ok { store.data.profile.notifications = false } } }
                }))
            Divider()
            Toggle("Закрыть приложение Face ID", isOn: $store.data.profile.lockApp)
        }
        .padding(16).card()
        Text("Дальше: добавьте первую задачу, хотелку или событие. Вместе уже \(store.daysTogether) дн.")
            .font(.subheadline).foregroundStyle(.secondary)
    }
}
