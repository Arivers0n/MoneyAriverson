import Foundation
import AVFoundation
import Speech
import SwiftData
import UserNotifications

// MARK: - Распознавание речи (на русском)

/// Голос → текст. На iOS 26 — новый движок SpeechAnalyzer (на устройстве, текст появляется мгновенно),
/// иначе — классический SFSpeechRecognizer (по возможности тоже на устройстве).
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var level: Float = 0
    @Published var error: String?
    /// Остановиться самому, если человек замолчал (после того как что-то сказал).
    var autoStop = true
    var onAutoStop: (() -> Void)?
    private var lastChange = Date()
    private var heardThisSession = false
    private var timer: Timer?

    private let locale = Locale(identifier: "ru-RU")
    private lazy var recognizer = SFSpeechRecognizer(locale: locale)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var modern: AnyObject?
    private var prefix = ""

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    /// Заранее спросить разрешения и подготовить модель — чтобы запись стартовала без пауз.
    static func warmUp() {
        if #available(iOS 26.0, *) { Task.detached(priority: .background) { await ModernSpeech.prepareAssets() } }
    }

    func start() async {
        error = nil
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let s = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
            guard s == .authorized else {
                error = "Разрешите распознавание речи: Настройки → Копилка → Распознавание речи."
                return
            }
        }
        if AVAudioApplication.shared.recordPermission != .granted {
            guard await AVAudioApplication.requestRecordPermission() else {
                error = "Разрешите доступ к микрофону: Настройки → Копилка → Микрофон."
                return
            }
        }
        prefix = transcript.isEmpty ? "" : transcript.trimmingCharacters(in: .whitespaces) + " "
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            if #available(iOS 26.0, *), let m = await ModernSpeech.makeIfReady(locale: locale) {
                modern = m
                try startEngine { m.feed($0) }
                m.run { [weak self] text in
                    Task { @MainActor in self?.update(text) }
                }
            } else {
                try startClassic()
            }
            isRecording = true
            heardThisSession = false
            lastChange = Date()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            self.error = "Не удалось включить микрофон: \(error.localizedDescription)"
            finish()
        }
    }

    private func startClassic() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "распознавание речи сейчас недоступно, проверьте интернет"])
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }   // быстрее и без интернета
        request = req
        try startEngine { req.append($0) }
        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.update(text) }
                if final || (err != nil && self.isRecording) { self.finish() }
            }
        }
    }

    private func startEngine(_ feed: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            feed(buffer)
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in stride(from: 0, to: n, by: 4) { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(1, n / 4)))
            let lvl = min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 40))   // −50…−10 дБ → 0…1
            Task { @MainActor in
                guard let self else { return }
                self.level = self.level * 0.55 + lvl * 0.45   // сглаживание
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func update(_ text: String) {
        let full = prefix + text
        if full != transcript { lastChange = Date() }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { heardThisSession = true }
        transcript = full
    }

    func stop() {
        request?.endAudio()
        finish()
    }

    private func tick() {
        guard isRecording, autoStop, heardThisSession else { return }
        if Date().timeIntervalSince(lastChange) > 1.6 {
            stop()
            onAutoStop?()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task?.finish()
        task = nil
        if #available(iOS 26.0, *), let m = modern as? ModernSpeech { m.finish() }
        modern = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Новый движок iOS 26: модель на устройстве, «живые» (volatile) результаты почти без задержки.
@available(iOS 26.0, *)
final class ModernSpeech: @unchecked Sendable {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>
    private let cont: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?

    private init(transcriber: SpeechTranscriber, format: AVAudioFormat) {
        self.transcriber = transcriber
        self.analyzer = SpeechAnalyzer(modules: [transcriber])
        self.format = format
        (input, cont) = AsyncStream<AnalyzerInput>.makeStream()
    }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Скачать модель русского языка заранее (один раз, в фоне).
    static func prepareAssets() async {
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ru-RU")) else { return }
        let t = makeTranscriber(loc)
        if let req = try? await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try? await req.downloadAndInstall()
        }
    }

    /// Готовый к работе движок — или nil, если модель ещё не скачана (тогда работает классический).
    static func makeIfReady(locale: Locale) async -> ModernSpeech? {
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == loc.identifier(.bcp47) }) else {
            Task.detached(priority: .background) { await prepareAssets() }
            return nil
        }
        let t = makeTranscriber(loc)
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else { return nil }
        let m = ModernSpeech(transcriber: t, format: fmt)
        do { try await m.analyzer.start(inputSequence: m.input) } catch { return nil }
        return m
    }

    func run(onText: @escaping (String) -> Void) {
        let transcriber = self.transcriber
        resultsTask = Task {
            var finalized = ""
            do {
                for try await r in transcriber.results {
                    let piece = String(r.text.characters)
                    if r.isFinal {
                        finalized = Self.join(finalized, piece)
                        onText(finalized)
                    } else {
                        onText(Self.join(finalized, piece))
                    }
                }
            } catch {}
        }
    }

    private static func join(_ a: String, _ b: String) -> String {
        let b = b.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    /// Вызывается из аудиопотока.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let out = convert(buffer) else { return }
        cont.yield(AnalyzerInput(buffer: out))
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return nil }
        var used = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if used { status.pointee = .noDataNow; return nil }
            used = true
            status.pointee = .haveData
            return buffer
        }
        return err == nil ? out : nil
    }

    func finish() {
        cont.finish()
        let analyzer = self.analyzer
        let task = resultsTask
        Task {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            task?.cancel()
        }
    }
}

