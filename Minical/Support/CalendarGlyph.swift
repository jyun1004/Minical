import AppKit
import CoreText

/// Minical's calendar-page glyph with today's date, shared by the menu bar and the panel's Today
/// button so both are drawn by the same code: a crisp page with modest corners, a slim binding
/// strip across the top, and the date in the system serif (New York), centered on its actual ink
/// in the space below the strip. A template image, so the menu bar and SwiftUI tint it.
enum CalendarGlyph {
    static func image(day: Int, size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)

            let line = snapped(size.width * 0.06, minimum: 1)
            let radius = size.width * 0.18
            let page = rect.insetBy(dx: line / 2, dy: line / 2)
            context.setLineWidth(line)
            context.addPath(CGPath(roundedRect: page, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()

            // The binding strip, clipped to the page's outer edge so its corners follow the outline.
            let strip = snapped(size.height * 0.22, minimum: 2)
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius + line / 2, cornerHeight: radius + line / 2, transform: nil))
            context.clip()
            context.fill(CGRect(x: rect.minX, y: rect.maxY - strip, width: rect.width, height: strip))
            context.restoreGState()

            // The date, centered on its ink (not its line box) between the strip and the bottom edge,
            // then lifted a touch: true center reads as sitting low, so the optical center is higher.
            let body = CGRect(x: rect.minX, y: rect.minY + line, width: rect.width, height: rect.height - strip - line)
            let text = numberLine(day, digitHeight: body.height * 0.6)
            let ink = CTLineGetImageBounds(text, context)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: body.midX - ink.midX, y: body.midY - ink.midY + body.height * 0.04)
            CTLineDraw(text, context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "\(day)"
        return image
    }

    /// The date set so its digits stand `digitHeight` points tall.
    private static func numberLine(_ day: Int, digitHeight: CGFloat) -> CTLine {
        let reference = serif(size: 100)
        let size = digitHeight / (reference.capHeight / 100)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: serif(size: size),
            .foregroundColor: NSColor.black,
            .kern: -size * 0.02,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: "\(day)", attributes: attributes))
    }

    private static func serif(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Snaps a stroke or edge to the half-point grid so it lands on whole pixels at 2×.
    private static func snapped(_ value: CGFloat, minimum: CGFloat) -> CGFloat {
        max(minimum, (value * 2).rounded() / 2)
    }
}
