import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    @Query(sort: \Tx.date) private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }
    @AppStorage("budget") private var budget: Double = 0

    @State private var key = Keychain.apiKey ?? ""
    @State private var baseURL = APIConfig.baseURL
    @State private var modelName = APIConfig.model
    @State private var checking = false
    @State private var keyStatus: String?
    @State private var keyOK = false
    @State private var notify = Notifier.enabled
    @State private var importing = false
    @State private var importMsg: String?

    @ObservedObject private var ap = Appearance.shared
    @State private var daily = Notifier.dailyOn
    @State private var dailyTime = Calendar.current.date(bySettingHour: Notifier.dailyMinutes / 60, minute: Notifier.dailyMinutes % 60, second: 0, of: Date()) ?? Date()
    @State private var backupMsg: String?
    @State private var confirmWipe = false
    @State private var share: ShareItem?
    @State private var showOwnKey = Keychain.hasKey
    @EnvironmentObject var sync: SyncEngine
    @State private var wipeText = ""

    var body: some View {
        NavigationStack {
            Form {
                SyncSettingsSection()

                Section {
                    NavigationLink { AppearanceView() } label: { SettingRow("Оформление", "paintpalette.fill", .pink, detail: "темы, значок, экран") }
                    Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { router.show(.customize) } } label: {
                        SettingRow("Главный экран", "square.grid.2x2.fill", .blue)
                    }
                    NavigationLink { CategoriesView() } label: { SettingRow("Категории", "tag.fill", .orange) }
                    NavigationLink { PetPickerView() } label: { SettingRow("Напарник", "pawprint.fill", .brown, detail: CompanionCatalog.def(CompanionEngine.petID).name) }
                } header: { Text("Под себя") } footer: {
                    Text("Совет: удержите палец на главном экране — блоки можно убирать и добавлять прямо там.")
                }

                Section {
                    Toggle(isOn: $ap.haptics.animation()) { SettingRow("Вибрация", "iphone.radiowaves.left.and.right", .indigo) }
                        .onChange(of: ap.haptics) { _, v in if v { Haptic.success() } }
                    if ap.haptics {
                        Picker(selection: $ap.hapticStrength) {
                            Text("Мягкая").tag("soft"); Text("Обычная").tag("normal"); Text("Сильная").tag("strong")
                        } label: { SettingRow("Сила", "waveform", .indigo.opacity(0.7)) }
                        .onChange(of: ap.hapticStrength) { _, _ in Haptic.heavy() }
                    }
                    Picker(selection: $ap.motion) {
                        Text("Все").tag("full"); Text("Спокойные").tag("calm"); Text("Выключены").tag("off")
                    } label: { SettingRow("Анимации", "sparkles", .teal) }
                    Toggle(isOn: $ap.confetti) { SettingRow("Конфетти за цели", "party.popper.fill", .yellow) }
                    Toggle(isOn: $ap.sounds) { SettingRow("Звуки", "speaker.wave.2.fill", .purple) }
                        .onChange(of: ap.sounds) { _, v in if v { CompanionSound.xp() } }
                } header: { Text("Ощущения") } footer: {
                    Text("«Спокойные» — без покачиваний и счётчиков, только мягкие переходы. Если в iOS включено «Уменьшение движения», анимации выключаются сами.")
                }

                Section {
                    Toggle(isOn: $ap.showKopecks) { SettingRow("Показывать копейки", "number", .gray) }
                    Toggle(isOn: $ap.alwaysIncome) { SettingRow("Всегда показывать доходы", "arrow.down.left.circle.fill", .green) }
                    Toggle(isOn: $ap.debtInTotals) { SettingRow("Долги в итогах месяца", "creditcard.fill", .red) }
                    Picker(selection: $ap.firstWeekday) {
                        Text("Понедельник").tag(2); Text("Воскресенье").tag(1)
                    } label: { SettingRow("Первый день недели", "calendar", .red.opacity(0.8)) }
                    LabeledContent { Text(budget > 0 ? Fmt.rubU(budget) : "не задан").foregroundStyle(.secondary) } label: { SettingRow("Лимит расходов", "gauge.with.dots.needle.33percent", .mint) }
                } header: { Text("Подсчёты") } footer: {
                    Text("Если «Долги в итогах» выключено, платежи по кредитам и возвраты долгов не попадают в доходы и расходы месяца — только в раздел «Платежи».")
                }

                Section {
                    Toggle(isOn: $notify) { SettingRow("О платежах и подписках", "bell.badge.fill", .red) }
                        .onChange(of: notify) { _, v in
                            Notifier.enabled = v
                            Task {
                                if v { _ = await Notifier.requestPermission() }
                                Notifier.reschedule(ctx: ctx)
                            }
                        }
                    Toggle(isOn: $daily.animation()) { SettingRow("Каждый день «Запишите траты»", "pencil.and.list.clipboard", .orange) }
                        .onChange(of: daily) { _, v in
                            Notifier.dailyOn = v
                            Task { if v { _ = await Notifier.requestPermission() }; Notifier.scheduleDaily() }
                        }
                    if daily {
                        DatePicker(selection: $dailyTime, displayedComponents: .hourAndMinute) { SettingRow("Время", "clock.fill", .orange.opacity(0.7)) }
                            .onChange(of: dailyTime) { _, d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                Notifier.dailyMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
                                Notifier.scheduleDaily()
                            }
                    }
                } header: { Text("Напоминания") } footer: { Text("О кредитах — за день до платежа в 10:00 и в сам день в 9:00. Нажмите на ежедневное напоминание — сразу откроется голосовой ввод.") }

                Section {
                    aiStatusRow
                    DisclosureGroup(isExpanded: $showOwnKey) {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Base URL (необязательно)").font(.caption).foregroundStyle(.secondary)
                        TextField(APIConfig.defaultBase, text: $baseURL)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Модель (необязательно)").font(.caption).foregroundStyle(.secondary)
                        TextField("\(APIConfig.defaultSmart), \(APIConfig.defaultFast)", text: $modelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Button(checking ? "Проверяю…" : "Сохранить и проверить", action: checkKey).disabled(checking || key.isEmpty)
                        Spacer()
                        if Keychain.hasKey { Button("Удалить", role: .destructive) { key = ""; Keychain.apiKey = nil; keyStatus = "Ключ удалён"; keyOK = false } }
                    }
                    if let keyStatus { Text(keyStatus).font(.footnote).foregroundStyle(keyOK ? Theme.inc : Theme.exp) }
                    } label: { SettingRow("Свой ключ и шлюз", "key.fill", .gray, detail: Keychain.hasKey ? "используется" : "необязательно") }
                } header: {
                    Text("Умные функции")
                } footer: {
                    Text("ИИ понимает разговорную речь, читает чеки и делает разбор месяца. После входа в аккаунт он работает через сервер Копилки — ключ вводить не нужно.\n\nСвой ключ — только если хотите платить за ИИ сами. Base URL — адрес шлюза, совместимого с Claude API; модель — идентификатор из API (например, \(APIConfig.defaultSmart)). Хранится в связке ключей iPhone.")
                }

                Section {
                    Button {
                        if let url = Backup.exportFile(ctx: ctx) { share = ShareItem(url: url) } else { backupMsg = "Не удалось собрать копию." }
                    } label: { SettingRow("Сохранить резервную копию", "externaldrive.fill.badge.icloud", .blue) }
                    Button { importing = true } label: { SettingRow("Восстановить из копии", "arrow.counterclockwise.circle.fill", .blue.opacity(0.8)) }
                    Button {
                        if let url = CSV.exportFile(txs: txs, accounts: accs) { share = ShareItem(url: url) }
                    } label: { SettingRow("Экспорт операций в CSV", "tablecells.fill", .green) }
                    Button { importing = true } label: { SettingRow("Импорт CSV", "square.and.arrow.down.fill", .green.opacity(0.8)) }
                    if let m = backupMsg ?? importMsg { Text(m).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Данные") } footer: {
                    Text("Резервная копия — один файл со всем: операциями, счетами, долгами, копилками, категориями и лимитами. Сохраните его в «Файлы» или отправьте себе.")
                }

                Section {
                    NavigationLink { AutomationView() } label: { SettingRow("Siri, виджеты и ссылки", "wand.and.stars", .purple) }
                } header: { Text("Автоматизация") }

                Section {
                    Button(role: .destructive) { wipeText = ""; confirmWipe = true } label: {
                        SettingRow("Стереть все данные", "trash.fill", .red, destructive: true)
                    }
                } footer: {
                    Text("Удалит операции, счета, долги и копилки в текущем пространстве — и на всех устройствах семьи. Перед этим лучше сохранить резервную копию.")
                }

                Section {
                    VStack(spacing: 6) {
                        Image(AppIcons.all.first { $0.id == (UIApplication.shared.alternateIconName ?? "") }?.preview ?? "Preview-Default").resizable().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        Text("Копилка").font(.headline)
                        Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 5) {
                        TestData.shared.unlocked = true
                        Haptic.success()
                        router.say("Проверка на худших данных — переключатель сверху")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText, .plainText, .text]) { res in
                guard case .success(let url) = res else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { importMsg = "Не удалось прочитать файл."; return }
                backupMsg = nil; importMsg = nil
                if let n = Backup.restore(data, ctx: ctx) {
                    Haptic.success(); backupMsg = "Восстановлено записей: \(n)"; return
                }
                guard let text = String(data: data, encoding: .utf8) else { importMsg = "Не удалось прочитать файл."; return }
                let n = CSV.importCSV(text, ctx: ctx)
                importMsg = n > 0 ? "Импортировано операций: \(n)" : "В файле не нашлось операций."
                if n > 0 { Haptic.success() } else { Haptic.warning() }
            }
            .sheet(item: $share) { ShareSheet(items: [$0.url]).presentationDetents([.medium, .large]) }
            .alert("Стереть все данные?", isPresented: $confirmWipe) {
                TextField("Напишите: стереть", text: $wipeText)
                Button("Отмена", role: .cancel) {}
                Button("Стереть", role: .destructive) {
                    guard wipeText.lowercased().trimmingCharacters(in: .whitespaces) == "стереть" else { Haptic.warning(); backupMsg = "Не стёрто: нужно написать «стереть»."; return }
                    Backup.wipe(ctx: ctx)
                    Haptic.heavy()
                    backupMsg = "Все данные стёрты."
                }
            } message: { Text("Это нельзя отменить. Для подтверждения напишите «стереть».") }
        }
    }

    @ViewBuilder private var aiStatusRow: some View {
        if Keychain.hasKey {
            SettingRow("ИИ работает", "sparkles", .purple, detail: "по вашему ключу")
        } else if Claude.usesServer {
            SettingRow("ИИ работает", "sparkles", .purple, detail: "через сервер Копилки")
        } else if !sync.loggedIn {
            NavigationLink { AccountView() } label: {
                SettingRow("Войдите в аккаунт", "sparkles", .purple, detail: "и ИИ заработает без ключа")
            }
        } else {
            SettingRow("ИИ на сервере не настроен", "sparkles", .gray, detail: "голос работает упрощённо")
                .task { await sync.refreshAIStatus() }
        }
    }

    private func checkKey() {
        // проверяем адрес до сохранения, чтобы не оставить приложение с битым URL
        if !baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
            do { _ = try APIConfig.endpoint(for: baseURL) }
            catch { keyOK = false; keyStatus = error.localizedDescription; Haptic.warning(); return }
        }
        Keychain.apiKey = key
        APIConfig.baseURL = baseURL
        APIConfig.model = modelName
        baseURL = APIConfig.baseURL; modelName = APIConfig.model
        checking = true; keyStatus = nil
        Task {
            defer { checking = false }
            do {
                _ = try await Claude.ask("Ответь одним словом: готов", maxTokens: 300)
                keyOK = true
                let host = (try? APIConfig.endpoint())?.host ?? "api.anthropic.com"
                keyStatus = "Работает ✓ · \(host) · \(APIConfig.model.isEmpty ? "модели по умолчанию" : APIConfig.model)"
                Haptic.success()
            } catch {
                keyOK = false; keyStatus = error.localizedDescription
            }
        }
    }
}

