import SwiftUI
import SwiftData

/// Голосовой ввод поверх любого экрана: живой текст, волна, автостоп по паузе.
struct VoiceOverlay: View {
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @StateObject private var speech = SpeechRecognizer()

    enum Phase { case listening, idle, thinking }
    @State private var phase: Phase = .listening
    @State private var levels: [CGFloat] = Array(repeating: 0.05, count: 32)
    @State private var err: String?
    @State private var exampleIndex = 0
    @State private var appeared = false
    @FocusState private var editing: Bool

    static let examples = [
        "«Кофе 250, такси 400»",
        "«Вчера в Пятёрочке на 1 800 с карты»",
        "«Пришла зарплата 85 тысяч»",
        "«Закинул по кредиту восемь пятьсот»",
        "«Отложил пятёрку на отпуск»",
        "«Подписка Яндекс 399, каждый месяц 15-го»",
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { if phase != .thinking { close() } }

            panel
                .offset(y: appeared ? 0 : 420)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: appeared)
        .task {
            appeared = true
            speech.onAutoStop = { parse() }
            await speech.start()
            if !speech.isRecording { phase = .idle }
        }
        .onChange(of: speech.level) { _, v in
            levels.removeFirst()
            levels.append(max(0.05, CGFloat(v)))
        }
        .onChange(of: speech.isRecording) { _, rec in
            if !rec && phase == .listening { phase = .idle }
        }
        .onChange(of: router.voiceRelease) { _, _ in
            if speech.isRecording { speech.stop(); parse() }
        }
        .onReceive(Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { exampleIndex = (exampleIndex + 1) % Self.examples.count }
        }
    }

    private var panel: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 38, height: 5)

            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(phase == .listening ? Theme.accent : Color.secondary)
                .animation(.none, value: phase)

            transcriptView
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)

            if let e = err ?? speech.error {
                Text(e).font(.footnote).foregroundStyle(Theme.exp).frame(maxWidth: .infinity, alignment: .leading)
            }

            Waveform(levels: levels, active: phase == .listening)
                .frame(height: 36)

            HStack {
                Button("Отмена") { close() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
                    .disabled(phase == .thinking)
                Spacer()
                micButton
                Spacer()
                Button("Готово") { speech.stop(); parse() }
                    .font(.body.weight(.semibold))
                    .frame(width: 90, alignment: .trailing)
                    .disabled(phase == .thinking || speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(phase == .listening ? "Замолчите — и я сам всё разберу" : "Нажмите на текст, чтобы поправить")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 22)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 30, y: -4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var statusText: String {
        switch phase {
        case .listening: return speech.transcript.isEmpty ? "Слушаю…" : "Слушаю… говорите дальше"
        case .idle: return speech.transcript.isEmpty ? "Нажмите на микрофон и говорите" : "Проверьте и нажмите «Готово»"
        case .thinking: return Keychain.hasKey ? "Claude разбирает…" : "Разбираю…"
        }
    }

    @ViewBuilder private var transcriptView: some View {
        if phase == .idle && !speech.transcript.isEmpty {
            TextField("", text: $speech.transcript, axis: .vertical)
                .focused($editing)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .lineLimit(1...6)
        } else if speech.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Например").font(.footnote).foregroundStyle(.tertiary)
                Text(Self.examples[exampleIndex])
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .id(exampleIndex)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        } else {
            ScrollView {
                Text(speech.transcript)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(phase == .thinking ? 0.5 : 1)
            }
            .frame(maxHeight: 180)
        }
    }

    private var micButton: some View {
        Button {
            editing = false
            if speech.isRecording { speech.stop(); phase = .idle }
            else { phase = .listening; Task { await speech.start(); if !speech.isRecording { phase = .idle } } }
        } label: {
            ZStack {
                Circle()
                    .fill((phase == .listening ? Theme.exp : Theme.accent).opacity(0.16))
                    .frame(width: 84, height: 84)
                    .scaleEffect(phase == .listening ? 1 + CGFloat(speech.level) * 0.35 : 1)
                    .animation(.easeOut(duration: 0.12), value: speech.level)
                Circle()
                    .fill(phase == .listening ? Theme.exp : Theme.accent)
                    .frame(width: 64, height: 64)
                if phase == .thinking {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: phase == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .thinking)
        .accessibilityLabel(phase == .listening ? "Остановить" : "Говорить")
    }

    private func close() {
        speech.onAutoStop = nil
        speech.stop()
        appeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { router.voiceOn = false }
    }

    private func parse() {
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, phase != .thinking else { if text.isEmpty { phase = .idle }; return }
        editing = false
        phase = .thinking
        err = nil
        Task {
            var items: [ParsedItem] = []
            do { items = try await Brain.parseSpeech(text, ctx: ctx) }
            catch {
                items = LocalParser.parse(text)
                if items.isEmpty { err = error.localizedDescription; phase = .idle; return }
            }
            guard !items.isEmpty else {
                err = "Не услышал сумм. Скажите, например: «кофе двести пятьдесят»."
                phase = .idle
                return
            }
            speech.onAutoStop = nil
            appeared = false
            try? await Task.sleep(nanoseconds: 220_000_000)
            router.voiceOn = false
            router.show(.review(ReviewPayload(items: items, subtitle: "«\(text)»")))
        }
    }
}

struct Waveform: View {
    let levels: [CGFloat]
    let active: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(active ? Theme.accent : Color.secondary.opacity(0.4))
                    .frame(width: 4, height: max(4, levels[i] * 36))
            }
        }
        .animation(.easeOut(duration: 0.1), value: levels)
    }
}
