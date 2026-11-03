import SwiftUI
import WidgetKit

/// Обновляет данные для виджетов при каждом изменении (с паузой, чтобы не дёргать систему).
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()
    private var task: Task<Void, Never>?
    private var lastPhoto = ""

    func update(_ store: Store) {
        task?.cancel()
        task = Task { [weak store] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let store else { return }
            await self.write(store)
        }
    }

    private func write(_ store: Store) async {
        guard WidgetShared.hasAccess else { return }
        var s = VDSnapshot()
        s.myName = store.name(.me)
        s.partnerName = store.name(.partner)
        s.myHex = store.p.myHex
        s.partnerHex = store.p.partnerHex
        if let st = store.statusNow(.partner) {
            let k = statusKind(st.kind)
            s.statusTitle = st.title
            s.statusSymbol = k.symbol
            s.statusHex = k.hex
            s.statusNote = [st.place, st.note].filter { !$0.isEmpty }.joined(separator: " · ")
            s.statusStarted = st.started
            s.statusExpires = st.expires
        }
        func mood(_ w: Who) -> JarMood? {
            let today = store.data.jar.filter { $0.who == w && Calendar.current.isDateInToday($0.date) }
            guard let b = today.max(by: { $0.date < $1.date }) else { return nil }
            return jarMoods[min(b.mood, jarMoods.count - 1)]
        }
        s.myMoodEmoji = mood(.me)?.emoji ?? ""
        s.partnerMoodEmoji = mood(.partner)?.emoji ?? ""
        s.partnerMoodTitle = mood(.partner)?.title ?? ""
        s.distanceText = store.distanceKm()?.kmText ?? ""
        s.daysTogether = max(0, Calendar.current.dateComponents([.day], from: store.p.start, to: Date()).day ?? 0)

        if let p = store.data.photos.max(by: { $0.date < $1.date }) {
            s.photoCaption = p.caption
            let key = p.media + p.file
            if key != lastPhoto {
                if let url = ImageCache.url(media: p.media, file: p.file, thumb: "480x0"),
                   let (d, r) = try? await ImageCache.session.data(from: url),
                   (r as? HTTPURLResponse)?.statusCode == 200 {
                    WidgetShared.writePhoto(d)
                    lastPhoto = key
                }
            }
            s.hasPhoto = lastPhoto == key
        } else {
            WidgetShared.removePhoto()
            lastPhoto = ""
        }
        WidgetShared.writeSnapshot(s)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
