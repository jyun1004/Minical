import AppKit
import EventKit
import SwiftUI

/// A value snapshot of an `EKEvent`, safe to diff and render.
nonisolated struct CalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    let eventIdentifier: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    let calendarTitle: String?
    let notes: String?
    let url: URL?
    let isHoliday: Bool

    init(_ event: EKEvent) {
        eventIdentifier = event.eventIdentifier
        // Occurrences of a recurring event share an identifier, so qualify it with the start.
        id = "\(event.eventIdentifier ?? UUID().uuidString)@\(event.startDate.timeIntervalSinceReferenceDate)"
        title = event.title ?? ""
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        color = Color(nsColor: event.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue)
        let trimmedLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        location = trimmedLocation?.isEmpty == false ? trimmedLocation : nil
        calendarTitle = event.calendar?.title
        let trimmedNotes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = trimmedNotes?.isEmpty == false ? trimmedNotes : nil
        url = event.url
        isHoliday = Self.isHolidayCalendar(event.calendar)
    }

    var isPast: Bool { end < .now }

    /// Started and not yet over at `date`; all-day events never count.
    func isUnderway(at date: Date) -> Bool { !isAllDay && start <= date && date < end }

    /// All-day, or running through the whole of `day`: drawn as an all-day event that day.
    func fillsDay(_ day: Date, calendar: Calendar) -> Bool {
        guard !isAllDay, let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return true }
        return start <= day && end >= dayEnd
    }

    /// Which day of a multi-day event `day` is, and how many days it spans; nil for a single day.
    func daySpan(on day: Date, calendar: Calendar) -> (index: Int, count: Int)? {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end > start ? end.addingTimeInterval(-1) : start)
        guard let count = calendar.dateComponents([.day], from: first, to: last).day,
              let index = calendar.dateComponents([.day], from: first, to: day).day, count > 0 else { return nil }
        return (index + 1, count + 1)
    }

    /// A compact clock time: "10 AM" on the hour, "9:30 AM" otherwise.
    static func shortTime(_ date: Date, calendar: Calendar) -> String {
        let style: Date.FormatStyle = calendar.component(.minute, from: date) == 0
            ? .dateTime.hour() : .dateTime.hour().minute()
        return date.formatted(style.locale(AppLocale.current))
    }

    /// A compact length: "45m", "1h", "1h 30m".
    static func shortDuration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    func timeDescription(on day: Date, calendar: Calendar) -> String {
        if isAllDay { return String(localized: "All Day") }
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return "" }
        switch (start < day, end > dayEnd) {
        case (true, true):
            return String(localized: "All Day")
        case (true, false):
            return String(localized: "Until \(end.formatted(Self.timeStyle))")
        case (false, true):
            return String(localized: "From \(start.formatted(Self.timeStyle))")
        case (false, false):
            return Self.intervalFormatter.string(from: start, to: end)
        }
    }

    static func displayOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static var timeStyle: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLocale.current)
    }

    private static let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.locale = AppLocale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Subscribed holiday calendars ("Holidays in South Korea", "대한민국 공휴일", …).
    private static func isHolidayCalendar(_ calendar: EKCalendar?) -> Bool {
        guard let calendar, calendar.type == .subscription else { return false }
        let title = calendar.title.lowercased()
        return ["holiday", "공휴일", "휴일", "祝日", "节假日"].contains { title.contains($0) }
    }
}

struct CalendarGroup: Identifiable {
    let id: String
    let title: String
    let calendars: [CalendarItem]
}

struct CalendarItem: Identifiable {
    let id: String
    let title: String
    let swatch: NSImage
    let allowsNewEvents: Bool

    init(_ calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        allowsNewEvents = calendar.allowsContentModifications
        swatch = Self.swatch(NSColor(cgColor: calendar.cgColor) ?? .systemBlue)
    }

    /// Menus render SF Symbols as templates, so colored dots need a real bitmap.
    private static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
