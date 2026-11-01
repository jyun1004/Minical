import AppKit
import SwiftUI

/// The day at a glance, after AbleNotch's lock screen calendar widget: a header that says what is
/// coming and when, the event that matters most right now in large type, and the whole day, from
/// midnight to midnight, as one thin strip: the past filled in, each event a glowing piece in its
/// calendar color, and a glowing dot at the current time. Pointing at an event lights it up;
/// clicking it opens its details in place of the headline.
struct DayOverview: View {
    let day: Date
    @Environment(CalendarModel.self) private var model
    @Environment(\.highlight) private var highlight
    @Environment(\.colorScheme) private var colorScheme
    /// The event under the pointer on the strip.
    @State private var hoveredID: String?
    /// The event whose details are open.
    @State private var detailID: String?

    private let stripHeight: CGFloat = 18

    var body: some View {
        let events = timedEvents()
        TimelineView(.everyMinute) { context in
            let now = context.date
            let isToday = day == model.today
            let focus = isToday ? focusEvent(events, now: now) : events.first
            let detail = events.first { $0.id == detailID }

            VStack(alignment: .leading, spacing: 10) {
                header(events: events, focus: detail ?? focus, isDetail: detail != nil, now: now, isToday: isToday)
                    .frame(height: 15)
                ZStack(alignment: .topLeading) {
                    if let detail {
                        EventDetail(event: detail, day: day, duration: duration) { show(nil) }
                            .transition(.eventSwap)
                    } else {
                        hero(focus)
                            .frame(height: 38)
                            .transition(.eventSwap)
                    }
                }
                strip(events: events, now: isToday ? now : nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
        .onChange(of: hoveredID != nil) { _, pointing in
            if pointing { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if hoveredID != nil { NSCursor.pop() } }
        #if DEBUG
        .onAppear {
            if CommandLine.arguments.contains("--detail") { detailID = timedEvents().first?.id }
        }
        #endif
    }

    private func show(_ id: String?) {
        withAnimation(Motion.panel) { detailID = id }
    }

    // MARK: Header

    private func header(events: [CalendarEvent], focus: CalendarEvent?, isDetail: Bool, now: Date, isToday: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .foregroundStyle(highlight)
            Text(headerTitle(events: events, focus: focus, isDetail: isDetail, now: now, isToday: isToday))
                .contentTransition(.numericText())
            Spacer(minLength: 4)
            if !isDetail, let note = headerNote(events: events, focus: focus, now: now, isToday: isToday) {
                Text(note)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func headerTitle(events: [CalendarEvent], focus: CalendarEvent?, isDetail: Bool, now: Date, isToday: Bool) -> String {
        guard isToday else {
            if let focus, isDetail { return duration(Int(focus.end.timeIntervalSince(focus.start) / 60)) }
            if events.isEmpty { return String(localized: "No Events") }
            return String(localized: "\(events.count) events")
        }
        guard let focus else { return String(localized: "Today") }
        if focus.end <= now { return String(localized: "Ended") }
        if focus.start <= now {
            return String(localized: "Now · \(duration(Int(focus.end.timeIntervalSince(now) / 60))) left")
        }
        let until = duration(Int(focus.start.timeIntervalSince(now) / 60))
        return isDetail ? String(localized: "Starts in \(until)") : String(localized: "Next · in \(until)")
    }

    private func headerNote(events: [CalendarEvent], focus: CalendarEvent?, now: Date, isToday: Bool) -> String? {
        if !isToday {
            return events.isEmpty ? nil : String(localized: "\(duration(busyMinutes(events))) busy")
        }
        let more = events.filter { $0.start > now && $0.id != focus?.id }.count
        return more > 0 ? String(localized: "\(more) more") : nil
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(_ event: CalendarEvent?) -> some View {
        if let event {
            let accent = event.color.eventAccent(for: colorScheme)
            Button { show(event.id) } label: {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(accent)
                        .frame(width: 3.5)
                        .shadow(color: event.color.opacity(0.6), radius: 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayTitle(event))
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(subtitle(event))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.98))
            .help(Text("Show Details"))
            .id(event.id)
            .transition(.eventSwap)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(day == model.today ? String(localized: "Nothing else today") : String(localized: "No Events"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Your day is clear")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.eventSwap)
        }
    }

    // MARK: Strip

    private func strip(events: [CalendarEvent], now: Date?) -> some View {
        let dayMinutes = CGFloat(24 * 60)

        return VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = { (minute: Int) -> CGFloat in width * min(max(CGFloat(minute) / dayMinutes, 0), 1) }
                let placed = TimelineLayout.place(events, on: day, calendar: model.calendar)
                let nowMinute = now.map(minute(of:))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.1))
                        .frame(height: 6)

                    // The part of today already behind us.
                    if let nowMinute {
                        Capsule()
                            .fill(LinearGradient(colors: [Color.primary.opacity(0.1), Color.primary.opacity(0.35)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, x(nowMinute)), height: 6)
                    }

                    // Every event at full height on the one line; overlapping ones stack in start
                    // order, each edged in the card's own background so their ends stay readable.
                    ForEach(placed) { item in
                        let isLive = now.map { item.event.start <= $0 && $0 < item.event.end } ?? false
                        let isPast = now.map { item.event.end <= $0 } ?? false
                        StripSegment(
                            color: item.event.color,
                            isLive: isLive,
                            isPast: isPast,
                            isLit: item.id == hoveredID || item.id == detailID
                        )
                        .frame(width: max(x(item.endMinute) - x(item.startMinute) - 1, 5), height: isLive ? 10 : 8)
                        .offset(x: x(item.startMinute) + 0.5)
                        .zIndex(item.id == hoveredID || item.id == detailID ? 1 : 0)
                    }

                    if let nowMinute {
                        // Just above the bar, so it never sits on an event.
                        Circle()
                            .fill(.primary)
                            .frame(width: 5, height: 5)
                            .offset(x: x(nowMinute) - 2.5, y: -8.5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: stripHeight)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let id = item(at: location, in: placed, x: x)?.id
                        if id != hoveredID { hoveredID = id }
                    case .ended:
                        hoveredID = nil
                    }
                }
                .onTapGesture {
                    // Click an event for its details; click it again, or the empty strip, to close them.
                    show(hoveredID == detailID ? nil : hoveredID)
                }
            }
            .frame(height: stripHeight)

            hourLabels
        }
    }

    /// The event under the pointer, with a few points of slack so short events are easy to hit.
    /// Where events overlap, the shortest wins, since it is the one hardest to point at otherwise.
    private func item(at location: CGPoint, in placed: [TimelineLayout.Placed], x: (Int) -> CGFloat) -> TimelineLayout.Placed? {
        let slack: CGFloat = 3
        return placed
            .filter { x($0.startMinute) - slack <= location.x && location.x <= x($0.endMinute) + slack }
            .min { $0.endMinute - $0.startMinute < $1.endMinute - $1.startMinute }
    }

    private var hourLabels: some View {
        let hours = [0, 6, 12, 18, 24]
        return GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                ForEach(hours, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .alignmentGuide(.leading) { dimensions in
                            // Ends hug the strip's edges; inner labels center on their hour.
                            let position = width * CGFloat(hour) / 24
                            let anchor = hour == 0 ? 0 : hour == 24 ? dimensions.width : dimensions.width / 2
                            return anchor - position
                        }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(height: 12)
    }

    // MARK: Helpers

    /// The event in progress, or else the next one still to come today.
    private func focusEvent(_ events: [CalendarEvent], now: Date) -> CalendarEvent? {
        events.first { $0.start <= now && now < $0.end } ?? events.filter { $0.start > now }.min { $0.start < $1.start }
    }

    private func timedEvents() -> [CalendarEvent] {
        guard let dayEnd = model.calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return (model.eventsByDay[day] ?? [])
            .filter { !$0.isAllDay && !($0.start <= day && $0.end >= dayEnd) }
            .sorted { $0.start < $1.start }
    }

    private func minute(of date: Date) -> Int {
        min(24 * 60, max(0, Int(date.timeIntervalSince(day) / 60)))
    }

    private func busyMinutes(_ events: [CalendarEvent]) -> Int {
        var covered = IndexSet()
        for event in events {
            let start = minute(of: event.start)
            let end = minute(of: event.end)
            if end > start { covered.insert(integersIn: start..<end) }
        }
        return covered.count
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 12 { return String(localized: "Noon") }
        let date = model.calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        return date.formatted(.dateTime.hour().locale(model.calendar.locale ?? AppLocale.current))
    }

    private func subtitle(_ event: CalendarEvent) -> String {
        let time = event.timeDescription(on: day, calendar: model.calendar)
        guard let location = event.location?.split(whereSeparator: \.isNewline).first else { return time }
        return "\(time) · \(location)"
    }

    private func displayTitle(_ event: CalendarEvent) -> String {
        event.title.isEmpty ? String(localized: "(No Title)") : event.title
    }

    private func duration(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        formatter.calendar = model.calendar
        return formatter.string(from: TimeInterval(max(minutes, 1) * 60)) ?? ""
    }
}

/// An event's details, opened from the strip or the headline: when, where, which calendar, notes.
private struct EventDetail: View {
    let event: CalendarEvent
    let day: Date
    let duration: (Int) -> String
    let onClose: () -> Void
    @Environment(CalendarModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = event.color.eventAccent(for: colorScheme)
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(accent)
                    .frame(width: 3.5)
                    .shadow(color: event.color.opacity(0.6), radius: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? String(localized: "(No Title)") : event.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(event.timeDescription(on: day, calendar: model.calendar)) · \(duration(Int(event.end.timeIntervalSince(event.start) / 60)))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .buttonStyle(HoverButtonStyle(size: 20))
                .help(Text("Close"))
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                if let location = event.location {
                    row("mappin.and.ellipse", Text(location))
                }
                if let calendarTitle = event.calendarTitle {
                    row("circle.fill", Text(calendarTitle), tint: event.color)
                }
                if let url = event.url {
                    row("link", Text(url.host() ?? url.absoluteString))
                }
                if let notes = event.notes {
                    row("text.alignleft", Text(notes), lines: 3)
                }
            }
            .padding(.leading, 13.5)

            HStack {
                Spacer()
                Button { SystemCalendar.show(event) } label: {
                    Label("Open in Calendar", systemImage: "arrow.up.forward")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(CapsuleButtonStyle())
            }
        }
    }

    private func row(_ symbol: String, _ text: Text, tint: Color? = nil, lines: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: tint == nil ? 10 : 7, weight: .semibold))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
                .frame(width: 12)
            text
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One event on the strip. The event happening right now glows brighter and gently breathes; the
/// one under the pointer (or open in details) glows softly.
private struct StripSegment: View {
    let color: Color
    let isLive: Bool
    let isPast: Bool
    let isLit: Bool

    var body: some View {
        // One even color, so hovering lights the whole event alike. Finished events keep their
        // color but lose their glow, so they read as done without fading into the past behind them.
        Capsule()
            .fill(color.opacity(isPast ? 0.7 : 1))
            .shadow(color: color.opacity(isPast ? 0 : isLive ? 0.5 : 0.45), radius: isLive ? 4 : 3)
            .overlay {
                Capsule().strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
            }
            // A soft glow in the event's own color: enough to say "this one is here", no more.
            .shadow(color: color.opacity(isLit ? 0.55 : 0), radius: 5)
            .brightness(isLit ? 0.06 : 0)
            .animation(Motion.hoverSpring, value: isLit)
    }
}
