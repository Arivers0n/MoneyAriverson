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
        rec = r; url = u; recording = true; seconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let r = self.rec else { return }
                r.updateMeters()
                self.seconds = r.currentTime
                self.level = CGFloat(max(0, min(1, (r.averagePower(forChannel: 0) + 50) / 50)))
                if self.seconds >= 300 { self.recording = false }
            }
        }
        return true
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

struct VoiceBubble: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var mp = MediaPlayer.shared
    let m: ChatMessage

    var body: some View {
        let c = store.color(m.from)
        let on = c.onAccent
        let playing = mp.playingId == m.id
        HStack(spacing: 10) {
            Button {
                if let mid = m.media, let f = m.file, let u = ImageCache.url(media: mid, file: f, thumb: nil) {
                    store.tap(); mp.toggle(id: m.id, url: u)
                }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(c)
                    .frame(width: 34, height: 34).background(on, in: Circle())
            }.buttonStyle(PressStyle())
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(on.opacity(0.35)).frame(height: 4)
                        Capsule().fill(on).frame(width: g.size.width * (playing ? mp.progress : 0), height: 4)
                    }.frame(maxHeight: .infinity)
                }.frame(height: 14)
                Text(mmss(m.dur ?? 0)).font(.caption2.monospacedDigit()).foregroundStyle(on.opacity(0.85))
            }.frame(width: 130)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(c, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Кружок

struct CircleBubble: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var mp = MediaPlayer.shared
    let m: ChatMessage
    private let size: CGFloat = 190

    var body: some View {
        let playing = mp.playingId == m.id
        ZStack {
            Circle().fill(store.color(m.from).opacity(0.25))
            if playing, let p = mp.player {
                VideoLayer(player: p).clipShape(Circle())
            } else {
                Image(systemName: "play.fill").font(.system(size: 34)).foregroundStyle(store.color(m.from))
            }
            Circle().trim(from: 0, to: playing ? mp.progress : 0)
                .stroke(store.color(m.from), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(2)
            VStack { Spacer(); HStack { Text(mmss(m.dur ?? 0)).font(.caption2.monospacedDigit())
                .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white); Spacer() } }
                .padding(14)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            if let mid = m.media, let f = m.file, let u = ImageCache.url(media: mid, file: f, thumb: nil) {
                store.tap(); mp.toggle(id: m.id, url: u)
            }
        }
    }
}

struct VideoLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerView { let v = PlayerView(); v.layer0.player = player; v.layer0.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ v: PlayerView, context: Context) { v.layer0.player = player }
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layer0: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Съёмка кружка

struct CircleCamera: UIViewControllerRepresentable {
    let onDone: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = ["public.movie"]
        p.cameraCaptureMode = .video
        p.cameraDevice = .front
        p.videoMaximumDuration = 30
        p.videoQuality = .typeMedium
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(onDone) }
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (URL?) -> Void
        init(_ d: @escaping (URL?) -> Void) { onDone = d }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.mediaURL] as? URL)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}
