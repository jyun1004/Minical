import SwiftUI

/// Month mode: the six-week grid with the selected day's agenda underneath.
struct MonthPage: View {
    let onSwipeArea: (CGRect) -> Void
    @Environment(CalendarModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            MonthView()
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, 6)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onSwipeArea($0) }

            if model.showsEvents {
                Divider()
                    .padding(.horizontal, Layout.gutter)
                AgendaView()
            }
        }
    }
}

struct MonthView: View {
    @Environment(CalendarModel.self) private var model
    @Namespace private var selection

    var body: some View {
        VStack(spacing: 2) {
            WeekdayHeader()

            ZStack {
                MonthGrid(month: model.displayedMonth, selection: selection)
                    .id(model.displayedMonth)
                    .transition(.page(direction: model.pageDirection))
            }
            .clipped()
        }
    }
}

private struct MonthGrid: View {
    let month: Date
    let selection: Namespace.ID
    @Environment(CalendarModel.self) private var model

    var body: some View {
        let calendar = model.calendar
        let days = model.gridDays(for: month)
        let monthNumber = calendar.component(.month, from: month)
        // Scoped per month so the outgoing and incoming grids never share a geometry source.
        let selectionID = "month-\(month.timeIntervalSinceReferenceDate)"

        VStack(spacing: 0) {
            ForEach(0..<days.count / 7, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(days[week * 7 ..< week * 7 + 7], id: \.self) { day in
                        DayCell(
                            day: day,
                            isInMonth: calendar.component(.month, from: day) == monthNumber,
                            selectionID: selectionID,
                            selection: selection
                        )
                    }
                }
            }
        }
    }
}
