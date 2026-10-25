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
                .offset(y: appeared || !Motion.moves ? 0 : 420)
                .opacity(appeared || Motion.moves ? 1 : 0)
        }
        .animation(Motion.moves ? .timingCurve(0.32, 0.72, 0, 1, duration: 0.42) : (Motion.enabled ? .easeOut(duration: 0.2) : nil), value: appeared)
        .task {
            Haptic.press()
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
        VStack(spacing: 16) {
            HStack {
                Button("Отмена") { close() }
                    .foregroundStyle(.secondary)
                    .disabled(phase == .thinking)
                Spacer()
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(phase == .listening ? Theme.accent : Color.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Готово") { speech.stop(); parse() }
                    .fontWeight(.semibold)
                    .disabled(phase == .thinking || speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.body)

            transcriptView
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)

            if let e = err ?? speech.error {
                Text(e).font(.footnote).foregroundStyle(Theme.exp).frame(maxWidth: .infinity, alignment: .leading)
            }

            Waveform(levels: levels, active: phase == .listening)
                .frame(height: 28)

            HStack {
                SideButton(symbol: "camera", label: "Скан чека") { switchTo { router.scanRequest += 1 } }
                Spacer()
                micButton
                Spacer()
                SideButton(symbol: "keyboard", label: "Вручную") { switchTo { router.show(.newTx) } }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func switchTo(_ action: @escaping () -> Void) {
        speech.onAutoStop = nil
        speech.stop()
        appeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            router.voiceOn = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { action() }
        }
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
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .lineLimit(1...6)
        } else if speech.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Например").font(.footnote).foregroundStyle(.tertiary)
                Text(Self.examples[exampleIndex])
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .id(exampleIndex)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        } else {
            ScrollView {
                Text(speech.transcript)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(phase == .thinking ? 0.5 : 1)
            }
            .frame(maxHeight: 180)
        }
    }

    private var micButton: some View {
        Button {
            editing = false
            Haptic.press()
            if speech.isRecording { speech.stop(); phase = .idle }
            else { phase = .listening; Task { await speech.start(); if !speech.isRecording { phase = .idle } } }
        } label: {
            ZStack {
                if phase == .listening && Motion.moves { PulseRing(color: Theme.exp) }
                Circle()
                    .fill((phase == .listening ? Theme.exp : Theme.accent).opacity(0.16))
                    .frame(width: 76, height: 76)
                    .scaleEffect(phase == .listening ? 1 + CGFloat(speech.level) * 0.35 : 1)
                    .animation(.easeOut(duration: 0.12), value: speech.level)
                Circle()
                    .fill(phase == .listening ? Theme.exp : Theme.accent)
                    .frame(width: 58, height: 58)
                if phase == .thinking {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: phase == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(Pressable(scale: 0.9, haptic: false))
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
                if items.isEmpty { Haptic.warning(); err = error.localizedDescription; phase = .idle; return }
            }
            guard !items.isEmpty else {
                Haptic.warning()
                err = "Не услышал сумм. Скажите, например: «кофе двести пятьдесят»."
                phase = .idle
                return
            }
            speech.onAutoStop = nil
            Haptic.success()
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

struct SideButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .background(Theme.soft, in: Circle())
        }
        .buttonStyle(Pressable(scale: 0.92))
        .accessibilityLabel(label)
    }
}

/// Расходящиеся кольца вокруг микрофона, пока идёт запись.
struct PulseRing: View {
    let color: Color
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 2)
                    .frame(width: 76, height: 76)
                    .scaleEffect(go ? 1.6 : 1)
                    .opacity(go ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.8), value: go)
            }
        }
        .onAppear { go = true }
        .allowsHitTesting(false)
    }
}
