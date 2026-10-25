import Foundation
import AVFoundation
import Speech
import SwiftData
import UserNotifications

// MARK: - Распознавание речи (на русском)

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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var prefix = ""

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        error = nil
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            error = "Разрешите распознавание речи: Настройки → Копилка → Распознавание речи."
            return
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            error = "Разрешите доступ к микрофону: Настройки → Копилка → Микрофон."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Распознавание речи сейчас недоступно. Проверьте интернет."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            request = req
            prefix = transcript.isEmpty ? "" : transcript.trimmingCharacters(in: .whitespaces) + " "

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                req.append(buffer)
                guard let ch = buffer.floatChannelData?[0] else { return }
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in stride(from: 0, to: n, by: 8) { sum += abs(ch[i]) }
                let lvl = min(1, sum / Float(max(1, n / 8)) * 12)
                Task { @MainActor in self?.level = lvl }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            heardThisSession = false
            lastChange = Date()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }

            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let text = self.prefix + result.bestTranscription.formattedString
                        if text != self.transcript { self.lastChange = Date() }
                        if !result.bestTranscription.formattedString.isEmpty { self.heardThisSession = true }
                        self.transcript = text
                        if result.isFinal { self.finish() }
                    }
                    if err != nil && self.isRecording { self.finish() }
                }
            }
        } catch {
            self.error = "Не удалось включить микрофон: \(error.localizedDescription)"
            finish()
        }
    }

    func stop() {
        request?.endAudio()
        finish()
    }

    private func tick() {
        guard isRecording, autoStop, heardThisSession else { return }
        if Date().timeIntervalSince(lastChange) > 1.9 {
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
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
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
    func say(_ t: String) {
        toast = t
        let current = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { if self.toast == current { self.toast = nil } }
    }
    func handle(url: URL) {
        switch url.host ?? "" {
        case "voice": show(.voice(auto: true))
        case "scan": sheet = nil; scanRequest += 1
        case "add": show(.newTx)
        case "debts": show(.payments)
        case "goals", "cards": show(.goals(1))
        case "stats": show(.stats)
        default: break
        }
    }
}
