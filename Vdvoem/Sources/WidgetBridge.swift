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

        fillExtras(&s, store)

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

    /// Данные для дополнительных виджетов: задачи, даты, планы, хотелки, фильмы, капсула, голосование, игры, питомец.
    private func fillExtras(_ s: inout VDSnapshot, _ store: Store) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func tag(_ w: Who?) -> String { w == .me ? "me" : (w == .partner ? "partner" : "") }

        let open = store.data.tasks.filter { !$0.done }
        s.tasks = open.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.priority > b.priority
            }
        }.prefix(14).map { WTask(title: $0.title, who: tag($0.owner), due: $0.due, priority: $0.priority) }
        s.tasksDone = store.data.tasks.filter { $0.done }.count

        var evs: [WEvent] = []
        for e in store.data.events {
            var d: Date?
            if !e.yearly { d = cal.startOfDay(for: e.date) >= today ? cal.startOfDay(for: e.date) : nil }
            else {
                var c = cal.dateComponents([.month, .day], from: e.date)
                for add in 0...1 {
                    c.year = cal.component(.year, from: today) + add
                    if let x = cal.date(from: c), x >= today { d = x; break }
                }
            }
            if let d { evs.append(WEvent(title: e.title, emoji: e.emoji, date: d)) }
        }
        s.events = Array(evs.sorted { $0.date < $1.date }.prefix(16))

        s.plans = store.data.plans.prefix(4).map {
            WPlan(title: $0.title, emoji: $0.emoji, done: $0.steps.filter { $0.done }.count, total: $0.steps.count, target: $0.target)
        }

        let pw = store.data.wishes.filter { $0.owner == .partner && !$0.got }
        s.wishesTotal = pw.count
        s.wishes = pw.sorted { $0.priority > $1.priority }.prefix(8).map { $0.title }

        let ms = store.data.movies.filter { $0.state < 2 }
            .sorted { ($0.state == 1 ? 0 : 1, $0.date) < ($1.state == 1 ? 0 : 1, $1.date) }
        s.movies = ms.prefix(14).map { WMovie(title: $0.title, owner: tag($0.owner), state: $0.state, progress: $0.progress, kind: $0.kind) }

        let caps = store.data.capsules.filter { $0.opens > Date() }.sorted { $0.opens < $1.opens }
        s.capsuleCount = caps.count
        s.capsuleTitle = caps.first?.title ?? ""
        s.capsuleOpens = caps.first?.opens

        if let p = store.data.polls.last {
            s.poll = WPoll(question: p.question, options: p.options.map { WOpt(text: $0.text, votes: $0.voters.count, mine: $0.voters.contains(.me)) })
        } else { s.poll = nil }

        s.winsMe = store.data.matches.filter { $0.winner == .me }.count
        s.winsPartner = store.data.matches.filter { $0.winner == .partner }.count
        s.myTurns = store.data.matches.filter { $0.state == .playing && $0.turn == .me }.count

        if let pet = store.data.pets.first {
            s.petName = pet.name
            s.petAgeDays = max(0, cal.dateComponents([.day], from: pet.born, to: Date()).day ?? 0)
            s.petFedHours = max(0, Int(Date().timeIntervalSince(pet.lastFed) / 3600))
        } else { s.petName = "" }

        let todayMsgs = store.data.messages.filter { cal.isDateInToday($0.date) }
        s.messagesToday = todayMsgs.count
        if let last = store.data.messages.last {
            s.lastMessage = last.kind == "voice" ? "🎤 Голосовое" : last.text
        } else { s.lastMessage = "" }
    }
}
