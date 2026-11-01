import SwiftUI

/// Day mode: the whole day at a glance as one horizontal bar, then the detailed hourly timeline.
struct DayPage: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DayOverview(day: model.selectedDate)
                    .id(model.selectedDate)
                    .transition(.page(direction: model.pageDirection))
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 2)
            .padding(.bottom, 10)

            DayTimeline()
        }
    }
}

/// The selected day's all-day events over its hourly timeline. The two share a fixed height:
/// the timeline grows into whatever the all-day row leaves free, so moving between days with and
/// without all-day events never resizes the panel (which read as the whole window blinking).
private struct DayTimeline: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        let days = [model.selectedDate]
        let rows = AllDayRow.rowCount(days: days, isWeek: false, model: model)
        VStack(spacing: 0) {
            AllDayRow(days: days, isWeek: false)
            Divider()
            TimelineScroll(days: days, isWeek: false, hourHeight: 42)
                .frame(height: Layout.timelineHeight + AllDayRow.height(rows: AllDayRow.maxRows) - AllDayRow.height(rows: rows))
        }
        .animation(Motion.page, value: rows)
    }
}

// MARK: - All-day events

private struct AllDayRow: View {
    let days: [Date]
    let isWeek: Bool
    @Environment(CalendarModel.self) private var model

    static let maxRows = 3

    /// The row's full height, bottom padding included, for a number of chip rows.
    static func height(rows: Int) -> CGFloat {
        rows > 0 ? CGFloat(rows) * 18 + CGFloat(rows - 1) * 2 + 6 : 0
    }

    static func rowCount(days: [Date], isWeek: Bool, model: CalendarModel) -> Int {
        min(days.map { allDayEvents(on: $0, model: model).count }.max() ?? 0, isWeek ? 2 : maxRows)
    }

    var body: some View {
        let columns = days.map { day in Self.allDayEvents(on: day, model: model) }
        let rows = Self.rowCount(days: days, isWeek: isWeek, model: model)

        if rows > 0 {
            ZStack {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(Array(zip(days, columns)), id: \.0) { _, events in
                        VStack(spacing: 2) {
                            ForEach(events.prefix(rows)) { event in
                                AllDayChip(event: event, compact: isWeek)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .id(days.first)
                .transition(.page(direction: model.pageDirection))
            }
            .frame(height: CGFloat(rows) * 18 + CGFloat(rows - 1) * 2)
            .clipped()
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 6)
            .transition(.opacity)
        }
    }

    private static func allDayEvents(on day: Date, model: CalendarModel) -> [CalendarEvent] {
        guard let dayEnd = model.calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return (model.eventsByDay[day] ?? []).filter { $0.isAllDay || ($0.start <= day && $0.end >= dayEnd) }
    }
}

private struct AllDayChip: View {
    let event: CalendarEvent
    let compact: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let accent = event.color.eventAccent(for: colorScheme)
        Button { SystemCalendar.show(event) } label: {
            HStack(spacing: 4) {
                if !compact {
                    Image(systemName: "calendar.circle.fill")
                        .font(.system(size: 12))
                }
                Text(event.title.isEmpty ? String(localized: "(No Title)") : event.title)
                    .font(.system(size: compact ? 9.5 : 10.5, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, compact ? 5 : 3)
            .frame(height: 18)
            .background {
                Capsule().fill(event.color.opacity(hovering ? 0.24 : 0.15))
            }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
        .help(Text(event.title))
    }
}

// MARK: - Timeline

private struct TimelineScroll: View {
    let days: [Date]
    let isWeek: Bool
    let hourHeight: CGFloat
    @Environment(CalendarModel.self) private var model

    /// Leaves room above midnight so its label is not clipped.
    private let topInset: CGFloat = 8

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    // Scroll targets a little above each hour line, so its label is never clipped.
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            Color.clear
                                .frame(height: hourHeight)
                                .id(ScrollMark.id(hour))
                        }
                    }
                    .padding(.top, max(0, topInset - 8))

                    HourGrid(hourHeight: hourHeight, topInset: topInset, calendar: model.calendar)

                    ZStack {
                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                DayColumn(day: day, isWeek: isWeek, hourHeight: hourHeight, topInset: topInset)
                                if isWeek, day != days.last {
                                    Rectangle()
                                        .fill(.primary.opacity(0.06))
                                        .frame(width: 1)
                                }
                            }
                        }
                        .id(days.first)
                        .transition(.page(direction: model.pageDirection))
                    }
                    .clipped()
                    .padding(.leading, Layout.timeGutter)
                    .padding(.trailing, Layout.gutter)

