import SwiftUI

/// Week mode: the whole week as one list, grouped by day, under a short summary. Day mode shows a
/// single day by the hour; this is for seeing what the week holds at a glance.
struct WeekPage: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        let days = model.weekDays(containing: model.selectedDate)
        ZStack(alignment: .top) {
            Group {
                switch model.access {
                case .notDetermined:
                    AccessPrompt(denied: false) { model.requestAccess() }
                case .denied:
                    AccessPrompt(denied: true) { SystemCalendar.openPrivacySettings() }
                case .granted:
                    VStack(spacing: 8) {
                        WeekSummary(days: days)
                        WeekList(days: days)
                    }
                }
            }
            .id(days.first)
            .transition(.page(direction: model.pageDirection))
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }
}

// MARK: - Summary

private struct WeekSummary: View {
    let days: [Date]
    @Environment(CalendarModel.self) private var model

    var body: some View {
        let stats = WeekStats(days: days, model: model)
        HStack(spacing: 6) {
            tile(stats.eventCount.formatted(), "Events")
            tile(stats.busyText, "Busy")
            tile(stats.busiestDay.map { model.calendar.shortStandaloneWeekdaySymbols[model.calendar.component(.weekday, from: $0) - 1] } ?? "–", "Busiest")
        }
    }

    private func tile(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14.5, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.primary.opacity(0.05))
        }
    }
}

/// Counts the week's own events (holidays aside) and how long they keep you busy. Overlapping
/// events count their shared time once; all-day events add no hours.
private struct WeekStats {
    let eventCount: Int
    let busyMinutes: Int
    let busiestDay: Date?

    init(days: [Date], model: CalendarModel) {
        var ids = Set<String>()
        var minutesByDay: [(Date, Int)] = []
        for day in days {
            let events = (model.eventsByDay[day] ?? []).filter { !$0.isHoliday }
            ids.formUnion(events.map(\.id))
            guard let dayEnd = model.calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let spans = events.filter { !$0.isAllDay }
                .map { (max($0.start, day), min($0.end, dayEnd)) }
                .filter { $0.0 < $0.1 }
                .sorted { $0.0 < $1.0 }
            var total: TimeInterval = 0
            var current: (Date, Date)?
            for span in spans {
                if let open = current, span.0 <= open.1 {
                    current = (open.0, max(open.1, span.1))
                } else {
                    if let open = current { total += open.1.timeIntervalSince(open.0) }
                    current = span
                }
            }
            if let open = current { total += open.1.timeIntervalSince(open.0) }
            minutesByDay.append((day, Int(total / 60)))
        }
        eventCount = ids.count
        busyMinutes = minutesByDay.reduce(0) { $0 + $1.1 }
        busiestDay = minutesByDay.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    /// Past ten hours the minutes are dropped, to keep the tile short.
    var busyText: String {
        busyMinutes >= 600 ? "\(busyMinutes / 60)h" : CalendarEvent.shortDuration(minutes: busyMinutes)
    }
}

// MARK: - Days

private struct WeekList: View {
    let days: [Date]
    @State private var contentHeight: CGFloat = 0

    /// Past this the list scrolls, so a packed week keeps the panel about as tall as the month.
    private static let maxHeight: CGFloat = 440

    var body: some View {
        let overflows = contentHeight > Self.maxHeight
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    if index > 0 { Divider().opacity(0.6) }
                    WeekDayRow(day: day)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, Self.maxHeight))
        // Rows past the cap fade out instead of being cut.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: overflows ? 0.9 : 1),
                                     .init(color: overflows ? .clear : .black, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}

private struct WeekDayRow: View {
    let day: Date
    @Environment(CalendarModel.self) private var model
    @Environment(\.highlight) private var highlight

    var body: some View {
        let events = model.eventsByDay[day] ?? []
        let isToday = day == model.today
        HStack(alignment: .top, spacing: 8) {
            Button { showDay() } label: {
                VStack(spacing: 0) {
                    Text(Self.weekday(day, calendar: model.calendar))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isToday ? AnyShapeStyle(highlight) : AnyShapeStyle(.secondary))
                    Text(model.calendar.component(.day, from: day).formatted())
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? AnyShapeStyle(highlight) : AnyShapeStyle(.primary))
                }
                .frame(width: 34, height: Self.labelHeight)
            }
            .buttonStyle(RowButtonStyle())
            .help(Text("Show in Day View"))

            VStack(spacing: 0) {
                if events.isEmpty {
                    Text("No events")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: Self.labelHeight, alignment: .leading)
                        .padding(.leading, 6)
                } else {
                    // A lone event stands as tall as the date beside it.
                    ForEach(events) { event in
                        WeekEventRow(event: event, day: day, height: events.count == 1 ? Self.labelHeight : 22)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(day < model.today ? 0.45 : 1)
    }

    private static let labelHeight: CGFloat = 36

    private func showDay() {
        model.select(day)
        model.setMode(.day)
    }

    private static func weekday(_ day: Date, calendar: Calendar) -> String {
        calendar.shortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day) - 1].uppercased()
    }
}

private struct WeekEventRow: View {
    let event: CalendarEvent
    let day: Date
    let height: CGFloat
    @Environment(CalendarModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = event.color.eventAccent(for: colorScheme)
        Button { SystemCalendar.show(event) } label: {
            HStack(spacing: 7) {
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: height - 8)
                Text(time)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 56, alignment: .leading)
                Text(event.title.isEmpty ? String(localized: "(No Title)") : event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isAllDay ? AnyShapeStyle(accent) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: height)
            .opacity(event.isPast && day >= model.today ? 0.5 : 1)
        }
        .buttonStyle(RowButtonStyle())
        .help(Text("Open in Calendar"))
        .contextMenu {
            Button("Open in Calendar") { SystemCalendar.show(event) }
        }
    }

    private var isAllDay: Bool { event.fillsDay(day, calendar: model.calendar) }

    /// The start time ("10 AM", "9:30 AM"); an event carried over from an earlier day shows when
    /// it ends instead.
    private var time: String {
        if isAllDay { return String(localized: "All Day") }
        let text = CalendarEvent.shortTime(event.start < day ? event.end : event.start, calendar: model.calendar)
        return event.start < day ? "→ \(text)" : text
    }
}
