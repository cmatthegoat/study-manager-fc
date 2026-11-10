import AppKit
import EventKit
import Observation

/// A read-only window onto the user's own calendars. Nothing here ever writes to a calendar
/// or a reminder list, so the overlay can never damage anything: it only reads a range of
/// events and hands them to the month grid.
@Observable
final class AppleCalendar {
    /// One event as the grid needs it: a day, a title and the calendar's colour.
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let day: Date
        let isAllDay: Bool
        let colorHex: String
        let calendarName: String
    }

    enum Access {
        case unknown
        case denied
        case granted
    }

    var access: Access = .unknown
    private(set) var items: [Item] = []
    @ObservationIgnored private let eventStore = EKEventStore()

    /// The events on one day, in start order, for the day-detail card.
    func items(on day: Date, calendar: Calendar = .current) -> [Item] {
        items.filter { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// Asks once. macOS shows its own prompt the first time; a denial is remembered by the
    /// system, so the view offers a trip to System Settings instead of asking again.
    func requestAccess() async {
        guard #available(macOS 14.0, *) else {
            access = .denied
            return
        }
        let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        access = granted ? .granted : .denied
    }

    /// Reads every calendar the user has allowed. The range is deliberately small — a month
    /// either side of what is on screen — so the app never walks a decade of history.
    func load(around day: Date, calendar: Calendar = .current) {
        guard access == .granted else { return }
        guard let start = calendar.date(byAdding: .month, value: -1, to: day),
              let end = calendar.date(byAdding: .month, value: 2, to: day) else { return }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
        items = events.map { event in
            Item(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Event",
                day: calendar.startOfDay(for: event.startDate),
                isAllDay: event.isAllDay,
                colorHex: Self.hex(for: event.calendar),
                calendarName: event.calendar?.title ?? "Calendar"
            )
        }
    }

    private static func hex(for calendar: EKCalendar?) -> String {
        guard let cgColor = calendar?.cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return "6E7B8B"
        }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