// MARK: - Уведомления о платежах

@MainActor
enum Notifier {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "notify") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notify") }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(ctx: ModelContext) {
        let center = UNUserNotificationCenter.current()
        if TestData.isActive { return }   // на тестовых данных уведомления не трогаем
        center.removeAllPendingNotificationRequests()
        guard enabled else { scheduleDaily(center); return }
        let debts = ctx.live(Debt.self)
        let recs = ctx.live(Recurring.self)
        let now = Date()
        var items: [(Date, String, String)] = []

        for x in allInstallments(debts) where x.isOpen && x.due.day0 >= now.day0 {
            let dayBefore = cal.date(bySettingHour: 10, minute: 0, second: 0, of: x.due.addingDays(-1)) ?? x.due
            let sameDay = cal.date(bySettingHour: 9, minute: 0, second: 0, of: x.due) ?? x.due
            let verb = x.debt.isOut ? "Платёж" : "Вам должны вернуть"
            if dayBefore > now { items.append((dayBefore, "Завтра платёж: \(x.debt.name)", "\(verb) \(Fmt.rubU(x.amount)) — \(DF.short(x.due)).")) }
            if sameDay > now { items.append((sameDay, "Сегодня платёж: \(x.debt.name)", "\(Fmt.rubU(x.amount)). Не забудьте отметить оплату в Копилке.")) }
        }
        for r in recs {
            for k in 0..<3 {
                let m = now.addingMonths(k)
                guard let d = r.due(in: m) else { continue }
                let at = cal.date(bySettingHour: 10, minute: 0, second: 0, of: d) ?? d
                if at > now { items.append((at, r.name, "\(r.kind == .inc ? "Поступление" : "Списание") \(Fmt.rubU(r.amount)). Запишите в Копилку одним касанием.")) }
            }
        }
        for (i, it) in items.sorted(by: { $0.0 < $1.0 }).prefix(60).enumerated() {
            let c = UNMutableNotificationContent()
            c.title = it.1
            c.body = it.2
            c.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: it.0)
            let req = UNNotificationRequest(identifier: "k\(i)", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(req)
        }
        scheduleDaily(center)
    }

    // Ежедневное напоминание «Запишите траты»
    static var dailyOn: Bool {
        get { UserDefaults.standard.bool(forKey: "notify.daily") }
        set { UserDefaults.standard.set(newValue, forKey: "notify.daily") }
    }
    /// Минуты от полуночи, по умолчанию 21:00.
    static var dailyMinutes: Int {
        get { UserDefaults.standard.object(forKey: "notify.dailyMin") as? Int ?? 21 * 60 }
        set { UserDefaults.standard.set(newValue, forKey: "notify.dailyMin") }
    }
    static let dailyPhrases = [
        "Пара секунд: что сегодня потратили? Скажите голосом 🎙",
        "Запишите траты за день — завтра не вспомните, куда ушли деньги.",
        "Вечерняя сверка: кофе, такси, магазин? Одно касание — и готово.",
        "Копилка ждёт. Что сегодня было — траты или день без трат? 🌿",
    ]
    static func scheduleDaily(_ center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: ["daily"])
        guard dailyOn else { return }
        let c = UNMutableNotificationContent()
        c.title = "Копилка"
        c.body = dailyPhrases.randomElement() ?? dailyPhrases[0]
        c.sound = .default
        c.userInfo = ["url": "koshelek://voice"]
        var comps = DateComponents()
        comps.hour = dailyMinutes / 60
        comps.minute = dailyMinutes % 60
        center.add(UNNotificationRequest(identifier: "daily", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}

// MARK: - Навигация между экранами

struct ReviewPayload: Identifiable {
    let id = UUID()
    var items: [ParsedItem]
    var subtitle: String
}

enum Route: Identifiable {
    case voice(auto: Bool)
    case review(ReviewPayload)
    case newTx
    case editTx(Tx)
    case settings
    case stats, payments, search, insights, accounts, customize
    case goals(Int)
    var id: String {
        switch self {
        case .voice: return "voice"
        case .review(let p): return "review-\(p.id)"
        case .newTx: return "new"
        case .editTx(let t): return "tx-\(t.uid)"
        case .settings: return "settings"
        case .stats: return "stats"
        case .payments: return "payments"
        case .search: return "search"
        case .insights: return "insights"
        case .accounts: return "accounts"
        case .customize: return "customize"
        case .goals(let t): return "goals-\(t)"
        }
    }
}

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var sheet: Route?
    @Published var tab = 0
    @Published var busy: String?
    @Published var toast: String?
    @Published var scanRequest = 0
    @Published var celebrate: (String, String)?
    @Published var voiceOn = false
    @Published var voiceRelease = 0

    /// Фильтр ленты и анализа по счёту (nil — все счета)
    @Published var accFilter: UUID?

    func startVoice() {
        sheet = nil
        voiceOn = true
    }

    func show(_ r: Route) {
        if case .voice = r { startVoice(); return }
        if sheet != nil {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.sheet = r }
        } else { sheet = r }
    }
    /// Действие для кнопки «Отменить» в подсказке снизу.
    @Published var undo: (() -> Void)?
    private var toastToken = 0
    func say(_ t: String, undo: (() -> Void)? = nil) {
        toastToken += 1
        let token = toastToken
        self.undo = undo
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + (undo == nil ? 2.6 : 4.5)) {
            if self.toastToken == token { self.toast = nil; self.undo = nil }
        }
    }
    func runUndo() {
        let u = undo
        undo = nil
        toast = nil
        Haptic.tap()
        u?()
    }
    func handle(url: URL) {
        switch url.host ?? "" {
        case "voice": show(.voice(auto: true))
        case "scan": sheet = nil; scanRequest += 1
        case "add": show(.newTx)
        case "debts": show(.payments)
        case "goals", "cards": show(.goals(1))
        case "stats": show(.stats)
        case "connect":
            // Приглашение: koshelek://connect?server=https://money.example.ru&code=ABC123
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let server = items.first { $0.name == "server" }?.value ?? ""
            let code = (items.first { $0.name == "code" }?.value ?? "").uppercased()
            let sync = SyncEngine.shared
            if !code.isEmpty { UserDefaults.standard.set(code, forKey: "pendingJoin") }
            if !sync.loggedIn {
                if !server.isEmpty { sync.server = SyncEngine.normalize(server) }
                say("Сервер уже указан — войдите или зарегистрируйтесь")
                // при первом запуске экран входа и так открыт; иначе ведём в настройки
                if UserDefaults.standard.bool(forKey: "welcome.done") { show(.settings) }
            } else if !code.isEmpty {
                Task { await sync.joinPending(ctx: TestData.shared.context) }
            }
        default: break
        }
    }
}
