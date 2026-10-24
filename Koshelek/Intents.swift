import AppIntents
import SwiftData
import Foundation

/// «Привет, Siri, запиши в Кошелёк» → Siri спрашивает «Что записать?» → сохраняем без открытия приложения.
struct RecordMoneyIntent: AppIntent {
    static var title: LocalizedStringResource = "Записать в Лад"
    static var description = IntentDescription("Записывает траты, доходы, платежи по кредитам, задачи, покупки и привычки, сказанные своими словами.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Что записать", requestValueDialog: "Что записать?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Store.container.mainContext
        let items: [ParsedItem]
        do { items = try await Brain.parseSpeech(text, ctx: ctx) }
        catch { items = LocalParser.parse(text) }
        guard !items.isEmpty else {
            return .result(dialog: "Не нашёл суммы. Скажите, например: кофе двести пятьдесят.")
        }
        let accs = (try? ctx.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.created)]))) ?? []
        let last = UserDefaults.standard.string(forKey: "lastAcc") ?? ""
        let acc = accs.first { $0.uid.uuidString == last }?.uid ?? accs.first?.uid
        let res = Saver.apply(items, account: acc, ctx: ctx)
        var msg = "Записал: " + res.summary.joined(separator: ", ")
        if let d = res.closedDebt { msg += ". Поздравляю, «\(d)» закрыт!" }
        if let g = res.goalDone { msg += ". Цель «\(g)» достигнута!" }
        return .result(dialog: "\(msg)")
    }
}

/// Открывает экран голосового ввода и сразу включает микрофон.
struct OpenVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Голосовой ввод в Ладе"
    static var description = IntentDescription("Открывает Лад и сразу начинает слушать.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.tab = 0
        Router.shared.show(.voice(auto: true))
        return .result()
    }
}

struct OpenScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Скан чека в Ладе"
    static var description = IntentDescription("Открывает Лад для скана чека или скриншота.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.handle(url: URL(string: "koshelek://scan")!)
        return .result()
    }
}

struct KoshelekShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordMoneyIntent(),
                    phrases: ["Запиши в \(.applicationName)", "Записать в \(.applicationName)", "Добавь в \(.applicationName)", "Запиши трату в \(.applicationName)", "Добавь задачу в \(.applicationName)"],
                    shortTitle: "Записать",
                    systemImageName: "mic.fill")
        AppShortcut(intent: OpenVoiceIntent(),
                    phrases: ["Голосовой ввод в \(.applicationName)", "Открой \(.applicationName) голосом"],
                    shortTitle: "Голосом",
                    systemImageName: "waveform")
        AppShortcut(intent: OpenScanIntent(),
                    phrases: ["Сканируй чек в \(.applicationName)"],
                    shortTitle: "Скан чека",
                    systemImageName: "camera.fill")
    }
}
