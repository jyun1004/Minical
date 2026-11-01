import AppKit
import SwiftUI

struct AgendaView: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.selectedDateTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.opacity)
                if let relative = model.selectedRelativeTitle {
                    Text(relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .frame(height: 24)
            .animation(Motion.fade, value: model.selectedDate)

            // Re-rendered each minute, so the event under way (and its taller card) and the past
            // ones follow the clock.
            TimelineView(.everyMinute) { context in
                let height = contentHeight(now: context.date)
                content(now: context.date)
                    .id(model.selectedDate)
                    .transition(.eventSwap)
                    // Fits the day's events (up to a cap), so the panel grows and shrinks with them.
                    .frame(height: height, alignment: .top)
                    .fixedSize(horizontal: false, vertical: height == nil)
                    .animation(Motion.fade, value: model.selectedDate)
            }
        }
        .padding(.horizontal, Layout.gutter - 6)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// The list fits its rows (up to a cap); the access prompt takes its natural height (nil),
    /// however its text wraps.
    private func contentHeight(now: Date) -> CGFloat? {
        guard model.access == .granted else { return nil }
        guard !model.selectedEvents.isEmpty else { return Layout.agendaEmptyHeight }
        return min(listHeight(now: now), Layout.agendaHeight)
    }

    /// Banners and cards with the gaps between them, one more gap between the two groups, and
    /// the list's bottom padding.
    private func listHeight(now: Date) -> CGFloat {
        let (banners, cards) = AgendaGroups.split(model.selectedEvents, day: model.selectedDate, calendar: model.calendar)
        let rows = banners.count + cards.count
        guard rows > 0 else { return 0 }
        let gaps = CGFloat(rows - 1 + (banners.isEmpty || cards.isEmpty ? 0 : 1)) * AgendaGroups.gap
        let cardHeights = cards.reduce(0) { $0 + TimedCard.height(isLive: $1.isUnderway(at: now)) }
        return CGFloat(banners.count) * AllDayBanner.height + cardHeights + gaps + 6
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch model.access {
        case .notDetermined:
            AccessPrompt(denied: false) { model.requestAccess() }
                .padding(.horizontal, 6)
                .padding(.top, 4)
        case .denied:
            AccessPrompt(denied: true) { SystemCalendar.openPrivacySettings() }
                .padding(.horizontal, 6)
                .padding(.top, 4)
        case .granted:
            let (banners, cards) = AgendaGroups.split(model.selectedEvents, day: model.selectedDate, calendar: model.calendar)
            if banners.isEmpty && cards.isEmpty {
                EmptyAgenda()
            } else {
                let overflows = listHeight(now: now) > Layout.agendaHeight
                ScrollView {
                    VStack(spacing: AgendaGroups.gap) {
                        ForEach(banners) { event in
                            AllDayBanner(event: event, day: model.selectedDate, calendar: model.calendar)
                        }
                        if !banners.isEmpty && !cards.isEmpty {
                            Color.clear.frame(height: 0)
                        }
                        let timeWidth = TimedCard.timeWidth(for: cards, day: model.selectedDate, calendar: model.calendar)
                        ForEach(cards) { event in
                            TimedCard(event: event, day: model.selectedDate, calendar: model.calendar, now: now, timeWidth: timeWidth)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                // Rows past the cap fade out instead of being cut.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black, location: overflows ? 0.86 : 1),
                                             .init(color: overflows ? .clear : .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

private struct EmptyAgenda: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            Text("No Events")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            if model.canCreateEvents {
                Button { model.beginComposing() } label: {
                    Label("Add Event", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(CapsuleButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }
}

/// A day's events in the agenda's two groups: all-day banners on top, then timed cards.
private enum AgendaGroups {
    static let gap: CGFloat = 4

    static func split(_ events: [CalendarEvent], day: Date, calendar: Calendar) -> (banners: [CalendarEvent], cards: [CalendarEvent]) {
        let banners = events.filter { $0.fillsDay(day, calendar: calendar) }
        return (banners, events.filter { !$0.fillsDay(day, calendar: calendar) })
    }
}

/// An all-day event: one slim line in a stronger wash of its calendar's color, marked
/// "All Day", or "Day 2 of 3" when it spans several days.
private struct AllDayBanner: View {
    static let height: CGFloat = 26

    let event: CalendarEvent
    let day: Date
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = event.color.eventAccent(for: colorScheme)
        Button { SystemCalendar.show(event) } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(event.title.isEmpty ? String(localized: "(No Title)") : event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(tag)
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(accent.opacity(0.8))
            }
            .padding(.horizontal, 9)
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(EventCardButtonStyle(color: event.color, shape: EventCardShape(top: 7, bottom: 7), extraTint: 0.1))
        .help(Text("Open in Calendar"))
        .contextMenu {
            Button("Open in Calendar") { SystemCalendar.show(event) }
        }
    }

    private var tag: String {
        guard let span = event.daySpan(on: day, calendar: calendar) else { return String(localized: "All Day") }
        return String(localized: "Day \(span.index) of \(span.count)")
    }
}

/// A timed event: its start and end stacked in a column of their own, then the title over the
/// place (or the length). The event under way says how long is left and grows a strip of its own
/// along the bottom with the time gone, a progress track and the share done.
private struct TimedCard: View {
    static let baseHeight = Layout.rowHeight - 4
    static let stripHeight: CGFloat = 16

    static func height(isLive: Bool) -> CGFloat { baseHeight + (isLive ? stripHeight : 0) }

    let event: CalendarEvent
    let day: Date
    let calendar: Calendar
    let now: Date
    let timeWidth: CGFloat

    /// The time column's width for a day's cards: just wide enough for the longest start or end
    /// among them, so the titles sit close to the times and still line up.
    static func timeWidth(for events: [CalendarEvent], day: Date, calendar: Calendar) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let widest = events.flatMap { event in
            let card = TimedCard(event: event, day: day, calendar: calendar, now: .now, timeWidth: 0)
            return [card.startText, card.endText]
        }
        .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
        .max() ?? 0
        return ceil(widest) + TimeSpan.markerWidth
    }

    var body: some View {
        Button { SystemCalendar.show(event) } label: {
            TimedCardLabel(event: event, start: startText, end: endText, subtitle: subtitle,
                           progress: progress, elapsed: elapsedText, timeWidth: timeWidth)
        }
        .buttonStyle(EventCardButtonStyle(color: event.color))
        .frame(height: Self.height(isLive: progress != nil))
        .help(Text("Open in Calendar"))
        .contextMenu {
            Button("Open in Calendar") { SystemCalendar.show(event) }
        }
    }

    /// How far through the event `now` is, while it is under way.
    private var progress: Double? {
        guard event.isUnderway(at: now) else { return nil }
        return now.timeIntervalSince(event.start) / event.end.timeIntervalSince(event.start)
    }

    /// An event carried over from the day before starts "Until" its end; one running into the
    /// next day ends with an arrow.
    fileprivate var startText: String {
        event.start < day ? String(localized: "Until") : CalendarEvent.shortTime(event.start, calendar: calendar)
    }

    fileprivate var endText: String {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return "" }
        return event.end > dayEnd ? "→" : CalendarEvent.shortTime(event.end, calendar: calendar)
    }

    private var subtitle: String {
        if progress != nil {
            let left = CalendarEvent.shortDuration(minutes: max(1, Int(event.end.timeIntervalSince(now) / 60)))
            return String(localized: "\(left) left")
        }
        return event.location ?? CalendarEvent.shortDuration(minutes: Int(event.end.timeIntervalSince(event.start) / 60))
    }

    private var elapsedText: String {
        CalendarEvent.shortDuration(minutes: max(0, Int(now.timeIntervalSince(event.start) / 60)))
    }
}

private struct TimedCardLabel: View {
    let event: CalendarEvent
    let start: String
    let end: String
    let subtitle: String
    let progress: Double?
    let elapsed: String
    let timeWidth: CGFloat
    @Environment(\.isHovered) private var hovering
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = event.color.eventAccent(for: colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TimeSpan(start: start, end: end, accent: accent, width: timeWidth)
                    .padding(.leading, 8)

                Capsule()
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title.isEmpty ? String(localized: "(No Title)") : event.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(subtitle)
                        .font(.system(size: 10, weight: progress == nil ? .medium : .semibold))
                        .foregroundStyle(progress == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent.opacity(0.85)))
                }
                .lineLimit(1)
                .padding(.leading, 8)

                Spacer(minLength: 4)

                ZStack(alignment: .trailing) {
                    if progress != nil {
                        Text("Now")
                            .font(.system(size: 8.5, weight: .heavy))
                            .textCase(.uppercase)
                            .foregroundStyle(.black.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(accent))
                            .opacity(hovering ? 0 : 1)
                    }
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(accent.opacity(0.8))
                        .opacity(hovering ? 1 : 0)
                        .offset(x: hovering ? 0 : -3, y: hovering ? 0 : 3)
                }
                .padding(.trailing, 8)
            }
            .frame(height: TimedCard.baseHeight)

            if let progress {
                ProgressStrip(progress: progress, elapsed: elapsed, accent: accent)
                    .frame(height: TimedCard.stripHeight)
            }
        }
        .opacity(event.isPast ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Start over end in one size and weight, told apart by a filled dot for the start and a hollow
/// one for the end, joined by a hairline like a stretch of the timeline.
private struct TimeSpan: View {
    /// The dots' column and the gap after it.
    static let markerWidth: CGFloat = 10

    let start: String
    let end: String
    let accent: Color
    let width: CGFloat

    var body: some View {
        HStack(spacing: Self.markerWidth - 5) {
            VStack(spacing: 0) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                Rectangle()
                    .fill(.primary.opacity(0.2))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 1.5)
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1.2)
                    .frame(width: 5, height: 5)
            }
            .frame(height: 21)

            VStack(alignment: .leading, spacing: 0) {
                Text(start)
                Text(end)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
        }
        .frame(width: width, alignment: .leading)
    }
}

/// The event under way's own strip under the card: the time gone, a thin track whose fill
/// brightens and glows more strongly toward its leading end, and the share done.
private struct ProgressStrip: View {
    let progress: Double
    let elapsed: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(elapsed)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                let width = max(2, proxy.size.width * progress)
                let fill = LinearGradient(colors: [accent.opacity(0.2), accent.opacity(0.7), accent],
                                          startPoint: .leading, endPoint: .trailing)
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.18))
                    // The glow: the same fill blurred and faded in along its length, gathering
                    // most brightly over the last stretch instead of sitting on a dot.
                    Capsule()
                        .fill(fill)
                        .frame(width: width, height: 6)
                        .blur(radius: 3)
                        .mask(LinearGradient(colors: [.clear, .black.opacity(0.5), .black],
                                             startPoint: .leading, endPoint: .trailing))
                    Capsule()
                        .fill(accent)
                        .frame(width: min(width, 18), height: 5)
                        .blur(radius: 4)
                        .offset(x: width - min(width, 18) + 3)
                    Capsule()
                        .fill(fill)
                        .frame(width: width)
                }
                .frame(height: 2)
                .frame(maxHeight: .infinity)
            }
            Text((progress).formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(accent)
                .fontWeight(.bold)
        }
        .font(.system(size: 9, weight: .semibold))
        .monospacedDigit()
        .padding(.horizontal, 9)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.12))
        .overlay(alignment: .top) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
        }
    }
}

struct AccessPrompt: View {
    let denied: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: denied ? "calendar.badge.exclamationmark" : "calendar.badge.plus")
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(denied ? "Calendar access is off" : "See your events here")
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(denied ? "Allow Minical in System Settings." : "Connect your calendars to show events.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(denied ? "Settings" : "Connect", action: action)
                .buttonStyle(CapsuleButtonStyle(prominent: true))
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.05))
        }
    }
}
