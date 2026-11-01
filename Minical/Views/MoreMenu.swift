import SwiftUI

struct MoreMenu: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        Menu {
            Button("Go to Today") { model.goToToday() }
            Button("Open Calendar") { SystemCalendar.openApp() }

            Divider()

            Toggle("Show Events", isOn: Binding(
                get: { model.showsEvents },
                set: { value in withAnimation(Motion.fade) { model.setShowsEvents(value) } }
            ))

            if model.showsEvents, !model.calendarGroups.isEmpty {
                Menu("Calendars") {
                    ForEach(model.calendarGroups) { group in
                        Section(group.title) {
                            ForEach(group.calendars) { item in
                                Toggle(isOn: Binding(
                                    get: { model.isCalendarVisible(item.id) },
                                    set: { model.setCalendar(item.id, visible: $0) }
                                )) {
                                    Label {
                                        Text(item.title)
                                    } icon: {
                                        Image(nsImage: item.swatch)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Button("Appearance…") { model.showAppearance() }

            Picker("Week Starts On", selection: Binding(
                get: { model.weekStart },
                set: { model.setWeekStart($0) }
            )) {
                Text("System Default").tag(WeekStart.system)
                Text(verbatim: model.weekdayName(1)).tag(WeekStart.sunday)
                Text(verbatim: model.weekdayName(2)).tag(WeekStart.monday)
            }

            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Divider()

            Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                .disabled(!AppUpdater.shared.canCheckForUpdates)

            Button("Quit Minical") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .regular))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("More"))
    }
}
