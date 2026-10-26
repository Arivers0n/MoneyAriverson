import SwiftUI
import SwiftData

/// Строки для экрана настроек: аккаунт, синхронизация и выбор бюджета.
struct SyncSettingsSection: View {
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Section {
            NavigationLink { AccountView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: sync.loggedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.plus")
                        .font(.title2).foregroundStyle(sync.loggedIn ? Theme.inc : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sync.loggedIn ? (sync.userName.isEmpty ? sync.userEmail : sync.userName) : "Войти и синхронизировать")
                            .font(.body.weight(.medium))
                        Text(statusLine).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if sync.loggedIn {
                NavigationLink { FamilyView() } label: {
                    LabeledContent("Бюджет", value: sync.currentSpace?.name ?? "Личное")
                }
            }
        } header: { Text("Аккаунт") } footer: {
            if !sync.loggedIn { Text("Синхронизация между iPhone и iPad и общий семейный бюджет. Нужен ваш сервер — он ставится одной командой.") }
        }
    }

    var statusLine: String {
        switch sync.state {
        case .off: return "Данные только на этом устройстве"
        case .syncing: return "Синхронизация…"
        case .error(let e): return "Ошибка: \(e)"
        case .idle:
            if let d = sync.lastSync {
                let m = Int(Date().timeIntervalSince(d) / 60)
                if m < 1 { return "Синхронизировано только что" }
                if m < 60 { return "Синхронизировано \(m) мин назад" }
                return "Синхронизировано " + DF.s(d, "d MMM, HH:mm")
            }
            return "Подключено"
        }
    }
}

// MARK: - Вход и регистрация

struct AccountView: View {
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var server = SyncEngine.shared.server
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var registering = false
    @State private var busy = false
    @State private var err: String?
    @State private var serverOK: Bool?
    @State private var confirmLogout = false
    @State private var providers: [String] = []
    @State private var oauthBusy: String?

    var body: some View {
        Form {
            if sync.loggedIn {
                Section {
                    LabeledContent("Имя", value: sync.userName.isEmpty ? "—" : sync.userName)
                    LabeledContent("Почта", value: sync.userEmail)
                    LabeledContent("Сервер", value: sync.server.replacingOccurrences(of: "https://", with: ""))
                }
                Section {
                    Button {
                        Task { await sync.sync(ctx: ctx) }
                    } label: {
                        HStack {
                            Text("Синхронизировать сейчас")
                            Spacer()
                            if sync.state == .syncing { ProgressView() }
                        }
                    }
                    if case .error(let e) = sync.state { Text(e).font(.footnote).foregroundStyle(Theme.exp) }
                }
                Section {
                    Button("Выйти из аккаунта", role: .destructive) { confirmLogout = true }
                } footer: { Text("Данные останутся на телефоне. Синхронизация продолжится после повторного входа.") }
            } else {
                Section {
                    TextField("money.ваш-домен.ru", text: $server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .onSubmit { checkServer() }
                    if let ok = serverOK {
                        Label(ok ? "Сервер Копилки найден" : "По этому адресу сервер Копилки не отвечает",
                              systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.footnote).foregroundStyle(ok ? Theme.inc : Theme.exp)
                    }
                } header: { Text("Адрес сервера") } footer: {
                    Text("Уже указан сервер Копилки по умолчанию. Менять нужно, только если вам дали адрес другого сервера.")
                }
                if !providers.isEmpty {
                    Section {
                        ForEach(["apple", "google", "yandex"].filter { providers.contains($0) }, id: \.self) { p in
                            OAuthButton(provider: p, busy: oauthBusy == p) { oauth(p) }
                                .disabled(oauthBusy != nil || busy)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    } header: { Text("Быстрый вход") } footer: { Text("Войдите тем же аккаунтом на iPad или другом iPhone — данные будут одни и те же. Или по почте и паролю:") }
                }
                Section {
                    Picker("", selection: $registering) {
                        Text("Вход").tag(false)
                        Text("Новый аккаунт").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if registering { TextField("Как вас зовут", text: $name).textContentType(.name) }
                    TextField("Почта", text: $email)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.username)
                    SecureField(registering ? "Пароль (от 8 символов)" : "Пароль", text: $password)
                        .textContentType(registering ? .newPassword : .password)
                }
                if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text(registering ? "Создать аккаунт" : "Войти").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(busy || server.isEmpty || email.isEmpty || password.count < (registering ? 8 : 1))
                } footer: {
                    Text("Всё, что вы уже записали на этом телефоне, перенесётся в ваш личный бюджет на сервере.")
                }
            }
        }
        .onAppear { if !sync.loggedIn && !server.isEmpty { checkServer() } }
        .onChange(of: server) { _, v in
            providers = []
            let snap = v
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if snap == server, !snap.isEmpty { checkServer() }
            }
        }
        .navigationTitle(sync.loggedIn ? "Аккаунт" : "Синхронизация")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { sync.logout(keepData: true) }
        }
    }

    private func checkServer() {
        Task {
            serverOK = await sync.ping(server)
            let list = serverOK == true ? Array(await sync.oauthProviders(server).keys) : []
            withAnimation(Motion.spring) { providers = list }
        }
    }

    private func oauth(_ p: String) {
        oauthBusy = p; err = nil
        Haptic.press()
        Task {
            defer { oauthBusy = nil }
            do {
                try await sync.loginWithOAuth(p, server: server, ctx: ctx)
                Haptic.success()
                Router.shared.say("Вы вошли — данные синхронизируются")
                dismiss()
            } catch let e as SyncEngine.APIError where e.status == -1 {
                // пользователь закрыл окно
            } catch {
                Haptic.warning()
                err = error.localizedDescription
            }
        }
    }
    private func submit() {
        busy = true; err = nil
        Task {
            defer { busy = false }
            do {
                if registering {
                    try await sync.register(server: server, name: name.trimmingCharacters(in: .whitespaces), email: email.trimmingCharacters(in: .whitespaces), password: password, ctx: ctx)
                } else {
                    try await sync.login(server: server, email: email.trimmingCharacters(in: .whitespaces), password: password, ctx: ctx)
                }
                Router.shared.say("Вы вошли — данные синхронизируются")
                dismiss()
            } catch {
                err = error.localizedDescription
                if serverOK == nil { serverOK = await sync.ping(server) }
            }
        }
    }
}

