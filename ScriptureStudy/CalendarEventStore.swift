import Foundation
import Combine

// MARK: - Calendar Event Model

enum CalendarEventType: String, Codable {
    case prayer   = "prayer"
    case reminder = "reminder"
}

enum CalendarRepeat: String, Codable, CaseIterable {
    case once    = "Once"
    case daily   = "Daily"
    case weekly  = "Weekly"
}

struct CalendarEvent: Identifiable, Codable {
    var id:          UUID              = UUID()
    var text:        String
    var type:        CalendarEventType
    var date:        Date              // the anchored date
    var repeatRule:  CalendarRepeat    = .once
    var isDone:      Bool              = false
    var createdAt:   Date              = Date()

    var symbol: String {
        type == .prayer ? "🙏" : "❗"
    }
}

// MARK: - Store

@MainActor
class CalendarEventStore: ObservableObject {
    @Published var events: [CalendarEvent] = []

    private let storageKey = "calendarEvents"

    init() { load() }

    // MARK: - CRUD

    func add(_ event: CalendarEvent) {
        events.append(event)
        save()
    }

    func delete(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    func toggle(_ event: CalendarEvent) {
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx].isDone.toggle()
            save()
        }
    }

    // MARK: - Query

    /// Events visible on a given date (respects repeat rules)
    func events(for date: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        return events.filter { event in
            switch event.repeatRule {
            case .once:
                return cal.isDate(event.date, inSameDayAs: date)
            case .daily:
                return date >= cal.startOfDay(for: event.date)
            case .weekly:
                return date >= cal.startOfDay(for: event.date) &&
                       cal.component(.weekday, from: event.date) ==
                       cal.component(.weekday, from: date)
            }
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// True if a date has any events
    func hasEvents(on date: Date) -> Bool {
        !events(for: date).isEmpty
    }

    // MARK: - Persistence (UserDefaults for now, iCloud KV later)

    private func save() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data)
        else { return }
        events = decoded
    }
}
