import SwiftUI
import CoreLocation

// MARK: - Логика новых разделов

extension Store {
    // MARK: Статус

    func statusNow(_ w: Who) -> StatusItem? {
        let now = Date()
        return data.statuses.filter { $0.who == w && $0.expires > now }.max { $0.started < $1.started }
    }

    func setStatus(_ kind: StatusKind, note: String, place: String) {
        var d = data
        let now = Date()
        for i in d.statuses.indices where d.statuses[i].who == .me && d.statuses[i].expires > now {
            d.statuses[i].expires = now
        }
        d.statuses.append(StatusItem(who: .me, kind: kind.id, title: kind.title,
                                     note: note.trimmingCharacters(in: .whitespaces),
                                     place: place.trimmingCharacters(in: .whitespaces)))
        let old = now.addingTimeInterval(-7 * 24 * 3600)
        d.statuses.removeAll { $0.who == .me && $0.expires < old }
        data = d
        success()
    }

    func clearStatus() {
        var d = data
        let now = Date()
        for i in d.statuses.indices where d.statuses[i].who == .me && d.statuses[i].expires > now {
            d.statuses[i].expires = now
        }
        data = d
        tap()
    }

    // MARK: Сон

    func sleep(of w: Who, day: String) -> SleepEntry? {
        data.sleeps.first { $0.who == w && $0.day == day }
    }

    func lastSleep(of w: Who) -> SleepEntry? {
        data.sleeps.filter { $0.who == w }.max { $0.day < $1.day }
    }

    func saveSleep(bed: Date, wake: Date, quality: Int) {
        let day = wake.dayKey
        let id = day + Who.me.rawValue
        var d = data
        let e = SleepEntry(id: id, day: day, who: .me, bedtime: bed, wake: wake, quality: quality)
        if let i = d.sleeps.firstIndex(where: { $0.id == id }) { d.sleeps[i] = e } else { d.sleeps.append(e) }
        data = d
        success()
    }

    // MARK: Трекер

    static let defaultCounters: [TrackerCounter] = [
        TrackerCounter(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, title: "Вода", emoji: "💧", hex: "38BDF8"),
        TrackerCounter(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, title: "Я люблю тебя", emoji: "❤️", hex: "F43F5E"),
        TrackerCounter(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, title: "Объятия", emoji: "🤗", hex: "F59E0B"),
        TrackerCounter(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, title: "Кофе", emoji: "☕", hex: "A0674B")
    ]

    func seedCountersIfNeeded() {
        guard data.counters.isEmpty else { return }
        data.counters = Store.defaultCounters
    }

    func count(_ counter: UUID, who: Who?, on day: Date = Date()) -> Int {
        let c = Calendar.current
        return data.tracks.filter {
            $0.counter == counter && (who == nil || $0.who == who) && c.isDate($0.date, inSameDayAs: day)
        }.count
    }

    func addTrack(_ counter: UUID) {
        data.tracks.append(TrackerEvent(counter: counter, who: .me))
        tap()
    }

    func undoTrack(_ counter: UUID) {
        let mine = data.tracks.filter { $0.counter == counter && $0.who == .me && Calendar.current.isDateInToday($0.date) }
        guard let last = mine.max(by: { $0.date < $1.date }) else { return }
        data.tracks.removeAll { $0.id == last.id }
        tap()
    }

    /// Дней подряд, когда по счётчику была хотя бы одна запись (любого из вас).
    func streak(_ counter: UUID) -> Int {
        let c = Calendar.current
        var day = Date()
        var n = 0
        if count(counter, who: nil, on: day) == 0 { day = c.date(byAdding: .day, value: -1, to: day) ?? day }
        while count(counter, who: nil, on: day) > 0 {
            n += 1
            guard let prev = c.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    // MARK: Банка настроения

    func addBall(mood: Int, note: String) {
        data.jar.append(JarBall(who: .me, mood: mood, note: note.trimmingCharacters(in: .whitespaces)))
        success()
    }

    // MARK: Расстояние

    func place(of w: Who) -> PlacePoint? { data.places.first { $0.who == w } }

    func distanceKm() -> Double? {
        guard let a = place(of: .me), let b = place(of: .partner) else { return nil }
        let x = CLLocation(latitude: a.lat, longitude: a.lon)
        let y = CLLocation(latitude: b.lat, longitude: b.lon)
        return x.distance(from: y) / 1000
    }

    // MARK: Игры

    func wins(_ w: Who) -> Int {
        data.matches.filter { $0.state == .won && $0.winner == w }.count
    }
}

extension Double {
    var kmText: String {
        if self < 1 { return "\(Int(self * 1000)) м" }
        if self < 100 { return String(format: "%.1f км", self).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(self.rounded())) км"
    }
}

extension Date {
    var agoText: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Определение местоположения (по желанию)

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private weak var store: Store?
    private var lastSent: CLLocation?
    private var lastSentAt = Date.distantPast
    @Published var denied = false

    func attach(_ s: Store) {
        store = s
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        apply()
    }

    private var running = false

    func apply(force: Bool = false) {
        guard let s = store else { return }
        if s.p.shareLocation == running && !force { return }
        running = s.p.shareLocation
        if s.p.shareLocation {
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
            manager.startMonitoringSignificantLocationChanges()
            manager.requestLocation()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    func refresh() { if store?.p.shareLocation == true { manager.requestLocation() } }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.apply(force: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.publish(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func publish(_ loc: CLLocation) {
        guard let s = store, s.p.shareLocation else { return }
        let moved = lastSent.map { loc.distance(from: $0) } ?? .infinity
        guard moved > 200 || Date().timeIntervalSince(lastSentAt) > 600 else { return }
        lastSent = loc
        lastSentAt = Date()
        var d = s.data
        let point = PlacePoint(id: Who.me.rawValue, who: .me, lat: loc.coordinate.latitude,
                               lon: loc.coordinate.longitude, updated: Date())
        if let i = d.places.firstIndex(where: { $0.who == .me }) { d.places[i] = point } else { d.places.append(point) }
        s.data = d
    }
}