// MARK: - Бюджеты: личный и семейный

struct FamilyView: View {
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.modelContext) private var ctx
    @State private var newName = "Семья"
    @State private var code = ""
    @State private var busy = false
    @State private var err: String?
    @State private var showCreate = false
    @State private var confirmLeave: SpaceInfo?

    var body: some View {
        Form {
            Section {
                ForEach(sync.spaces) { s in
                    Button {
                        sync.switchTo(s.id)
                        Task { await sync.sync(ctx: ctx) }
                    } label: {
                        HStack {
                            Image(systemName: s.personal ? "person.fill" : "person.3.fill").foregroundStyle(Theme.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).foregroundStyle(.primary)
                                Text(s.personal ? "Видите только вы" : "\(s.members.count) \(plural(s.members.count, "участник", "участника", "участников"))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if s.id == Space.current { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            } header: { Text("Мои бюджеты") } footer: {
                Text("Каждый бюджет — отдельные счета, траты, копилки и долги. Переключайтесь, когда нужно.")
            }

            if let s = sync.currentSpace, !s.personal {
                Section {
                    HStack {
                        Text(s.code).font(.system(.title2, design: .monospaced).weight(.bold)).tracking(3)
                        Spacer()
                        ShareLink(item: "Присоединяйся к нашему бюджету в Копилке: \(sync.server)/api/kp/invite?code=\(s.code)\n\nИли вручную — сервер: \(sync.server.replacingOccurrences(of: "https://", with: "")), код приглашения: \(s.code)") {
                            Label("Отправить", systemImage: "square.and.arrow.up")
                        }
                    }
                    ForEach(s.members) { m in
                        HStack {
                            Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(m.display + (m.id == sync.userID ? " (вы)" : ""))
                                if !m.name.isEmpty { Text(m.email).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if m.id == s.owner { Text("владелец").font(.caption).foregroundStyle(.secondary) }
                        }
                        .swipeActions {
                            if s.owner == sync.userID && m.id != sync.userID {
                                Button("Удалить", role: .destructive) { run { try await sync.update(s.id, kick: m.id) } }
                            }
                        }
                    }
                    if s.owner == sync.userID {
                        Button("Сменить код приглашения") { run { try await sync.update(s.id, newCode: true) } }
                    }
                    Button("Выйти из «\(s.name)»", role: .destructive) { confirmLeave = s }
                } header: { Text("«\(s.name)» · код приглашения") } footer: {
                    Text("Отправьте код близким: в Копилке → Настройки → Аккаунт → Бюджет → «Вступить по коду». Все участники видят и меняют общие траты, копилки и долги, у каждой записи подписан автор.")
                }
            }

            Section {
                Button("Создать семейный бюджет") { showCreate = true }
                HStack {
                    TextField("Код приглашения", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Вступить") { run { try await sync.join(code: code, ctx: ctx); code = "" } }
                        .disabled(code.trimmingCharacters(in: .whitespaces).count < 4)
                }
            } header: { Text("Общий бюджет") }

            if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
        }
        .navigationTitle("Бюджеты")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .task { try? await sync.loadSpaces() }
        .alert("Новый общий бюджет", isPresented: $showCreate) {
            TextField("Название", text: $newName)
            Button("Создать") {
                run {
                    if let s = try await sync.createSpace(name: newName) { sync.switchTo(s.id) }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Например «Семья» или «Мы вдвоём». Потом пригласите близких по коду.") }
        .confirmationDialog("Выйти из «\(confirmLeave?.name ?? "")»? Общие записи останутся у остальных участников.", isPresented: Binding(get: { confirmLeave != nil }, set: { if !$0 { confirmLeave = nil } }), titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                if let s = confirmLeave {
                    run {
                        try await sync.leave(s.id)
                        if let p = sync.spaces.first(where: { $0.personal }) { sync.switchTo(p.id) }
                    }
                }
            }
        }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true; err = nil
        Task {
            defer { busy = false }
            do { try await op() } catch { err = error.localizedDescription }
        }
    }
}

/// Цветная буква G (нарисована фигурами, без картинок).
struct GoogleG: View {
    var body: some View {
        GeometryReader { g in
            let w = min(g.size.width, g.size.height)
            let lw = w * 0.2
            ZStack {
                seg(0, 0.125, Color(red: 0.26, green: 0.52, blue: 0.96), lw)
                seg(0.125, 0.375, Color(red: 0.20, green: 0.66, blue: 0.33), lw)
                seg(0.375, 0.556, Color(red: 0.98, green: 0.74, blue: 0.02), lw)
                seg(0.556, 0.875, Color(red: 0.92, green: 0.26, blue: 0.21), lw)
                Rectangle().fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .frame(width: (w - lw) / 2, height: lw)
                    .offset(x: (w - lw) / 4)
            }
            .padding(lw / 2)
            .frame(width: w, height: w)
        }
    }
    private func seg(_ a: CGFloat, _ b: CGFloat, _ c: Color, _ lw: CGFloat) -> some View {
        Circle().trim(from: a, to: b).stroke(c, style: StrokeStyle(lineWidth: lw))
    }
}

/// Кнопка «Войти через …» в фирменном стиле сервиса.
struct OAuthButton: View {
    let provider: String
    let busy: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(fg) } else { logo }
                Text(title).font(.body.weight(.semibold))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(provider == "google" ? 0.12 : 0)))
        }
        .buttonStyle(Pressable(scale: 0.97))
    }
    private var title: String {
        switch provider {
        case "apple": return "Войти через Apple"
        case "yandex": return "Войти с Яндекс ID"
        default: return "Войти через Google"
        }
    }
    private var bg: Color {
        switch provider {
        case "apple": return scheme == .dark ? .white : .black
        case "yandex": return Color(red: 0.99, green: 0.24, blue: 0.13)
        default: return Color(.secondarySystemGroupedBackground)
        }
    }
    private var fg: Color {
        switch provider {
        case "apple": return scheme == .dark ? .black : .white
        case "yandex": return .white
        default: return .primary
        }
    }
    @ViewBuilder private var logo: some View {
        switch provider {
        case "apple": Image(systemName: "apple.logo").font(.system(size: 19, weight: .medium))
        case "yandex":
            Text("Я").font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(red: 0.99, green: 0.24, blue: 0.13))
                .frame(width: 22, height: 22).background(.white, in: Circle())
        default: GoogleG().frame(width: 20, height: 20)
        }
    }
}
