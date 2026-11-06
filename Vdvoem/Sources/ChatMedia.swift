import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - Запись голоса

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var recording = false
    @Published var seconds: Double = 0
    @Published var level: CGFloat = 0
    /// Последние уровни звука для живой картинки при записи.
    @Published var live: [CGFloat] = Array(repeating: 0.04, count: 36)
    private var samples: [Float] = []
    private var rec: AVAudioRecorder?
    private var timer: Timer?
    private(set) var url: URL?

    func start() async -> Bool {
        let ok: Bool = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard ok else { return false }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? s.setActive(true)
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
        ]
        guard let r = try? AVAudioRecorder(url: u, settings: settings) else { return false }
        r.isMeteringEnabled = true
        guard r.record() else { return false }
        rec = r; url = u; recording = true; seconds = 0; samples = []
        live = Array(repeating: 0.04, count: 36)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let r = self.rec else { return }
                r.updateMeters()
                self.seconds = r.currentTime
                let l = max(0, min(1, (r.averagePower(forChannel: 0) + 48) / 48))
                self.level = CGFloat(l)
                self.samples.append(Float(l))
                self.live.removeFirst()
                self.live.append(max(0.04, CGFloat(l)))
                if self.seconds >= 300 { self.recording = false }
            }
        }
        return true
    }

    /// Форма голоса: 44 столбика 0...31 (берётся самый громкий момент каждого отрезка).
    func wave(bars: Int = 44) -> [Int] {
        guard !samples.isEmpty else { return Array(repeating: 6, count: bars) }
        var out: [Int] = []
        let n = samples.count
        for i in 0..<bars {
            let a = i * n / bars, b = max(a + 1, (i + 1) * n / bars)
            let m = samples[a..<min(b, n)].max() ?? 0
            out.append(Int((pow(Double(m), 0.8) * 31).rounded()))
        }
        return out
    }

    /// Останавливает запись. Возвращает файл и длительность (или nil, если слишком коротко / отмена).
    func stop(keep: Bool) -> (URL, Double)? {
        timer?.invalidate(); timer = nil
        let d = rec?.currentTime ?? seconds
        rec?.stop(); rec = nil
        recording = false; level = 0
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        defer { if !keep, let u = url { try? FileManager.default.removeItem(at: u) } }
        guard keep, d >= 0.6, let u = url else { return nil }
        return (u, d)
    }
}

// MARK: - Воспроизведение

@MainActor
final class MediaPlayer: ObservableObject {
    static let shared = MediaPlayer()
    @Published var playingId: UUID?
    @Published var progress: Double = 0
    private(set) var player: AVPlayer?
    private var obs: Any?
    private var end: NSObjectProtocol?

    func toggle(id: UUID, url: URL) {
        if playingId == id { stop(); return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: url)
        player = p; playingId = id; progress = 0
        obs = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self, weak p] t in
            guard let d = p?.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
            Task { @MainActor in self?.progress = min(1, t.seconds / d) }
        }
        end = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
    }

    func seek(id: UUID, fraction: Double) {
        guard playingId == id, let p = player, let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 else { return }
        p.seek(to: CMTime(seconds: d * max(0, min(1, fraction)), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        progress = max(0, min(1, fraction))
    }

    func stop() {
        if let o = obs { player?.removeTimeObserver(o) }
        if let e = end { NotificationCenter.default.removeObserver(e) }
        obs = nil; end = nil
        player?.pause(); player = nil
        playingId = nil; progress = 0
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }
}

func mmss(_ s: Double) -> String {
    let n = Int(s.rounded())
    return String(format: "%d:%02d", n / 60, n % 60)
}

// MARK: - Пузырь голосового

/// Столбики голоса: проигранная часть заливается цветом, рядом с головкой столбики «пружинят».
struct WaveBars: View {
    let bars: [Int]
    let progress: Double
    let active: Bool
    let on: Color

    var body: some View {
        GeometryReader { g in
            let n = bars.count
            let gap: CGFloat = 2.5
            let w = max(2, (g.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<n, id: \.self) { i in
                    let f = Double(i) / Double(max(1, n - 1))
                    let played = f <= progress
                    let near = active ? max(0, 1 - abs(f - progress) * 9) : 0
                    let h = max(4, g.size.height * (0.16 + 0.84 * CGFloat(bars[i]) / 31))
                    Capsule()
                        .fill(on.opacity(played ? 1 : 0.38))
                        .frame(width: w, height: h * (1 + 0.28 * CGFloat(near)))
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: near > 0.2)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

func fallbackWave(_ id: UUID, bars: Int = 44) -> [Int] {
    var h = UInt64(truncatingIfNeeded: id.uuidString.hashValue)
    return (0..<bars).map { _ in
        h = h &* 6364136223846793005 &+ 1442695040888963407
        return 6 + Int((h >> 33) % 20)
    }
}

struct VoiceBubble: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var mp = MediaPlayer.shared
    let m: ChatMessage

    var body: some View {
        let c = store.color(m.from)
        let on = c.onAccent
        let playing = mp.playingId == m.id
        let bars = (m.wave?.count ?? 0) >= 8 ? m.wave! : fallbackWave(m.id)
        let left = max(0, (m.dur ?? 0) * (1 - (playing ? mp.progress : 0)))
        HStack(spacing: 10) {
            Button {
                if let mid = m.media, let f = m.file, let u = ImageCache.url(media: mid, file: f, thumb: nil) {
                    store.tap(); mp.toggle(id: m.id, url: u)
                }
            } label: {
                ZStack {
                    Circle().fill(on)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(c)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 36, height: 36)
                .scaleEffect(playing ? 1.06 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: playing)
            }.buttonStyle(PressStyle())
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { g in
                    WaveBars(bars: bars, progress: playing ? mp.progress : 0, active: playing, on: on)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            if playing { mp.seek(id: m.id, fraction: Double(v.location.x / max(1, g.size.width))) }
                        })
                }.frame(width: 150, height: 26)
                Text(mmss(playing ? left : (m.dur ?? 0))).font(.caption2.monospacedDigit()).foregroundStyle(on.opacity(0.85))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(c, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Живая запись: пульсирующая точка и бегущие столбики голоса.
struct RecordingWave: View {
    @ObservedObject var voice: VoiceRecorder
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 9, height: 9)
                .scaleEffect(1 + voice.level * 0.8)
                .shadow(color: .red.opacity(0.6), radius: 4 + voice.level * 6)
                .animation(.easeOut(duration: 0.08), value: voice.level)
            Text(mmss(voice.seconds)).font(.body.monospacedDigit())
            GeometryReader { g in
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(Array(voice.live.enumerated()), id: \.offset) { i, v in
                        Capsule().fill(color.opacity(0.35 + 0.65 * Double(i) / 36))
                            .frame(width: 3, height: max(4, g.size.height * v))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .animation(.linear(duration: 0.05), value: voice.live)
            }
            .frame(height: 26)
        }
    }
}
