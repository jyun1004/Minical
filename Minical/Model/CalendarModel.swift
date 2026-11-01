import AppKit
import EventKit
import Observation
import SwiftUI

enum Motion {
    static let page = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let select = Animation.spring(response: 0.3, dampingFraction: 0.78)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.6)
    static let hover = Animation.easeOut(duration: 0.14)
    static let hoverSpring = Animation.spring(response: 0.26, dampingFraction: 0.72)
    static let fade = Animation.easeInOut(duration: 0.2)
    static let panel = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

@Observable
final class CalendarModel {
    private(set) var calendar: Calendar
    private(set) var today: Date
    /// Always the first day of the month shown in the grid.
    private(set) var displayedMonth: Date
    private(set) var selectedDate: Date
    /// +1 when paging forward in time, -1 when paging back. Drives the grid transition.
    private(set) var pageDirection = 1

    private(set) var access: CalendarAccess
    private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]
    private(set) var calendarGroups: [CalendarGroup] = []

    /// The new-event composer is open in place of the agenda.
    private(set) var isComposing = false
    private(set) var mode: ViewMode

    private(set) var weekStart: WeekStart
    private(set) var showsEvents: Bool
    private(set) var hiddenCalendarIDs: Set<String>
    private(set) var launchAtLogin = LoginItem.isEnabled
    private(set) var highlight: HighlightColor
    private(set) var theme: PanelTheme
    private(set) var paneColor: String
    private(set) var paneStrength: Double
    /// The Appearance sheet is open over the calendar.
    private(set) var isShowingAppearance = false

    @ObservationIgnored private let service = EventService()
    @ObservationIgnored private var store: EKEventStore { service.store }
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Ranges already fetched or in flight for the current generation.
    @ObservationIgnored private var requestedRanges: Set<DateInterval> = []
    /// Bumped on every full reload so late results from an older fetch are dropped.
    @ObservationIgnored private var generation = 0
    #if DEBUG
    @ObservationIgnored private var usesSampleData = false
    #endif

    init() {
        defaults.register(defaults: [DefaultsKey.showsEvents: true])
        let weekStart = WeekStart(rawValue: defaults.integer(forKey: DefaultsKey.weekStart)) ?? .system
        self.weekStart = weekStart
        showsEvents = defaults.bool(forKey: DefaultsKey.showsEvents)
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: DefaultsKey.hiddenCalendarIDs) ?? [])
        mode = defaults.string(forKey: DefaultsKey.viewMode).flatMap(ViewMode.init) ?? .month
        highlight = defaults.string(forKey: DefaultsKey.highlightColor).flatMap(HighlightColor.init) ?? .system
        theme = defaults.string(forKey: DefaultsKey.panelTheme).flatMap(PanelTheme.init) ?? .system
        paneColor = defaults.string(forKey: DefaultsKey.paneColor) ?? PaneColor.graphite
        paneStrength = defaults.object(forKey: DefaultsKey.paneStrength) as? Double ?? 0.5

        let calendar = Self.makeCalendar(weekStart)
        let today = calendar.startOfDay(for: .now)
        self.calendar = calendar
        self.today = today
        displayedMonth = Self.monthStart(of: today, in: calendar)
        selectedDate = today
        access = Self.currentAccess()

        observeSystem()
        reloadCalendars()
        reloadEvents()
    }

    // MARK: - Derived

    var selectedEvents: [CalendarEvent] { eventsByDay[selectedDate] ?? [] }

    var isShowingCurrentMonth: Bool { displayedMonth == Self.monthStart(of: today, in: calendar) }

    var monthTitle: String { Self.string(displayedMonth, template: "yMMMM", calendar: calendar) }

    var selectedDateTitle: String { Self.string(selectedDate, template: "MMMMdEEEE", calendar: calendar) }

    var selectedRelativeTitle: String? {
        switch calendar.dateComponents([.day], from: today, to: selectedDate).day {
        case 0: String(localized: "Today")
        case 1: String(localized: "Tomorrow")
        case -1: String(localized: "Yesterday")
        default: nil
        }
    }

    /// Weekday initials in display order, starting from the configured first weekday.
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    func weekdayName(_ weekday: Int) -> String {
        calendar.standaloneWeekdaySymbols[weekday - 1]
    }

    /// Six full weeks, so the popover never changes height between months.
    func gridDays(for month: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: month) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func isInDisplayedMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    func isHoliday(_ day: Date) -> Bool {
        eventsByDay[day]?.contains { $0.isHoliday && $0.isAllDay } ?? false
    }

    /// Up to three distinct calendar colors for the dots under a day.
    func eventColors(on day: Date) -> [Color] {
        var colors: [Color] = []
        for event in eventsByDay[day] ?? [] where !event.isHoliday && !colors.contains(event.color) {
            colors.append(event.color)
            if colors.count == 3 { break }
        }
        return colors
    }

    // MARK: - Navigation

    func setMode(_ value: ViewMode) {
        guard value != mode else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // Keep the month grid in step with the selection made in week or day view.
            displayedMonth = Self.monthStart(of: selectedDate, in: calendar)
        }
        withAnimation(Motion.panel) { mode = value }
        defaults.set(value.rawValue, forKey: DefaultsKey.viewMode)
        loadMonth(displayedMonth)
    }

    /// Steps one unit of the current view: a month, a week or a day.
    /// Counts of steps taken in each direction; the header arrows animate off these.
    private(set) var forwardSteps = 0
    private(set) var backwardSteps = 0

    func navigate(_ offset: Int) {
        if offset > 0 { forwardSteps += 1 } else { backwardSteps += 1 }
        switch mode {
        case .month: showMonth(offset: offset)
        case .week: moveSelection(byDays: 7 * offset)
        case .day: moveSelection(byDays: offset)
        }
    }

    func showMonth(offset: Int) {
        guard let target = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        page(direction: target > displayedMonth ? 1 : -1) { [self] in
            displayedMonth = target
        }
        loadMonth(target)
    }

    func goToToday() {
        select(today)
    }

    func select(_ day: Date) {
        let day = calendar.startOfDay(for: day)
        guard day != selectedDate || !isShowingSelectionPage(day) else { return }
        let month = Self.monthStart(of: day, in: calendar)

        if mode == .month, month == displayedMonth {
            withAnimation(Motion.select) { selectedDate = day }
        } else {
            // Week and day views slide their timeline to the newly selected day.
            let forward = mode == .month ? month > displayedMonth : day > selectedDate
            page(direction: forward ? 1 : -1) { [self] in
                selectedDate = day
                displayedMonth = month
            }
        }
        loadMonth(month)
        loadDay(day)
    }

    func moveSelection(byDays days: Int) {
        guard let day = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        select(day)
    }

    /// Called whenever the popover opens: always start from today.
    func prepareForPresentation() {
        #if DEBUG
        if usesSampleData { return }
        #endif
        refreshToday()
        launchAtLogin = LoginItem.isEnabled
        let month = Self.monthStart(of: today, in: calendar)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isComposing = false
            isShowingAppearance = false
            selectedDate = today
            if displayedMonth != month {
                displayedMonth = month
            }
        }
        // Access may have been granted or revoked in System Settings since the last open.
        if Self.currentAccess() != access {
            accessChanged()
            return
        }
        // Change notifications can be missed (or arrive before a synced account catches up), and a
        // loaded range is otherwise never fetched again, so every open re-reads what it shows. The
        // events already on screen stay until the fresh ones replace them.
        store.refreshSourcesIfNecessary()
        reloadEvents()
    }

    /// What identifies the current "page" of a view, so its content can slide as a unit.
    var pageKey: Date {
        mode == .month ? displayedMonth : pageKey(for: selectedDate)
    }

    private func pageKey(for day: Date) -> Date {
        switch mode {
        case .month: Self.monthStart(of: day, in: calendar)
        case .week: weekStart(of: day)
        case .day: day
        }
    }

    private func isShowingSelectionPage(_ day: Date) -> Bool {
        mode == .month ? isInDisplayedMonth(day) : true
    }

    private func page(direction: Int, _ change: @escaping @MainActor @Sendable () -> Void) {
        let commit: @MainActor @Sendable () -> Void = {
            withAnimation(Motion.page, change)
        }
        if direction == pageDirection {
            commit()
        } else {
            // The outgoing page reads its removal transition from the last render, so flip the
            // direction first and page on the next run loop turn once that render has happened.
            pageDirection = direction
            DispatchQueue.main.async(execute: commit)
        }
    }

    // MARK: - Weeks

    func weekStart(of day: Date) -> Date {
        let weekday = calendar.component(.weekday, from: day)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leading, to: calendar.startOfDay(for: day)) ?? day
    }

    func weekDays(containing day: Date) -> [Date] {
        let start = weekStart(of: day)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var title: String {
        switch mode {
        case .month:
            return monthTitle
        case .week:
            let start = weekStart(of: selectedDate)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let formatter = DateIntervalFormatter()
            formatter.calendar = calendar
            formatter.locale = calendar.locale
            formatter.dateTemplate = "MMMd"
            return formatter.string(from: start, to: end)
        case .day:
            return Self.string(selectedDate, template: "MMMdEEE", calendar: calendar)
        }
    }

    /// Today is the selected day and on screen, in any mode.
    var isShowingToday: Bool {
        guard selectedDate == today else { return false }
        return mode != .month || isShowingCurrentMonth
    }

    // MARK: - Creating events

    var writableCalendarGroups: [CalendarGroup] {
        calendarGroups.compactMap { group in
            let calendars = group.calendars.filter(\.allowsNewEvents)
            return calendars.isEmpty ? nil : CalendarGroup(id: group.id, title: group.title, calendars: calendars)
        }
    }

    var canCreateEvents: Bool { access == .granted && !writableCalendarGroups.isEmpty }

    /// A start time the composer should use instead of its default, e.g. a double-clicked slot.
    @ObservationIgnored private var composerStart: Date?

    func beginComposing(at start: Date? = nil) {
        guard canCreateEvents else { return }
        composerStart = start
        if let start { select(start) }
        withAnimation(Motion.panel) {
            isShowingAppearance = false
            isComposing = true
        }
    }

    func endComposing() {
        withAnimation(Motion.panel) { isComposing = false }
    }

    /// A sensible starting point: the next whole hour today, 9 AM on other days, one hour long.
    func newDraft() -> EventDraft {
        let start: Date
        if let composerStart {
            start = composerStart
        } else if selectedDate == today {
            let nextHour = calendar.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)
            start = nextHour ?? .now
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        }
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        let writable = writableCalendarGroups.flatMap(\.calendars).map(\.id)
        let preferred = store.defaultCalendarForNewEvents?.calendarIdentifier
        let calendarID = preferred.flatMap { writable.contains($0) ? $0 : nil } ?? writable.first
        return EventDraft(start: start, end: end, calendarID: calendarID)
    }

    func save(_ draft: EventDraft) throws {
        guard let calendarID = draft.calendarID, let target = store.calendar(withIdentifier: calendarID) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.isAllDay = draft.isAllDay
        if draft.isAllDay {
            let day = calendar.startOfDay(for: draft.start)
            event.startDate = day
            event.endDate = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        } else {
            event.startDate = draft.start
            event.endDate = max(draft.end, draft.start)
        }
        try store.save(event, span: .thisEvent, commit: true)

        // If hidden, the new event would silently vanish; surface its calendar again.
        if hiddenCalendarIDs.contains(calendarID) {
            setCalendar(calendarID, visible: true)
        } else {
            reloadEvents()
        }
        endComposing()
        select(event.startDate)
    }

    // MARK: - Settings

    func setWeekStart(_ value: WeekStart) {
        guard value != weekStart else { return }
        weekStart = value
        defaults.set(value.rawValue, forKey: DefaultsKey.weekStart)
        rebuildCalendar()
    }

    func setShowsEvents(_ value: Bool) {
        showsEvents = value
        defaults.set(value, forKey: DefaultsKey.showsEvents)
        if !value { isComposing = false }
        reloadEvents()
    }

    func isCalendarVisible(_ id: String) -> Bool { !hiddenCalendarIDs.contains(id) }

    func setCalendar(_ id: String, visible: Bool) {
        if visible { hiddenCalendarIDs.remove(id) } else { hiddenCalendarIDs.insert(id) }
        defaults.set(Array(hiddenCalendarIDs), forKey: DefaultsKey.hiddenCalendarIDs)
        reloadEvents()
    }

    func setTheme(_ value: PanelTheme) {
        withAnimation(Motion.fade) { theme = value }
        defaults.set(value.rawValue, forKey: DefaultsKey.panelTheme)
    }

    func setPaneColor(_ hex: String) {
        withAnimation(Motion.fade) { paneColor = hex }
        defaults.set(hex, forKey: DefaultsKey.paneColor)
    }

    func setPaneStrength(_ value: Double) {
        paneStrength = min(max(value, 0), 1)
        defaults.set(paneStrength, forKey: DefaultsKey.paneStrength)
    }

    func showAppearance() {
        isComposing = false
        withAnimation(Motion.panel) { isShowingAppearance = true }
    }

    func hideAppearance() {
        withAnimation(Motion.panel) { isShowingAppearance = false }
    }

    func setHighlight(_ value: HighlightColor) {
        withAnimation(Motion.fade) { highlight = value }
        defaults.set(value.rawValue, forKey: DefaultsKey.highlightColor)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: - Calendar access

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in self?.accessChanged() }
        }
    }

    private func accessChanged() {
        access = Self.currentAccess()
        reloadCalendars()
        reloadEvents()
    }

    private static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        default: .denied
        }
    }

    // MARK: - Loading

    private func reloadCalendars() {
        guard access == .granted else {
            calendarGroups = []
            return
        }
        let grouped = Dictionary(grouping: store.calendars(for: .event)) { $0.source?.sourceIdentifier ?? "" }
        calendarGroups = grouped.map { id, calendars in
            CalendarGroup(
                id: id,
                title: calendars.first?.source?.title ?? "",
                calendars: calendars
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    .map(CalendarItem.init)
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Invalidates everything and re-fetches what is on screen. Existing results stay visible
    /// until fresh ones replace them, so nothing flickers.
    private func reloadEvents() {
        generation += 1
        requestedRanges = []
        guard showsEvents, access == .granted else {
            eventsByDay = [:]
            return
        }
        loadMonth(displayedMonth)
        loadDay(selectedDate)
    }

    /// Loads a month's grid, then quietly prefetches its neighbours so paging is instant.
    private func loadMonth(_ month: Date) {
        loadGrid(of: month)
        for offset in [-1, 1] {
            if let neighbour = calendar.date(byAdding: .month, value: offset, to: month) {
                loadGrid(of: neighbour)
            }
        }
    }

    private func loadGrid(of month: Date) {
        let days = gridDays(for: month)
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        load(from: first, to: end)
    }

    private func loadDay(_ day: Date) {
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return }
        load(from: day, to: end)
    }

    private func load(from start: Date, to end: Date) {
        #if DEBUG
        if usesSampleData { return }
        #endif
        let range = DateInterval(start: start, end: end)
        guard showsEvents, access == .granted, !requestedRanges.contains(range) else { return }
        requestedRanges.insert(range)

        let generation = generation
        let calendar = calendar
        let hidden = hiddenCalendarIDs
        Task {
            let fetched = await service.events(from: start, to: end, hiddenCalendarIDs: hidden, calendar: calendar)
            guard generation == self.generation else { return }
            withAnimation(Motion.fade) {
                var day = start
                while day < end {
                    eventsByDay[day] = fetched[day]
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
        }
    }

    // MARK: - System changes

    private func observeSystem() {
        observe(.EKEventStoreChanged, object: store) { model in
            model.reloadCalendars()
            model.reloadEvents()
        }
        observe(.NSCalendarDayChanged) { $0.refreshToday() }
        observe(.NSSystemClockDidChange) { $0.refreshToday() }
        observe(.NSSystemTimeZoneDidChange) { $0.rebuildCalendar() }
        observe(NSLocale.currentLocaleDidChangeNotification) { $0.rebuildCalendar() }
        observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { $0.refreshToday() }
    }

    private func observe(
        _ name: Notification.Name,
        object: Any? = nil,
        in center: NotificationCenter = .default,
        handler: @escaping @MainActor (CalendarModel) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append(token)
    }

    private func refreshToday() {
        let newToday = calendar.startOfDay(for: .now)
        guard newToday != today else { return }
        let wasShowingToday = isShowingCurrentMonth
        let wasSelectingToday = selectedDate == today
        today = newToday
        if wasSelectingToday { selectedDate = newToday }
        if wasShowingToday { displayedMonth = Self.monthStart(of: newToday, in: calendar) }
        reloadEvents()
    }

    private func rebuildCalendar() {
        calendar = Self.makeCalendar(weekStart)
        today = calendar.startOfDay(for: .now)
        displayedMonth = Self.monthStart(of: displayedMonth, in: calendar)
        selectedDate = calendar.startOfDay(for: selectedDate)
        reloadEvents()
    }

    // MARK: - Debug

    #if DEBUG
    /// Fills the model with in-memory events so the UI can be inspected without calendar access.
    func loadSampleData(selecting dayOffset: Int = 0) {
        usesSampleData = true
        access = .granted

        func makeCalendar(_ title: String, _ color: NSColor) -> EKCalendar {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.cgColor = color.cgColor
            return calendar
        }
        let work = makeCalendar("Work", .systemBlue)
        let home = makeCalendar("Home", .systemOrange)
        let fitness = makeCalendar("Fitness", .systemGreen)
        calendarGroups = [CalendarGroup(id: "sample", title: "iCloud", calendars: [work, home, fitness].map(CalendarItem.init))]

        var buckets: [Date: [CalendarEvent]] = [:]
        func add(_ title: String, _ calendar: EKCalendar, day: Int, hour: Int? = nil, minutes: Int = 60, location: String? = nil, notes: String? = nil) {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.calendar = calendar
            event.location = location
            event.notes = notes
            let date = self.calendar.date(byAdding: .day, value: day, to: today)!
            if let hour {
                event.startDate = self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
                event.endDate = event.startDate.addingTimeInterval(TimeInterval(minutes * 60))
            } else {
                event.isAllDay = true
                event.startDate = date
                event.endDate = date.addingTimeInterval(86_399)
            }
            buckets[date, default: []].append(CalendarEvent(event))
        }
        add("Product launch", work, day: 0)
        add("Design review", work, day: 0, hour: 10, location: "Room 3A",
            notes: "Walk through the new onboarding flow and agree on the empty states.")
        add("Lunch with Mina", home, day: 0, hour: 12, minutes: 90)
        add("Standup", work, day: 0, hour: 10, minutes: 30)
        add("Coffee", home, day: 1, hour: 8)
        add("Yoga", fitness, day: 0, hour: 19)
        add("1:1", work, day: 1, hour: 11, minutes: 30)
        add("Dentist", home, day: 3, hour: 15)
        add("Run", fitness, day: 3, hour: 7)
        add("Sprint planning", work, day: -5, hour: 9)
        add("Dinner", home, day: -3, hour: 19)
        add("Climbing", fitness, day: 6, hour: 18)
        add("Offsite", work, day: 9)
        add("Groceries", home, day: 9, hour: 10)
        add("Run", fitness, day: 9, hour: 7)
        eventsByDay = buckets.mapValues { $0.sorted(by: CalendarEvent.displayOrder) }
        selectedDate = calendar.date(byAdding: .day, value: dayOffset, to: today)!
    }

    func showComposerForPreview() {
        isComposing = true
    }

    func showAppearanceForPreview(theme: PanelTheme?, sheet: Bool) {
        if let theme { self.theme = theme }
        isShowingAppearance = sheet
    }
    #endif

    // MARK: - Helpers

    private static func makeCalendar(_ weekStart: WeekStart) -> Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = AppLocale.current
        if let firstWeekday = weekStart.firstWeekday {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }

    private static func monthStart(of date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func string(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
