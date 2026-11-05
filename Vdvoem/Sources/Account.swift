import SwiftUI

// MARK: - Аккаунт: вход по почте и через Яндекс

/// Карточка в настройках и онбординге: либо «Войти», либо «Вы вошли как …».
struct AccountPanel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @State private var sheet = false
    @State private var confirmOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sync.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: sync.accountKind == "yandex" ? "y.circle.fill" : "envelope.fill")
                        .font(.title2).foregroundStyle(store.meColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Вы вошли").font(.subheadline.weight(.semibold))
                        Text(sync.accountEmail.hasSuffix("@oauth.vdvoem.app") ? "через Яндекс" : sync.accountEmail)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Выйти", role: .destructive) { confirmOut = true }
                        .font(.subheadline)
                }
                Text("Пара и данные привязаны к аккаунту — на новом телефоне просто войдите так же.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Аккаунт").font(.subheadline.weight(.semibold))
                Text("Сейчас пара привязана только к этому телефону. Войдите по почте или через Яндекс — тогда она не потеряется при смене телефона.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { sheet = true } label: {
                    Text("Войти или создать аккаунт").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        .animation(Motion.curve(0.25), value: sync.accountKind)
        .sheet(isPresented: $sheet) { SignInSheet() }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { sync.signOut(); store.success() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Данные останутся на телефоне, но пара отключится. Чтобы вернуть её, войдите снова.")
        }
    }
}

struct SignInSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss
    @State private var register = true
    @State private var email = ""
    @State private var pass = ""
    @State private var error: String?
    @State private var working = false
    @FocusState private var focus: Int?

    private var ready: Bool { email.contains("@") && !pass.isEmpty && !working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $register.animation(Motion.spring)) {
                        Text("Новый аккаунт").tag(true)
                        Text("Вход").tag(false)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 0) {
                        TextField("Почта", text: $email)
                            .keyboardType(.emailAddress).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: 0).submitLabel(.next)
                            .onSubmit { focus = 1 }
                            .padding(14)
                        Divider().padding(.leading, 14)
                        SecureField(register ? "Придумайте пароль (от 8 символов)" : "Пароль", text: $pass)
                            .textContentType(register ? .newPassword : .password)
                            .focused($focus, equals: 1).submitLabel(.go)
                            .onSubmit { Task { await go() } }
                            .padding(14)
                    }
                    .card()

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }

                    Button { Task { await go() } } label: {
                        HStack {
                            if working { ProgressView().tint(store.meColor.onAccent) }
                            Text(register ? "Создать аккаунт" : "Войти")
                        }
                        .bigButton()
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!ready).opacity(ready ? 1 : 0.5)

                    HStack(spacing: 10) {
                        Rectangle().fill(.quaternary).frame(height: 1)
                        Text("или").font(.footnote).foregroundStyle(.secondary)
                        Rectangle().fill(.quaternary).frame(height: 1)
                    }

                    Button { Task { await yandex() } } label: {
                        HStack(spacing: 10) {
                            Text("Я").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white).frame(width: 26, height: 26)
                                .background(Color(hex: "FC3F1D"), in: Circle())
                            Text("Войти через Яндекс").font(.headline).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .card()
                    }
                    .buttonStyle(PressStyle())
                    .disabled(working)

                    Text(register
                         ? "Пара и все данные этого телефона сохранятся — они просто привяжутся к аккаунту."
                         : "Если вы вошли на новом телефоне, пара подтянется сама.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(16)
                .animation(Motion.curve(0.22), value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ThemeBackground())
            .navigationTitle("Аккаунт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func finish(_ err: String?) {
        working = false
        if let err {
            error = err
            store.tap()
        } else {
            store.success()
            dismiss()
        }
    }

    private func go() async {
        guard ready else { return }
        working = true
        error = nil
        finish(register ? await sync.registerEmail(email, pass) : await sync.loginEmail(email, pass))
    }

    private func yandex() async {
        working = true
        error = nil
        finish(await sync.loginYandex())
    }
}

// MARK: - Стартовый экран подключения

/// Показывается при запуске, пока нет аккаунта и пары: вход, код партнёра или «пока пропустить».
struct ConnectGate: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    private var connected: Bool { sync.isPaired || sync.isSignedIn }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PairMark(size: 46).padding(.top, 28)
                Text("Подключитесь вдвоём").font(.title.weight(.semibold)).multilineTextAlignment(.center)
                Text("Войдите в аккаунт, чтобы пара не потерялась, а затем создайте код или введите код партнёра. Чат, задачи, статусы и всё остальное появятся у вас обоих сразу.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                AccountPanel()
                PairPanel()
                Button {
                    UserDefaults.standard.set(true, forKey: "vd.skipConnect")
                    store.tap()
                    dismiss()
                } label: {
                    Text(connected ? "Готово" : "Пока пропустить").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                Text("Это можно сделать позже: «Ещё» → «Настройки».")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
            .animation(Motion.curve(0.25), value: connected)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ThemeBackground())
    }
}
