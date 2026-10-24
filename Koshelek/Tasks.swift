import Foundation
import EventKit

/// Задачи живут в «Напоминаниях» Apple: так работают привычные уведомления, Siri и виджеты.
@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let due: Date?
        let hasTime: Bool
        let listName: String
        let listColor: CGColor?
        let done: Bool
        var isOverdue: Bool {
            guard let d = due else { return false }
            return hasTime ? d < Date() : d.day0 < Date().day0
        }
    }

    @Published var items: [Item] = []
    @Published var authorized = false
    @Published var denied = false

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        updateStatus()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func updateStatus() {
        let st = EKEventStore.authorizationStatus(for: .reminder)
        authorized = st == .fullAccess
        denied = st == .denied || st == .restricted
    }

    @discardableResult
    func requestAccess() async -> Bool {
        if authorized { return true }
        let ok = (try? await store.requestFullAccessToReminders()) ?? false
        updateStatus()
        if ok { refresh() }
        return ok
    }

    func refresh() {
        guard authorized else { items = []; return }
        let end = Date().addingDays(7)
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        store.fetchReminders(matching: pred) { rems in
            let mapped: [Item] = (rems ?? []).map { r in
                let comps = r.dueDateComponents
                let due = comps.flatMap { cal.date(from: $0) }
                let hasTime = comps?.hour != nil
                return Item(id: r.calendarItemIdentifier, title: r.title ?? "", due: due, hasTime: hasTime,
                            listName: r.calendar?.title ?? "", listColor: r.calendar?.cgColor, done: r.isCompleted)
            }
            let sorted = mapped.sorted { a, b in
                switch (a.due, b.due) {
                case let (x?, y?): return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.title < b.title
                }
            }
            Task { @MainActor in self.items = sorted }
        }
    }

    var today: [Item] { items.filter { $0.due.map { $0.day0 <= Date().day0 } ?? false } }
    var upcoming: [Item] { items.filter { $0.due.map { $0.day0 > Date().day0 } ?? false } }

    func add(title: String, due: Date?, hasTime: Bool) -> Bool {
        guard authorized else { return false }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = store.defaultCalendarForNewReminders()
        if let due {
            let units: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = cal.dateComponents(units, from: due)
            if hasTime { r.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        do { try store.save(r, commit: true); refresh(); return true } catch { return false }
    }

    func complete(_ item: Item) {
        guard let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        r.isCompleted = true
        try? store.save(r, commit: true)
        items.removeAll { $0.id == item.id }
    }
}
