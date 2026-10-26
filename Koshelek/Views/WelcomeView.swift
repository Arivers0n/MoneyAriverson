import SwiftUI
import SwiftData

/// Экран входа при первом запуске: адрес сервера уже вшит, человеку остаётся нажать «Войти через Google».
struct WelcomeView: View {
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.modelContext) private var ctx
    let onDone: () -> Void

    @State private var providers: [String] = []
    @State private var busy: String?
    @State private var err: String?
    @State private var showEmail = false
    @State private var showMore = false
    @State private var serverText = SyncEngine.shared.server
    @State private var appeared = false
    @State private var serverOK: Bool?

    var body: some View {
        ZStack {
            BackdropLayer(style: "aurora", accent: Theme.accent)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { skip() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Позже")
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.top, 8)

                Spacer()

                Image(AppIcons.all.first { $0.id == (UIApplication.shared.alternateIconName ?? "") }?.preview ?? "Preview-Default")
                    .resizable()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                    .scaleEffect(appeared || !Motion.moves ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)

                Text("Копилка")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .padding(.top, 22)
                Text("Скажите, что потратили, — остальное посчитаю сам.\nДанные одни на всех ваших устройствах.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 30)

                Spacer()

                VStack(spacing: 12) {
                    ForEach(["apple", "google", "yandex"].filter { providers.contains($0) }, id: \.self) { p in
                        OAuthButton(provider: p, busy: busy == p) { oauth(p) }
                            .disabled(busy != nil)
                    }
                    Button { showEmail = true } label: {
                        Label("Войти с помощью почты", systemImage: "envelope.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(Pressable(scale: 0.97))
                    .disabled(busy != nil)

                    if let err {
                        Text(err).font(.footnote).foregroundStyle(Theme.exp).multilineTextAlignment(.center)
                    } else if serverOK == false {
                        Text("Сервер не отвечает. Проверьте интернет — или нажмите «Позже», записи сохранятся на телефоне.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }

                    Button("Другой сервер") { showMore = true }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || !Motion.moves ? 0 : 20)
            }
        }
        .task {
            if let a = Motion.entrance(0.6) { withAnimation(a) { appeared = true } } else { appeared = true }
            await loadProviders()
        }
        .sheet(isPresented: $showEmail) {
            NavigationStack { AccountView() }
                .presentationDetents([.large])
        }
        .alert("Адрес сервера", isPresented: $showMore) {
            TextField("money.example.ru", text: $serverText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                sync.server = SyncEngine.normalize(serverText)
                Task { await loadProviders() }
            }
        } message: {
            Text("Если вам дали адрес другого сервера Копилки — вставьте его сюда.")
        }
        .onChange(of: sync.state) { _, _ in
            if sync.loggedIn { onDone() }
        }
    }

    private func loadProviders() async {
        guard !sync.server.isEmpty else { serverOK = false; return }
        serverOK = await sync.ping(sync.server)
        let list = serverOK == true ? Array(await sync.oauthProviders(sync.server).keys) : []
        withAnimation(Motion.spring) { providers = list }
    }

    private func oauth(_ p: String) {
        busy = p; err = nil
        Haptic.press()
        Task {
            defer { busy = nil }
            do {
                try await sync.loginWithOAuth(p, server: sync.server, ctx: ctx)
                Haptic.success()
                Router.shared.say("Вы вошли — данные синхронизируются")
                onDone()
            } catch let e as SyncEngine.APIError where e.status == -1 {
                // окно закрыли
            } catch {
                Haptic.warning()
                err = error.localizedDescription
            }
        }
    }

    private func skip() {
        Haptic.tap()
        onDone()
    }
}