                    // In the gap between the hour labels and the columns, clear of every event.
                    if days.contains(model.today) {
                        NowRail(hourHeight: hourHeight, topInset: topInset, calendar: model.calendar)
                            .transition(.opacity)
                    }
                }
                .frame(height: topInset * 2 + hourHeight * 24)
            }
            .scrollIndicators(.never)
            .onAppear { scrollToStart(proxy, animated: false) }
            .onChange(of: model.mode) { scrollToStart(proxy, animated: true) }
        }
    }

    /// An hour before now when today is visible, otherwise the start of a working day.
    private func scrollToStart(_ proxy: ScrollViewProxy, animated: Bool) {
        let hour = days.contains(model.today) ? max(0, model.calendar.component(.hour, from: .now) - 1) : 8
        if animated {
            withAnimation(Motion.panel) { proxy.scrollTo(ScrollMark.id(min(hour, 16)), anchor: .top) }
        } else {
            proxy.scrollTo(ScrollMark.id(min(hour, 16)), anchor: .top)
        }
    }
}

private enum ScrollMark {
    static func id(_ hour: Int) -> String { "mark-\(hour)" }
}

private struct HourGrid: View {
    let hourHeight: CGFloat
    let topInset: CGFloat
    let calendar: Calendar

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<25, id: \.self) { hour in
                HStack(alignment: .center, spacing: 6) {
                    Text(label(hour))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: Layout.timeGutter - 8, alignment: .trailing)
                        .opacity(hour == 0 || hour == 24 ? 0 : 1)
                    Rectangle()
                        .fill(.primary.opacity(0.07))
                        .frame(height: 1)
                }
                .frame(height: 12)
                .padding(.trailing, Layout.gutter)
                .frame(height: hour == 24 ? 12 : hourHeight, alignment: .top)
            }
        }
        // Center each line on its hour boundary.
        .offset(y: topInset - 6)
    }

    private func label(_ hour: Int) -> String {
        guard let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) else { return "" }
        return date.formatted(.dateTime.hour().locale(calendar.locale ?? AppLocale.current))
    }
}

private struct DayColumn: View {
    let day: Date
    let isWeek: Bool
    let hourHeight: CGFloat
    let topInset: CGFloat
    @Environment(CalendarModel.self) private var model
    @Environment(\.highlight) private var highlight

    var body: some View {
        let placed = TimelineLayout.place(events(), on: day, calendar: model.calendar)

        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                // The selected day in week view gets a faint wash; double-click anywhere to add an event.
                Rectangle()
                    .fill(isWeek && day == model.selectedDate ? highlight.opacity(0.045) : .clear)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { value in
                        compose(atY: value.location.y)
                    })
                    .simultaneousGesture(TapGesture().onEnded {
                        if isWeek { model.select(day) }
                    })

                ForEach(placed) { item in
                    let columnWidth = (width - 2) / CGFloat(item.columns)
                    EventBlock(event: item.event, day: day, compact: isWeek, height: height(of: item))
                        .frame(width: max(columnWidth - 1.5, 4), height: height(of: item))
                        .offset(x: 1 + CGFloat(item.column) * columnWidth, y: y(forMinute: item.startMinute))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func events() -> [CalendarEvent] {
        guard let dayEnd = model.calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return (model.eventsByDay[day] ?? []).filter { !$0.isAllDay && !($0.start <= day && $0.end >= dayEnd) }
    }

    private func y(forMinute minute: Int) -> CGFloat {
        topInset + CGFloat(minute) / 60 * hourHeight
    }

    private func height(of item: TimelineLayout.Placed) -> CGFloat {
        max(CGFloat(item.endMinute - item.startMinute) / 60 * hourHeight - 1.5, 16)
    }

    private func compose(atY y: CGFloat) {
        let minutes = Int(((y - topInset) / hourHeight * 60 / 30).rounded(.down)) * 30
        let clamped = min(max(minutes, 0), 23 * 60 + 30)
        guard let start = model.calendar.date(byAdding: .minute, value: clamped, to: day) else { return }
        model.beginComposing(at: start)
    }
}

/// The current time: a thin rail down the edge of the hour gutter, filling in the highlight color
/// over the last few hours and ending in the now dot. Nothing is drawn across the events.
private struct NowRail: View {
    let hourHeight: CGFloat
    let topInset: CGFloat
    let calendar: Calendar
    @Environment(\.highlight) private var highlight

    /// How far back the fill's lit end reaches.
    private let glowLength: CGFloat = 4

