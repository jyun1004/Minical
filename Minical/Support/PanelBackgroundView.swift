import AppKit

/// The panel's card, drawn per theme (after AbleNotch's): a base of the system popover material,
/// real Liquid Glass or a frosted pane; a tint over it (the glass themes' smoke, the pane's colour
/// veil, or solid black); the content; and on top a fine edge of light for the glass and pane
/// themes. Everything is clipped to the card's rounded shape. The glass takes AbleNotch's lens
/// (`GlassLens`), and Dusk's clear glass fades out toward the bottom.
final class PanelBackgroundView: NSView {
    private let material = NSVisualEffectView()
    private var glass: NSView?
    /// Holds the glass, so Dusk can fade it out with a mask.
    private let glassHolder = NSView()
    private let glassMask = CAGradientLayer()
    private let tint = GradientView()
    private let rim = RimView()
    private let cornerRadius: CGFloat
    private var theme: PanelTheme?

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        material.blendingMode = .behindWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        addSubview(material)

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.autoresizingMask = [.width, .height]
            glassHolder.wantsLayer = true
            glassHolder.autoresizingMask = [.width, .height]
            glassHolder.addSubview(glass)
            addSubview(glassHolder)
            self.glass = glass
        }

        tint.autoresizingMask = [.width, .height]
        addSubview(tint)

        rim.cornerRadius = cornerRadius
        rim.autoresizingMask = [.width, .height]
        addSubview(rim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Puts the content between the tint and the rim.
    func setContent(_ view: NSView) {
        addSubview(view, positioned: .below, relativeTo: rim)
    }

    override func layout() {
        super.layout()
        for view in [material, glassHolder, tint, rim] + [glass].compactMap({ $0 }) {
            view.frame = bounds
        }
        // The smoke and Dusk's glass are laid out by the card's height: followed as it resizes.
        if let theme, theme.isGlass, bounds.height != laidOutHeight {
            laidOutHeight = bounds.height
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutSmoke(theme)
            CATransaction.commit()
        }
        tuneLens()
    }

    private var laidOutHeight: CGFloat = 0
    private var lensSide: CGFloat = 0

    /// Sets the lens on the glass for its size, after the glass has laid itself out.
    private func tuneLens() {
        guard let theme, theme.isGlass, let glass else { return }
        let side = min(bounds.width, bounds.height).rounded()
        guard side != lensSide else { return }
        lensSide = side
        let values = GlassLens.values(side: side, clear: theme.usesClearGlass)
        DispatchQueue.main.async { [weak glass] in
            GlassLens.apply(glass?.layer, values)
        }
    }

    /// The glass themes' smoke and Dusk's glass mask, for the card's current height.
    private func layoutSmoke(_ theme: PanelTheme) {
        let smoke = theme.smoke(height: bounds.height)
        guard glass != nil else {
            // Without Liquid Glass (before macOS 26) the frost is darkened toward glass's depth.
            let base = 0.35
            let stops = smoke.isEmpty ? [(black: 0.0, location: 0.0), (black: 0.0, location: 1.0)] : smoke
            tint.set(stops: stops.map { (NSColor.black.withAlphaComponent(base + $0.black * (1 - base)), $0.location) }, horizontal: false)
            return
        }
        if !smoke.isEmpty {
            tint.set(stops: smoke.map { (NSColor.black.withAlphaComponent($0.black), $0.location) }, horizontal: false)
        }
        if theme == .duskGlass {
            let floor = PanelTheme.duskGlassFloor
            glassMask.frame = glassHolder.bounds
            glassMask.colors = smoke.map { NSColor.black.withAlphaComponent(floor + (1 - floor) * $0.black).cgColor }
            glassMask.locations = smoke.map { NSNumber(value: $0.location) }
            // The holder isn't flipped: the gradient runs from its top (y = 1) down.
            glassMask.startPoint = CGPoint(x: 0.5, y: 1)
            glassMask.endPoint = CGPoint(x: 0.5, y: 0)
            glassHolder.layer?.mask = glassMask
        } else {
            glassHolder.layer?.mask = nil
        }
    }

    /// Draws `theme`; a change of theme cross-fades, a change of pane colour or strength follows
    /// at once (the strength slider drives it continuously).
    func apply(_ theme: PanelTheme, paneColor: String, paneStrength: Double) {
        let animated = self.theme != nil && self.theme != theme
        self.theme = theme

        let hasGlass = glass != nil
        let usesGlass = theme.isGlass && hasGlass
        let usesMaterial = theme == .system || theme == .pane || (theme.isGlass && !hasGlass)

        material.material = theme == .system ? .popover : .hudWindow

        // Plain tints; the glass themes' smoke follows the card's height (`layoutSmoke`).
        var stops: [(NSColor, Double)] = []
        var horizontal = false
        switch theme {
        case .system, .fadedGlass, .duskGlass, .liquidGlass:
            break
        case .black:
            stops = [(.black, 0), (.black, 1)]
        case .pane:
            let veil = PaneColor.veil(paneColor, strength: paneStrength)
            let color = PaneColor.nsColor(paneColor)
            stops = [(color.withAlphaComponent(veil.edge), 0), (color.withAlphaComponent(veil.middle), 0.5),
                     (color.withAlphaComponent(veil.edge), 1)]
            horizontal = true
        }

        let showsTint = !stops.isEmpty || (theme.isGlass && (!hasGlass || !theme.smoke(height: 1).isEmpty))

        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            glass.style = theme.usesClearGlass ? .clear : .regular
            glass.tintColor = theme.glassTint > 0 ? NSColor.black.withAlphaComponent(theme.glassTint) : nil
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.3 : 0
            context.allowsImplicitAnimation = animated
            material.animator().alphaValue = usesMaterial ? 1 : 0
            glassHolder.animator().alphaValue = usesGlass ? 1 : 0
            rim.animator().alphaValue = theme.rim.isEmpty ? 0 : 1
            tint.animator().alphaValue = showsTint ? 1 : 0
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.3 : 0)
        CATransaction.setDisableActions(!animated)
        if !stops.isEmpty { tint.set(stops: stops, horizontal: horizontal) }
        if theme.isGlass {
            laidOutHeight = bounds.height
            layoutSmoke(theme)
        } else {
            glassHolder.layer?.mask = nil
        }
        rim.set(stops: theme.rim, width: theme == .pane ? 0.75 : 0.9)
        // The plain themes keep a hairline so the card's edge reads against any desktop.
        layer?.borderWidth = theme.rim.isEmpty ? 0.5 : 0
        layer?.borderColor = NSColor.white.withAlphaComponent(theme == .black ? 0.1 : 0.12).cgColor
        CATransaction.commit()
        lensSide = 0
        tuneLens()
    }
}

