import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    @Query(sort: \Tx.date) private var txs: [Tx]
    @Query(sort: \Account.created) private var accs: [Account]
    @AppStorage("budget") private var budget: Double = 0

    @State private var key = Keychain.apiKey ?? ""
    @State private var checking = false
    @State private var keyStatus: String?
    @State private var keyOK = false
    @State private var notify = Notifier.enabled
    @State private var importing = false
    @State private var importMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button(checking ? "Проверяю…" : "Сохранить и проверить", action: checkKey).disabled(checking || key.isEmpty)
                        Spacer()
                        if Keychain.hasKey { Button("Удалить", role: .destructive) { key = ""; Keychain.apiKey = nil; keyStatus = "Ключ удалён" } }
                    }
                    if let keyStatus { Text(keyStatus).font(.footnote).foregroundStyle(keyOK ? Theme.inc : Theme.exp) }
                } header: {
                    Text("Ключ Claude API")
                } footer: {
                    Text("Нужен, чтобы понимать разговорную речь, сканировать чеки и графики и делать разбор месяца. Ключ создаётся на console.anthropic.com → API Keys, баланс пополняется там же. Одна запись стоит доли копейки. Ключ хранится в связке ключей iPhone.")
                }

                Section("Бюджет") {
                    LabeledContent("Лимит расходов", value: budget > 0 ? Fmt.rubU(budget) : "не задан")
                }

                Section {
                    Toggle("Напоминать о платежах", isOn: $notify)
                        .onChange(of: notify) { _, v in
                            Notifier.enabled = v
                            Task {
                                if v { _ = await Notifier.requestPermission() }
                                Notifier.reschedule(ctx: ctx)
                            }
                        }
                } footer: { Text("За день до платежа по кредиту в 10:00 и в сам день в 9:00, а также о подписках и регулярных платежах.") }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("«Привет, Siri, запиши в Лад»").font(.body.weight(.semibold))
                        Text("Siri спросит, что записать, — скажите своими словами: «кофе двести пятьдесят, такси четыреста». Всё сохранится без открытия приложения.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Виджет и экран блокировки").font(.body.weight(.semibold))
                        Text("Добавьте виджет «Лад»: кнопки «Голосом», «Скан» и «Вручную» открывают нужный экран сразу. На экране блокировки — круглая кнопка микрофона.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Кнопка «Действие»").font(.body.weight(.semibold))
                        Text("Настройки → Кнопка «Действие» → Быстрая команда → «Записать в Лад». Зажали кнопку — и говорите.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Без открытия приложения") }

                Section {
                    Button("Импортировать CSV из веб-версии") { importing = true }
                    if let url = CSV.exportFile(txs: txs, accounts: accs) {
                        ShareLink("Выгрузить все операции в CSV", item: url)
                    }
                    if let importMsg { Text(importMsg).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Данные") } footer: {
                    Text("Чтобы перенести операции из веб-версии Кошелька (claude.ai): там во вкладке «Анализ» нажмите «Скачать CSV», а здесь — «Импортировать».")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { res in
                guard case .success(let url) = res else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { importMsg = "Не удалось прочитать файл."; return }
                let n = CSV.importCSV(text, ctx: ctx)
                importMsg = n > 0 ? "Импортировано операций: \(n)" : "В файле не нашлось операций."
            }
        }
    }

    private func checkKey() {
        Keychain.apiKey = key
        checking = true; keyStatus = nil
        Task {
            defer { checking = false }
            do {
                _ = try await Claude.ask("Ответь одним словом: готов", maxTokens: 300)
                keyOK = true; keyStatus = "Ключ работает ✓"
            } catch {
                keyOK = false; keyStatus = error.localizedDescription
            }
        }
    }
}