/// Строка настроек с цветной иконкой, как в системных «Настройках».
struct SettingRow: View {
    let title: String
    let symbol: String
    let color: Color
    var destructive = false
    var detail: String? = nil
    init(_ title: String, _ symbol: String, _ color: Color, destructive: Bool = false, detail: String? = nil) {
        self.title = title; self.symbol = symbol; self.color = color; self.destructive = destructive; self.detail = detail
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(destructive ? Theme.exp : Color.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Siri, виджеты, кнопка «Действие» и ссылки для «Быстрых команд».
struct AutomationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    struct Link: Identifiable { let id: String; let title: String; let symbol: String }
    let links = [
        Link(id: "voice", title: "Голосовой ввод", symbol: "mic.fill"),
        Link(id: "scan", title: "Скан чека", symbol: "camera.fill"),
        Link(id: "add", title: "Новая операция", symbol: "plus"),
        Link(id: "debts", title: "Платежи и долги", symbol: "calendar"),
        Link(id: "goals", title: "Копилки", symbol: "target"),
        Link(id: "stats", title: "Статистика", symbol: "chart.pie.fill"),
    ]
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("«Привет, Siri, запиши в Копилку»").font(.body.weight(.semibold))
                    Text("Siri спросит, что записать, — скажите своими словами: «кофе двести пятьдесят, такси четыреста». Всё сохранится без открытия приложения.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Виджет и экран блокировки").font(.body.weight(.semibold))
                    Text("Добавьте виджет «Копилка»: кнопки «Голосом», «Скан» и «Вручную» открывают нужный экран сразу. На экране блокировки — круглая кнопка микрофона.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Кнопка «Действие»").font(.body.weight(.semibold))
                    Text("Настройки → Кнопка «Действие» → Быстрая команда → «Записать в Копилку». Зажали кнопку — и говорите.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Без открытия приложения") }
            Section {
                ForEach(links) { l in
                    HStack {
                        Label(l.title, systemImage: l.symbol)
                        Spacer()
                        Text("koshelek://\(l.id)").font(.footnote.monospaced()).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button { UIPasteboard.general.string = "koshelek://\(l.id)"; Haptic.success() } label: { Label("Скопировать ссылку", systemImage: "doc.on.doc") }
                    }
                    .onTapGesture { UIPasteboard.general.string = "koshelek://\(l.id)"; Haptic.success(); router.say("Ссылка скопирована") }
                }
            } header: { Text("Ссылки") } footer: {
                Text("Нажмите, чтобы скопировать. В «Быстрых командах» добавьте действие «Открыть URL» с этой ссылкой — например, по NFC-метке или в автоматизации «Когда прихожу в магазин».")
            }
        }
        .navigationTitle("Автоматизация")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Системное окно «Поделиться» (для файлов, собранных по нажатию).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
