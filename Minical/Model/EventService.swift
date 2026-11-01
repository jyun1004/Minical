import EventKit
import Foundation

/// Owns the `EKEventStore` and runs fetches off the main thread, so paging never waits on EventKit.
nonisolated final class EventService: @unchecked Sendable {
    let store = EKEventStore()
    private let queue = DispatchQueue(label: "com.jyun1004.Minical.events", qos: .userInitiated)

    /// Events in `[start, end)`, bucketed by the start of every day they touch.
    func events(
        from start: Date,
        to end: Date,
        hiddenCalendarIDs: Set<String>,
        calendar: Calendar
    ) async -> [Date: [CalendarEvent]] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let calendars = self.store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
                guard !calendars.isEmpty else {
                    continuation.resume(returning: [:])
                    return
                }

                let predicate = self.store.predicateForEvents(withStart: start, end: end, calendars: calendars)
                var result: [Date: [CalendarEvent]] = [:]
                for event in self.store.events(matching: predicate) {
                    let item = CalendarEvent(event)
                    // Spread multi-day events over every day they touch, clamped to the requested range.
                    let lastMoment = item.end > item.start ? item.end.addingTimeInterval(-1) : item.start
                    var day = calendar.startOfDay(for: max(item.start, start))
                    let lastDay = calendar.startOfDay(for: min(lastMoment, end.addingTimeInterval(-1)))
                    while day <= lastDay {
                        result[day, default: []].append(item)
                        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                        day = next
                    }
                }
                for key in result.keys {
                    result[key]?.sort(by: CalendarEvent.displayOrder)
                }
                continuation.resume(returning: result)
            }
        }
    }
}

/// What the composer collects before it becomes an `EKEvent`.
struct EventDraft {
    var title = ""
    var isAllDay = false
    var start: Date
    var end: Date
    var calendarID: String?
}
