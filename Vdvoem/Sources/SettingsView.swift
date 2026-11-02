import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var confirmReset = false

    var body: some View {
        Screen {
            group("Профиль") {
                TextField("Ваше имя", text: $store.data.profile.myName)
                Divider()
                TextField("Имя партнёра", text: $store.data.profile.partnerName)
                Divider()
                DatePicker("Дата начала", selection: $store.data.profile.start, in: ...Date(), displayedComponents: .date)
            }

            group("Цвета") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(colorPairs) { pair in
                            Button {
                                store.data.profile.myHex = pair.me
                                store.data.profile.partnerHex = pair.partner
                                store.tap()
                            } label: {
                                HStack(spacing: -8) {
                                    Circle().fill(Color(hex: pair.me)).frame(width: 28, height: 28)
                                    Circle().fill(Color(hex: pair.partner)).frame(width: 28, height: 28)
                                }
                                .padding(10)
                                .background(Pal.field, in: Capsule())
                            }
                        }
                    }
                }
                Divider()
                ColorPicker(store.name(.me), selection: Binding(
                    get: { Color(hex: store.p.myHex) }, set: { store.data.profile.myHex = $0.hex }), supportsOpacity: false)
                Divider()
                ColorPicker(store.name(.partner), selection: Binding(
                    get: { Color(hex: store.p.partnerHex) }, set: { store.data.profile.partnerHex = $0.hex }), supportsOpacity: false)
            }

            group("Внешний вид") { LookControls() }

            group("Функции") {
                ForEach(Module.allCases) { m in
                    Toggle(isOn: Binding(
                        get: { !store.p.disabled.contains(m) },
                        set: { on in
                            if on { store.data.profile.disabled.removeAll { $0 == m } }
                            else if !store.p.disabled.contains(m) { store.data.profile.disabled.append(m) }
                        })) {
                        Label(m.title, systemImage: m.icon)
                    }
                    if m != Module.allCases.last { Divider() }
                }
            }

            NavigationLink { ReorderView() } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Порядок и нижняя панель").font(.body.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(16).card()
            }
            .buttonStyle(.plain)

            group("Пара") {
                HStack { Text("Ваш код"); Spacer(); Text(store.p.pairCode.isEmpty ? "—" : store.p.pairCode).font(.body.monospaced()).foregroundStyle(.secondary) }
                Divider()
                TextField("Код партнёра", text: $store.data.profile.partnerCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
            }

            group("Безопасность и уведомления") {
                Toggle("Закрыть приложение Face ID", isOn: $store.data.profile.lockApp)
                Divider()
                Toggle("Ежедневный «Вопрос дня»", isOn: Binding(
                    get: { store.p.notifications },
                    set: { on in
                        store.data.profile.notifications = on
                        if on {
                            Task {
                                let ok = await Notifier.request()
                                if !ok { store.data.profile.notifications = false }
                                Notifier.setDaily(ok)
                            }
                        } else {
                            Notifier.setDaily(false)
                        }
                    }))
            }

            Button(role: .destructive) { confirmReset = true } label: {
                Text("Сбросить все данные").frame(maxWidth: .infinity).padding(16).card()
            }
            .confirmationDialog("Удалить все данные и начать заново?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Удалить всё", role: .destructive) { store.resetAll() }
            }
        }
        .navigationTitle("Настройки")
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title)
            VStack(alignment: .leading, spacing: 12) { c() }.padding(16).card()
        }
    }
}

struct ReorderView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            Section {
                ForEach(store.p.order) { m in
                    let off = store.p.disabled.contains(m)
                    let pos = store.active.firstIndex(of: m)
                    HStack(spacing: 12) {
                        Image(systemName: m.icon).frame(width: 26)
                        Text(m.title)
                        Spacer()
                        if off { Chip(text: "выкл") }
                        else if let pos, pos < 4 { Chip(text: "панель", color: store.meColor) }
                    }
                    .opacity(off ? 0.45 : 1)
                    .listRowBackground(Pal.card)
                }
                .onMove { from, to in store.data.profile.order.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("Первые четыре включённые функции попадают в нижнюю панель, остальные — в «Ещё».")
                    .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Pal.bg.ignoresSafeArea())
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Порядок")
        .navigationBarTitleDisplayMode(.inline)
    }
}
