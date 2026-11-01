import SwiftUI

/// Weekday initials aligned to day columns.
struct WeekdayHeader: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                let weekday = (index + model.calendar.firstWeekday - 1) % 7 + 1
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    // Weekends recede, as in AbleNotch's month grid.
                    .foregroundStyle(weekday == 1 || weekday == 7 ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 20)
    }
}

/// One selectable day: a tall, soft tile that wraps the number and its event dots together.
struct DayCell: View {
    let day: Date
    let isInMonth: Bool
    let selectionID: String
    let selection: Namespace.ID

    @Environment(CalendarModel.self) private var model
    @Environment(\.highlight) private var highlight
    @State private var hovering = false

    var body: some View {
        let isToday = day == model.today
        let isSelected = day == model.selectedDate
        let dots = model.showsEvents ? model.eventColors(on: day) : []

        Button { model.select(day) } label: {
            ZStack {
                background(isSelected: isSelected, isToday: isToday)

                // Number and dots share fixed positions in every cell, so rows stay perfectly aligned
                // whether or not a day has events.
                // Not `.dateTime.day()`: some locales (e.g. Korean) append a suffix like "19일".
                Text(verbatim: "\(model.calendar.component(.day, from: day))")
                    .font(.system(size: 15, weight: isToday ? .semibold : isSelected ? .medium : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberStyle(isToday: isToday))
                    .offset(y: Layout.numberOffset)

                HStack(spacing: 2.5) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                    }
                }
                .opacity(isInMonth ? 1 : 0.45)
                .offset(y: Layout.dotsOffset)
            }
            .frame(width: Layout.tileSize.width, height: Layout.tileSize.height)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.cellHeight)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.9))
        .accessibilityLabel(Text(day, format: .dateTime.year().month(.wide).day().weekday(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func background(isSelected: Bool, isToday: Bool) -> some View {
        let tile = RoundedRectangle(cornerRadius: Layout.tileCornerRadius, style: .continuous)

        // Today keeps a faint wash of the highlight even when another day is selected.
        tile
            .fill(highlight.opacity(isToday && !isSelected ? 0.045 : 0))

        // Always in the tree so hover can grow and fade in rather than pop.
        tile
            .fill(LinearGradient(colors: [Color.primary.opacity(0.15), Color.primary.opacity(0.08)],
                                 startPoint: .top, endPoint: .bottom))
            .scaleEffect(hovering && !isSelected ? 1 : 0.82)
            .opacity(hovering && !isSelected ? 1 : 0)
            .animation(Motion.hoverSpring, value: hovering)

        if isSelected {
            tile
                .fill(highlight.opacity(hovering ? 0.26 : 0.2))
                .matchedGeometryEffect(id: selectionID, in: selection)
                .animation(Motion.hover, value: hovering)
        }
    }

    private func numberStyle(isToday: Bool) -> AnyShapeStyle {
        if isToday { return AnyShapeStyle(highlight) }
        if model.isHoliday(day) { return AnyShapeStyle(Color.red.opacity(isInMonth ? 1 : 0.45)) }
        guard isInMonth else { return AnyShapeStyle(.tertiary) }
        return model.calendar.isDateInWeekend(day) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }
}
