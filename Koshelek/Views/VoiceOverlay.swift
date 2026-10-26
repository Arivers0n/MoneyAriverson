import SwiftUI
import SwiftData

/// Голосовой ввод поверх экрана: размытие, живой текст в «пузыре» и кнопка, которая дышит в такт голосу.
struct VoiceOverlay: View {
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @StateObject private var speech = SpeechRecognizer()

    enum Phase { case listening, idle, thinking }
    @State private var phase: Phase = .listening
    @State private var err: String?
    @State private var appeared = false
    @State private var editing = false
    @FocusState private var focused: Bool
    @State private var hintIndex = 0

    static let hints = [
        "«Кофе 250, такси 400»",
        "«Вчера в Пятёрочке на 1 800 с карты»",
        "«Пришла зарплата 85 тысяч»",
        "«Закинул по кредиту восемь пятьсот»",
        "«Отложил пятёрку на отпуск»",
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Размытый фон приложения
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
                .onTapGesture { if phase != .thinking { close() } }

            VStack(spacing: 26) {
                bubble
                controls
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || !Motion.moves ? 0 : 60)
        }
        .animation(Motion.moves ? .timingCurve(0.32, 0.72, 0, 1, duration: 0.42) : (Motion.enabled ? .easeOut(duration: 0.2) : nil), value: appeared)
        .task {
            Haptic.press()
            appeared = true
            speech.onAutoStop = { parse() }
            await speech.start()
            if !speech.isRecording { phase = .idle }
        }
        .onChange(of: speech.isRecording) { _, rec in
            if !rec && phase == .listening { withAnimation(Motion.spring) { phase = .idle } }
        }
        .onChange(of: router.voiceRelease) { _, _ in
            if speech.isRecording { speech.stop(); parse() }
        }
        .onReceive(Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()) { _ in
            guard speech.transcript.isEmpty else { return }
            withAnimation(Motion.spring) { hintIndex = (hintIndex + 1) % Self.hints.count }
        }
    }

    // MARK: Пузырь с текстом

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                LiveDots(active: phase == .listening, level: CGFloat(speech.level))
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.opacity)
                Spacer()
            }

            Group {
                if editing {
                    TextField("", text: $speech.transcript, axis: .vertical)
                        .focused($focused)
                        .lineLimit(1...6)
                        .submitLabel(.done)
                        .onSubmit { parse() }
                } else if speech.transcript.isEmpty {
                    Text(Self.hints[hintIndex])
                        .foregroundStyle(.white.opacity(0.35))
                        .id(hintIndex)
                        .transition(.blurReplace)
                } else {
                    Text("“\(speech.transcript)”")
                        .foregroundStyle(.white.opacity(phase == .thinking ? 0.5 : 1))
                        .contentTransition(.interpolate)
                        .animation(.easeOut(duration: 0.12), value: speech.transcript)
                        .onTapGesture {
                            guard phase != .thinking else { return }
                            speech.onAutoStop = nil
                            speech.stop()
                            phase = .idle
                            editing = true
                            focused = true
                        }
                }
            }
            .font(.system(size: 22, weight: .medium, design: .rounded).italic())
            .foregroundStyle(.white)
            .tint(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if let e = err ?? speech.error {
                Text(e).font(.footnote).foregroundStyle(Color(hex: "FF8A75"))
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .animation(Motion.spring, value: speech.transcript.isEmpty)
    }

    // MARK: Кнопки

    private var controls: some View {
        HStack(spacing: 22) {
            CircleIcon(symbol: "keyboard", size: 54) {
                switchTo { router.show(.newTx) }
            }
            .opacity(phase == .thinking ? 0.4 : 1)
            .disabled(phase == .thinking)

            MicButton(phase: phase, level: CGFloat(speech.level)) {
                editing = false
                Haptic.press()
                switch phase {
                case .listening:
                    speech.stop()
                    parse()
                case .idle:
                    if speech.transcript.trimmingCharacters(in: .whitespaces).isEmpty {
                        phase = .listening
                        speech.onAutoStop = { parse() }
                        Task { await speech.start(); if !speech.isRecording { phase = .idle } }
                    } else {
                        parse()
                    }
                case .thinking:
                    break
                }
            }

            CircleIcon(symbol: "xmark", size: 54) { close() }
                .opacity(phase == .thinking ? 0.4 : 1)
                .disabled(phase == .thinking)
        }
    }

    private var statusText: String {
        switch phase {
        case .listening: return speech.transcript.isEmpty ? "Я вас слушаю…" : "Говорите — я записываю"
        case .idle: return speech.transcript.isEmpty ? "Нажмите и говорите" : "Нажмите на текст, чтобы поправить"
        case .thinking: return "Разбираю…"
        }
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
        focused = false
        withAnimation(Motion.spring) { phase = .thinking }
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

/// Большая кнопка: дышит в такт голосу, во время разбора — крутится.
private struct MicButton: View {
    let phase: VoiceOverlay.Phase
    let level: CGFloat
    let action: () -> Void

    var body: some View {
        let lv = Motion.enabled ? level : 0
        Button(action: action) {
            ZStack {
                if phase == .listening {
                    Circle().fill(.white.opacity(0.10)).frame(width: 96, height: 96)
                        .scaleEffect(1 + lv * 0.55)
                    Circle().fill(.white.opacity(0.14)).frame(width: 96, height: 96)
                        .scaleEffect(1 + lv * 0.28)
                }
                Circle()
                    .fill(phase == .listening ? Color.white : Theme.accent)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                    .scaleEffect(phase == .listening ? 1 + lv * 0.06 : 1)
                Group {
                    switch phase {
                    case .listening:
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black).frame(width: 28, height: 28)
                    case .idle:
                        Image(systemName: "arrow.up").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.onAccent)
                    case .thinking:
                        ProgressView().tint(Theme.onAccent).controlSize(.large)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            .frame(width: 120, height: 120)
            .animation(.easeOut(duration: 0.08), value: lv)
            .animation(Motion.spring, value: phase)
        }
        .buttonStyle(Pressable(scale: 0.92))
        .disabled(phase == .thinking)
        .accessibilityLabel(phase == .listening ? "Готово" : "Говорить")
    }
}

/// Три полоски, которые прыгают от громкости — живой индикатор записи.
private struct LiveDots: View {
    let active: Bool
    let level: CGFloat
    var body: some View {
        TimelineView(.animation(paused: !active || !Motion.enabled)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(active ? Color(hex: "FF5A4E") : Color.white.opacity(0.35))
                        .frame(width: 4, height: active ? 6 + CGFloat(sin(t * 9 + Double(i) * 1.3) * 0.5 + 0.5) * 12 * max(0.25, level) : 6)
                }
            }
            .frame(height: 18)
        }
    }
}

/// Круглая тёмная кнопка.
private struct CircleIcon: View {
    let symbol: String
    var size: CGFloat = 54
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.82), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08)))
        }
        .buttonStyle(Pressable(scale: 0.9))
    }
}
