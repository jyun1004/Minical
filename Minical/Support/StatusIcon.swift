import AppKit

/// The menu bar glyph: Minical's calendar page with today's date, the same drawing as the panel's
/// Today button. A template image, so macOS tints it for light, dark and tinted menu bars.
enum StatusIcon {
    static func image(day: Int) -> NSImage {
        CalendarGlyph.image(day: day, size: NSSize(width: 17, height: 16))
    }
}