/// A full-size linear gradient, top to bottom or left to right.
private final class GradientView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    func set(stops: [(NSColor, Double)], horizontal: Bool) {
        gradient.colors = stops.map(\.0.cgColor)
        gradient.locations = stops.map { NSNumber(value: $0.1) }
        // Flipped: y = 0 is the top edge.
        gradient.startPoint = horizontal ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0.5, y: 0)
        gradient.endPoint = horizontal ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0.5, y: 1)
    }
}

/// The glass edge, after AbleNotch's: a dark line just inside the card's outline (it shows on light
/// backgrounds) under a fine line of light, lit by a top-to-bottom gradient (on dark ones).
private final class RimView: NSView {
    var cornerRadius: CGFloat = 14
    private let dark = CAShapeLayer()
    private let gradient = CAGradientLayer()
    private let line = CAShapeLayer()
    private var lineWidth: CGFloat = 0.9

    /// The dark line's opacity and width (inside the outline).
    private static let darkLine = (opacity: 0.3, width: CGFloat(1.6))

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for stroke in [dark, line] { stroke.fillColor = nil }
        dark.strokeColor = NSColor.black.withAlphaComponent(Self.darkLine.opacity).cgColor
        dark.lineWidth = Self.darkLine.width
        line.strokeColor = NSColor.black.cgColor
        gradient.mask = line
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(dark)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        line.frame = bounds
        dark.frame = bounds
        dark.path = path(inside: Self.darkLine.width)
        line.lineWidth = lineWidth
        line.path = path(inside: lineWidth)
        CATransaction.commit()
    }

    /// The outline inset by half of `width`, so a stroke that wide lies just inside it.
    private func path(inside width: CGFloat) -> CGPath {
        let inset = width / 2
        let radius = max(0, cornerRadius - inset)
        return CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func set(stops: [(white: Double, location: Double)], width: CGFloat) {
        guard !stops.isEmpty else { return }
        gradient.colors = stops.map { NSColor.white.withAlphaComponent($0.white).cgColor }
        gradient.locations = stops.map { NSNumber(value: $0.location) }
        if width != lineWidth {
            lineWidth = width
            needsLayout = true
        }
    }
}