    var body: some View {
        TimelineView(.everyMinute) { context in
            let components = calendar.dateComponents([.hour, .minute], from: context.date)
            let hours = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0)) / 60
            let y = topInset + hours * hourHeight
            let glow = min(y - topInset, glowLength * hourHeight)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(.primary.opacity(0.08))
                    .frame(width: 2, height: hourHeight * 24)
                    .offset(y: topInset)
                // The whole day so far, faint at midnight and full at now, so the time gone reads
                // as filled wherever the timeline is scrolled.
                Capsule()
                    .fill(LinearGradient(stops: [.init(color: highlight.opacity(0.35), location: 0),
                                                 .init(color: highlight.opacity(0.55), location: 0.6),
                                                 .init(color: highlight, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: max(0, y - topInset))
                    .offset(y: topInset)
                // Over the last stretch the rail itself lights up toward now: a glow hugging the
                // line, and its core whitening, rather than a haze spread around it.
                Capsule()
                    .fill(LinearGradient(colors: [highlight.opacity(0), highlight.opacity(0.85)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: max(0, glow))
                    .blur(radius: 1.5)
                    .offset(y: y - glow)
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.45)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: max(0, glow))
                    .offset(y: y - glow)
                NowDot(color: highlight)
                    .offset(y: y - NowDot.size / 2)
            }
            .frame(width: NowDot.size + 4)
            .offset(x: Layout.timeGutter - 3 - (NowDot.size + 4) / 2)
        }
        .allowsHitTesting(false)
    }
}

private struct EventBlock: View {
    let event: CalendarEvent
    let day: Date
    let compact: Bool
    let height: CGFloat
    @Environment(CalendarModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.eventTint) private var tint
    @State private var hovering = false

    var body: some View {
        let accent = event.color.eventAccent(for: colorScheme)
        let shape = EventCardShape(top: compact ? 3.5 : 5, bottom: compact ? 5 : 7)
        let title = event.title.isEmpty ? String(localized: "(No Title)") : event.title
        let time = event.timeDescription(on: day, calendar: model.calendar)
        Button { SystemCalendar.show(event) } label: {
            // A short event is one line, centered on the bar; a taller one stacks title over time,
            // with the title's top aligned to the bar's top inset.
            let isShort = height < 30
            HStack(alignment: isShort ? .center : .top, spacing: compact ? 3 : 5) {
                Capsule()
                    .fill(accent)
                    .frame(width: compact ? 2 : 2.5)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 3)
                if isShort {
                    (Text(title).font(.system(size: compact ? 9 : 11, weight: .semibold)).foregroundStyle(accent)
                        + Text(compact ? "" : "  \(time)").font(.system(size: 9.5, weight: .medium)).foregroundStyle(accent.opacity(0.75)))
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.system(size: compact ? 9 : 11, weight: .semibold))
                            .foregroundStyle(accent)
                            .lineLimit(compact ? max(1, Int(height / 12)) : 2)
                        if !compact, height >= 34 {
                            Text(time)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(accent.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.leading, 3)
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(shape.fill(event.color.opacity(tint + (hovering ? 0.1 : 0.04))))
            .clipShape(shape)
            .opacity(event.isPast ? 0.55 : 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.97))
        .help(Text(verbatim: "\(event.title)\n\(event.timeDescription(on: day, calendar: model.calendar))"))
    }
}

// MARK: - Layout

/// Lays overlapping events side by side, like Calendar: events that overlap share a cluster,
/// and each gets the first free column within it.
enum TimelineLayout {
    struct Placed: Identifiable {
        let event: CalendarEvent
        let startMinute: Int
        let endMinute: Int
        var column = 0
        var columns = 1
        var id: String { event.id }
    }

    static func place(_ events: [CalendarEvent], on day: Date, calendar: Calendar) -> [Placed] {
        let items = events.map { event -> Placed in
            let start = max(0, minutes(from: day, to: event.start))
            // Give very short events a visible slot so they never collapse to a sliver.
            let end = min(24 * 60, max(minutes(from: day, to: event.end), start + 20))
            return Placed(event: event, startMinute: start, endMinute: end)
        }
        .sorted { ($0.startMinute, -$0.endMinute) < ($1.startMinute, -$1.endMinute) }

        var result: [Placed] = []
        var cluster: [Placed] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0

        func flush() {
            let count = columnEnds.count
            result += cluster.map { var item = $0; item.columns = count; return item }
            cluster = []
            columnEnds = []
        }

        for var item in items {
            if !cluster.isEmpty, item.startMinute >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= item.startMinute }) {
                item.column = free
                columnEnds[free] = item.endMinute
            } else {
                item.column = columnEnds.count
                columnEnds.append(item.endMinute)
            }
            clusterEnd = max(cluster.isEmpty ? 0 : clusterEnd, item.endMinute)
            cluster.append(item)
        }
        flush()
        return result
    }

    private static func minutes(from day: Date, to date: Date) -> Int {
        Int(date.timeIntervalSince(day) / 60)
    }
}
