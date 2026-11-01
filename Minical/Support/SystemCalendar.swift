import AppKit

/// Hand-offs to the system Calendar app and System Settings.
enum SystemCalendar {
    private static let bundleIdentifier = "com.apple.iCal"

    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func show(_ event: CalendarEvent) {
        guard let identifier = event.eventIdentifier?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "ical://ekevent/\(identifier)?method=show&options=more"),
              NSWorkspace.shared.open(url)
        else {
            openApp()
            return
        }
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
