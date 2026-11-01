import AppKit
import Foundation
import SwiftUI
import OSLog
import ServiceManagement

enum WeekStart: Int, CaseIterable, Identifiable {
    case system = 0
    case sunday = 1
    case monday = 2

    var id: Int { rawValue }

    /// The `Calendar.firstWeekday` value to force, or `nil` to follow the locale.
    var firstWeekday: Int? {
        switch self {
        case .system: nil
        case .sunday: 1
        case .monday: 2
        }
    }
}

/// The single color used for today, the selection and primary buttons.
enum HighlightColor: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .system: .controlAccentColor
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .graphite: .systemGray
        }
    }

    var color: Color { self == .system ? .accentColor : Color(nsColor: nsColor) }

    var name: LocalizedStringResource {
        switch self {
        case .system: "System Accent"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .graphite: "Graphite"
        }
    }

    /// A non-template dot for menus, which would otherwise flatten SF Symbols to monochrome.
    var swatch: NSImage {
        let color = nsColor
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// How the panel itself is drawn, after AbleNotch's themes.
enum PanelTheme: String, CaseIterable, Identifiable {
    /// The system popover material, light or dark with the system.
    case system
    /// Plain black.
    case black
    /// Smoked glass: darkest along the top, clearing downward, with a glass edge.
    case fadedGlass
    /// Black at the top, clearing to bright glass toward the bottom (dusk): the strongest fade.
    case duskGlass
    /// Liquid Glass all the way.
    case liquidGlass
    /// A frosted, translucent pane under a veil of a chosen colour.
    case pane

    var id: String { rawValue }

    var name: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .black: "Black"
        case .fadedGlass: "Faded Glass"
        case .duskGlass: "Dusk Glass"
        case .liquidGlass: "Liquid Glass"
        case .pane: "Pane"
        }
    }

    var isGlass: Bool { self == .fadedGlass || self == .duskGlass || self == .liquidGlass }

    /// Every theme but System is dark, so it draws its content in the dark appearance.
    var forcesDarkAppearance: Bool { self != .system }

    /// Dusk Glass draws the clear glass (it bends what's behind the most) and lets it fade out
    /// toward the bottom; the others the regular glass.
    var usesClearGlass: Bool { self == .duskGlass }

    /// The black the glass is tinted with (AbleNotch's notch: Dusk's clear glass untinted).
    var glassTint: Double { self == .duskGlass ? 0 : 0.2 }

    /// How tall the top band is that stands in for AbleNotch's notch: where Faded's smoke eases
    /// and Dusk's black ends.
    static let smokeBand: CGFloat = 32

    /// The smoke over the glass, top to bottom, on a card `height` tall: black at an opacity, at a
    /// location. Dusk: black through the top band, then one even curve to nothing at the bottom,
    /// slow at first and quicker toward the end (1 − t²).
    func smoke(height: CGFloat) -> [(black: Double, location: Double)] {
        let h = max(height, 1)
        switch self {
        case .fadedGlass:
            return [(0.72, 0), (0.42, Double(min(0.85, (Self.smokeBand + 4) / h))), (0.16, 1)]
        case .duskGlass:
            let blackEnd = Double(min(1, Self.smokeBand / h))
            return [(1, 0)] + (0...24).map { i in
                let t = Double(i) / 24
                return (1 - t * t, blackEnd + (1 - blackEnd) * t)
            }
        default:
            return []
        }
    }

    /// How much of Dusk's glass shows at each of `smoke`'s stops: fading with the smoke down to
    /// this, so the bottom is mostly the desktop itself, sharp, as through a window. (Glass, even
    /// the clear kind, blurs and lifts what's behind it: in full there it read as frost.)
    static let duskGlassFloor = 0.35

    /// The glass edge, top to bottom: white at an opacity, at a location (none for Black/System).
    var rim: [(white: Double, location: Double)] {
        switch self {
        case .liquidGlass: [(0.6, 0), (0.24, 0.72), (0.42, 1)]
        case .fadedGlass: [(0.42, 0), (0.16, 0.72), (0.3, 1)]
        case .duskGlass: [(0.14, 0), (0.5, 1)]
        case .pane: [(0.17, 0), (0.17, 1)]
        case .system, .black: []
        }
    }
}

/// The Pane theme's colours: the sheet is the frost under a veil of this colour.
enum PaneColor {
    static let graphite = "000000"
    static let presets: [(name: LocalizedStringResource, hex: String)] = [
        ("Graphite", graphite), ("Slate", "2B3A4F"), ("Midnight", "16204A"), ("Ocean", "0B4252"),
        ("Forest", "143A26"), ("Plum", "3E1A4A"), ("Wine", "4F1428"), ("Ember", "5A2A0C"),
    ]

    static func nsColor(_ hex: String) -> NSColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func color(_ hex: String) -> Color { Color(nsColor: nsColor(hex)) }

    /// The veil's opacity at the edges and the middle. At the default strength (0.5) black keeps a
    /// light smoke and a colour is laid denser so it reads; the strength scales from nearly clear
    /// frost (0) to nearly solid colour (1).
    static func veil(_ hex: String, strength: Double) -> (edge: Double, middle: Double) {
        let base: (edge: Double, middle: Double) = hex == graphite ? (0.36, 0.52) : (0.5, 0.64)
        let s = min(max(strength, 0), 1)
        func scale(_ v: Double) -> Double { s <= 0.5 ? v * (0.12 + 0.88 * s / 0.5) : v + (0.94 - v) * (s - 0.5) / 0.5 }
        return (scale(base.edge), scale(base.middle))
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case month, week, day

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .month: "Month"
        case .week: "Week"
        case .day: "Day"
        }
    }
}

enum CalendarAccess {
    case notDetermined
    case denied
    case granted
}

enum DefaultsKey {
    static let weekStart = "weekStart"
    static let showsEvents = "showsEvents"
    static let hiddenCalendarIDs = "hiddenCalendarIDs"
    static let highlightColor = "highlightColor"
    static let viewMode = "viewMode"
    static let panelTheme = "panelTheme"
    static let paneColor = "paneColor"
    static let paneStrength = "paneStrength"
}

enum LoginItem {
    private static let logger = Logger(subsystem: "com.jyun1004.Minical", category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to update login item: \(error.localizedDescription)")
        }
    }
}

/// The locale the interface is drawn in: the app's own language (English for now; Korean once its
/// translation is complete) with the user's region, clock and number settings.
nonisolated enum AppLocale {
    static var current: Locale {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents = Locale.Language.Components(identifier: language)
        return Locale(components: components)
    }
}
