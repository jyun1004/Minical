import AppKit
import Observation
import SwiftUI

/// Owns the menu bar item and the calendar panel beneath it.
///
/// A hand-rolled panel instead of `MenuBarExtra`, because the window height has to follow the
/// view mode and animate smoothly. `MenuBarExtra` sizes its window from the SwiftUI ideal size,
/// which can't be animated and which a scroll view inflates, clipping the content.
final class StatusItemController: NSObject, NSWindowDelegate {
    private let model: CalendarModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = CalendarPanel()
    /// Clear root view spanning the window, including the margins the shadow is drawn into.
    private let root = PanelRootView()
    /// The visible card. It draws its own shadow, so the shadow fades with it.
    private let card = PanelCardView()
    /// Fades the whole window. The fade is on the window, not the card's layer: a layer fading
    /// over the vibrant material switches its blur off until fully opaque, so the blur popped on
    /// at the end of every open and off at the start of every close.
    private var fade: WindowFade?
    /// Bumped by each open or close, so a finished open only cleans up if nothing followed it.
    private var materializeGeneration = 0
    /// The card's themed surface: base, tint, content and edge.
    private let background = PanelBackgroundView(cornerRadius: 14)
    private var hostingView: NSHostingView<AnyView>!
    private var outsideClickMonitor: Any?
    private var contentHeight: CGFloat = 540
    /// The card's height on screen, which trails `contentHeight` while a resize animates.
    private var cardHeight: CGFloat = 540
    private var resize: FrameAnimation?
    /// When the panel last closed, to tell a click on the icon that already closed it from one
    /// meant to open it.
    private var lastHide = Date.distantPast
    /// When the active Space last changed, to tell the focus a Space switch takes from the panel
    /// from focus taken by the user.
    private var lastSpaceChange = Date.distantPast
    private(set) var isShown = false

    private let width = Layout.width
    private let gapBelowMenuBar: CGFloat = 6
    private let cornerRadius: CGFloat = 14
    /// Transparent room around the card for its shadow and its opening lift.
    private let margins = NSEdgeInsets(top: 6, left: 28, bottom: 40, right: 28)

    init(model: CalendarModel) {
        self.model = model
        super.init()

        // Deferred: the height arrives mid-layout, and resizing the window then makes AppKit
        // apply the resize to the root view a second time once the layout pass ends.
        let content = CalendarPopover { [weak self] height in
            DispatchQueue.main.async { self?.contentHeightChanged(height) }
        }
            .environment(model)
        hostingView = NSHostingView(rootView: AnyView(content))
        // The panel decides its own size; the hosting view must not push back.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        // Pinned by hand at its natural height from the card's top (see `pinHosting`); a free
        // bottom margin keeps Auto Layout from sizing the card, and the window, around it.
        hostingView.autoresizingMask = [.minYMargin]

        background.autoresizingMask = [.width, .height]
        background.setContent(hostingView)

        card.cornerRadius = cornerRadius
        // Hangs from the window's top edge (see `layoutCard`); the bottom margin stays free so the
        // card's height can animate without Auto Layout stretching the window's root to fit.
        card.autoresizingMask = [.minYMargin]
        card.addSubview(background)
        root.addSubview(card)
        root.onClickOutsideCard = { [weak self] in self?.hide() }
        panel.contentView = root
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            // Draw the glyph at its own size; the default scaling shrinks it to fit a smaller box.
            button.imageScaling = .scaleNone
        }
        updateIcon()
        updateTheme()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
    }

    // MARK: Theme

    /// Redraws the card whenever the theme or the pane's colour or strength changes. Every theme
    /// but System is dark, so the panel takes the dark appearance for those.
    private func updateTheme() {
        withObservationTracking {
            let theme = model.theme
            background.apply(theme, paneColor: model.paneColor, paneStrength: model.paneStrength)
            panel.appearance = theme.forcesDarkAppearance ? NSAppearance(named: .darkAqua) : nil
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateTheme() }
        }
    }

    // MARK: Icon

    /// Redraws the date glyph whenever the model's notion of today changes.
    private func updateIcon() {
        withObservationTracking {
            let day = model.calendar.component(.day, from: model.today)
            statusItem.button?.image = StatusIcon.image(day: day)
            statusItem.button?.setAccessibilityLabel(model.today.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(AppLocale.current)))
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    // MARK: Showing and hiding

    @objc private func toggle() {
        if isShown { hide(); return }
        // Pressing the icon takes focus from the panel, which closes it a moment before this
        // action arrives. That same press must not open it again.
        guard Date().timeIntervalSince(lastHide) > 0.3 else { return }
        show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        model.prepareForPresentation()

        if !panel.isVisible {
            // A fresh open starts transparent, in place. Reopening while still closing skips
            // this and fades back in from wherever the alpha is.
            resize?.stop()
            resize = nil
            // As tall as the screen allows, sized now while unseen: the card then grows and
            // shrinks inside it, and the window is never resized on screen (see
            // `contentHeightChanged`). Its empty area is fully transparent, so clicks pass through.
            panel.setFrame(windowFrame(forHeight: .greatestFiniteMagnitude), display: false)
            cardHeight = cardHeight(for: contentHeight)
            layoutCard()
            panel.alphaValue = 0
            setMaterialize(scale: Self.appearScale, blur: Self.appearBlur)
        }
        panel.makeKeyAndOrderFront(nil)
        // Out of the desktops, so a Space switch leaves the panel where it is. Ordering out can
        // drop it from that Space, so this runs on every open.
        PinnedSpace.pin(panel)
        fadeWindow(to: 1, motion: Self.appear)
        animateMaterialize(opening: true)

        setIconHighlighted(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                // The menu bar delivers presses on our own icon here too; the icon's action
                // handles those, so it alone decides whether that press closes the panel.
                guard let self, !self.isPointerOverIcon else { return }
                self.hide()
            }
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        lastHide = Date()
        setIconHighlighted(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil

        animateMaterialize(opening: false)
        fadeWindow(to: 0, motion: Self.disappear) { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Fades the window from its current alpha, frame by frame on the display's own clock,
    /// optionally after a delay. The time it takes shrinks with the distance left, so a reversal
    /// mid-fade stays smooth.
    private func fadeWindow(to target: CGFloat, motion: FadeCurve, completion: (() -> Void)? = nil) {
        fade?.stop()
        let start = panel.alphaValue
        let scaled = motion.duration * max(Double(abs(target - start)), 0.25) * Self.slowMotion
        fade = WindowFade(window: panel, view: root, from: start, to: target, duration: scaled,
                          timing: motion.timing) { [weak self] in
            self?.fade = nil
            completion?()
        }
    }

    /// The icon's look is left to the menu bar: it highlights an item only while it is pressed,
    /// since it keeps that look only for items that open a standard menu.
    private func setIconHighlighted(_ highlighted: Bool) {
        statusItem.button?.highlight(highlighted)
    }

    private var isPointerOverIcon: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    // MARK: Materialize

    /// Control Center's panel doesn't just fade: its content comes in a little small and out of
    /// focus, sharpening and growing into place (top-anchored, so it also settles slightly
    /// downward); closing runs the same motion backwards. The scale is on the card, so its shadow follows;
    /// the blur is on the content alone, never on the material (blurring a layer over the vibrant
    /// backdrop would switch the backdrop off). Both start from what is on screen, so a reversal
    /// mid-way is seamless, and the blur filter is removed entirely once the panel is open.
    private func animateMaterialize(opening: Bool) {
        guard let cardLayer = card.layer, let contentLayer = hostingView.layer else { return }
        installBlur()
        materializeGeneration += 1
        let generation = materializeGeneration

        // Closing plays opening exactly backwards: the same length, each curve reversed in time,
        // back to the same small, out-of-focus start.
        let curve = opening ? Self.appear : Self.disappear
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = (cardLayer.presentation() ?? cardLayer).transform
        scale.toValue = opening ? CATransform3DIdentity : scaleTransform(Self.appearScale)
        scale.duration = curve.duration
        scale.timingFunction = curve.timing

        let currentBlur = (contentLayer.presentation()?.value(forKeyPath: Self.blurKey) as? CGFloat)
            ?? (contentLayer.value(forKeyPath: Self.blurKey) as? CGFloat) ?? 0
        let blur = CABasicAnimation(keyPath: Self.blurKey)
        blur.fromValue = currentBlur
        blur.toValue = opening ? 0 : Self.appearBlur
        // Opening comes into focus over its first stretch; closing goes out of focus over its
        // last stretch, after the same pause it ended on when opening.
        blur.duration = Self.blurDuration
        blur.timingFunction = opening ? Self.blurIn : Self.blurOut
        if !opening, currentBlur < 0.01 {
            blur.beginTime = contentLayer.convertTime(CACurrentMediaTime(), from: nil)
                + (curve.duration - Self.blurDuration) * Self.slowMotion
            blur.fillMode = .backwards
        }

        for animation in [scale, blur] { animation.speed = Float(1 / Self.slowMotion) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, opening, self.isShown, generation == self.materializeGeneration else { return }
                self.hostingView.layer?.filters = nil
            }
        }
        cardLayer.transform = scale.toValue as! CATransform3D
        contentLayer.setValue(blur.toValue, forKeyPath: Self.blurKey)
        cardLayer.add(scale, forKey: "materialize")
        contentLayer.add(blur, forKey: "materialize")
        CATransaction.commit()
    }

    /// Puts the card at a given scale and the content at a given blur, without animating.
    private func setMaterialize(scale: CGFloat, blur: CGFloat) {
        guard let cardLayer = card.layer, let contentLayer = hostingView.layer else { return }
        installBlur()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardLayer.removeAnimation(forKey: "materialize")
        contentLayer.removeAnimation(forKey: "materialize")
        cardLayer.transform = scaleTransform(scale)
        contentLayer.setValue(blur, forKeyPath: Self.blurKey)
        CATransaction.commit()
    }

    private func installBlur() {
        guard let contentLayer = hostingView.layer, contentLayer.filters?.isEmpty ?? true,
              let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.name = "blur"
        filter.setValue(0, forKey: kCIInputRadiusKey)
        hostingView.layerUsesCoreImageFilters = true
        contentLayer.filters = [filter]
    }

    /// Scaled around the card's top centre, the edge that hangs from the menu bar.
    private func scaleTransform(_ scale: CGFloat) -> CATransform3D {
        guard let layer = card.layer, scale != 1 else { return CATransform3DIdentity }
        let bounds = layer.bounds
        let anchor = layer.anchorPoint
        let top = CGPoint(
            x: bounds.width / 2 - bounds.width * anchor.x,
            y: (layer.isGeometryFlipped ? 0 : bounds.height) - bounds.height * anchor.y
        )
        let shift = CATransform3DMakeTranslation(top.x * (1 - scale), top.y * (1 - scale), 0)
        return CATransform3DScale(shift, scale, scale, 1)
    }

    private static let blurKey = "filters.blur.inputRadius"
    private static let appearScale: CGFloat = 0.93
    private static let appearBlur: CGFloat = 10
    private static let blurDuration = 0.22
    private static let blurIn = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
    /// `blurIn` reversed in time.
    private static let blurOut = CAMediaTimingFunction(controlPoints: 0.8, 0, 0.8, 1)

    private struct FadeCurve {
        let duration: Double
        let timing: CAMediaTimingFunction
    }

    /// Control Center's opening curve, measured: a hesitant first frame, half its way within the
    /// first quarter, then a long, gentle settle; played about a tenth slower than its 0.33 s,
    /// which felt rushed here. Closing is the same motion run backwards.
    private static let appear = FadeCurve(duration: 0.36, timing: CAMediaTimingFunction(controlPoints: 0.2, 0, 0.1, 1))
    /// `appear` reversed in time: control points (x1, y1, x2, y2) become (1 − x2, 1 − y2, 1 − x1, 1 − y1).
    private static let disappear = FadeCurve(duration: 0.36, timing: CAMediaTimingFunction(controlPoints: 0.9, 0, 0.8, 1))

    #if DEBUG
    /// `--slow-motion [factor]` plays the open and close animations that many times slower (ten
    /// by default), to inspect them.
    private static let slowMotion: Double = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--slow-motion") else { return 1 }
        return index + 1 < arguments.count ? Double(arguments[index + 1]) ?? 10 : 10
    }()
    #else
    private static let slowMotion: Double = 1
    #endif

    func windowDidResignKey(_ notification: Notification) {
        // A Space switch hands focus to the new desktop's front app a moment after announcing
        // itself. The panel stays open through it (it sits in its own Space, see `PinnedSpace`) and
        // takes focus back, so the keyboard and the usual ways of closing it keep working.
        if isShown, Date().timeIntervalSince(lastSpaceChange) < 0.3 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isShown else { return }
                self.panel.makeKey()
            }
            return
        }
        hide()
    }

    @objc private func activeSpaceChanged() {
        lastSpaceChange = Date()
    }

    // MARK: Sizing

    /// The SwiftUI content reports its natural height; the card follows, its top edge pinned under
    /// the menu bar and its bottom edge gliding to the new height.
    ///
    /// The window itself is never resized while on screen: a resized window shows a blank frame
    /// while its new backing is drawn, which read as the panel blinking off and on. It is already
    /// as tall as the screen allows, so only the card's frame changes.
    private func contentHeightChanged(_ height: CGFloat) {
        let height = ceil(height)
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard panel.isVisible else { return }

        // The content is laid out once at its final height; only the card's edge moves.
        resize?.stop()
        let from = cardHeight
        let to = cardHeight(for: height)

        resize = FrameAnimation(view: root, duration: 0.34,
                                timing: CAMediaTimingFunction(controlPoints: 0.25, 1, 0.3, 1)) { [weak self] progress in
            guard let self else { return }
            cardHeight = from + (to - from) * progress
            layoutCard()
        } completion: { [weak self] in
            guard let self else { return }
            resize = nil
        }
    }

    /// `height` as the card shows it, after the window frame clamps it to the screen.
    private func cardHeight(for height: CGFloat) -> CGFloat {
        windowFrame(forHeight: height).height - margins.top - margins.bottom
    }

    /// Places the card at its current height, hanging from the top of the window's margins.
    private func layoutCard() {
        let bounds = root.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.frame = NSRect(
            x: margins.left,
            y: bounds.height - margins.top - cardHeight,
            width: bounds.width - margins.left - margins.right,
            height: max(0, cardHeight)
        )
        background.frame = card.bounds
        pinHosting()
        CATransaction.commit()
    }

    /// Keeps the content pinned to the top of the card, in a hosting view as tall as the tallest
    /// card the window can hold; the rounded background clips what hangs below. The SwiftUI root
    /// aligns itself to the top, so a taller layout only reaches further down. A hosting view sized
    /// to the content would trail each change by a frame, and in that frame SwiftUI centers the
    /// overflowing content, which showed as the whole panel jumping and blinking on resize.
    private func pinHosting() {
        let height = max(contentHeight, root.bounds.height - margins.top - margins.bottom)
        let size = NSSize(width: width, height: height)
        if hostingView.frame.size != size { hostingView.setFrameSize(size) }
        hostingView.setFrameOrigin(NSPoint(x: 0, y: background.bounds.height - height))
    }

    func windowDidResize(_ notification: Notification) {
        layoutCard()
    }

    /// The window frame: the card under the icon, plus the transparent margins around it.
    private func windowFrame(forHeight height: CGFloat) -> NSRect {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            return NSRect(x: 0, y: 0, width: width + margins.left + margins.right,
                          height: height + margins.top + margins.bottom)
        }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let clampedHeight = min(height, visible.height - gapBelowMenuBar - 8)
        let x = min(max(buttonFrame.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let top = min(buttonFrame.minY, visible.maxY) - gapBelowMenuBar
        let card = NSRect(x: x, y: top - clampedHeight, width: width, height: clampedHeight)
        return NSRect(
            x: card.minX - margins.left,
            y: card.minY - margins.bottom,
            width: card.width + margins.left + margins.right,
            height: card.height + margins.top + margins.bottom
        )
    }
}

/// Steps a window's alpha on a display link: smooth at the display's refresh rate, and stoppable
/// at any frame so the next fade can start from exactly where this one left off.
final class WindowFade: NSObject {
    private weak var window: NSWindow?
    private let from: CGFloat
    private let to: CGFloat
    private let duration: Double
    private let delay: Double
    private let curve: UnitBezier
    private let completion: () -> Void
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval?

    init(window: NSWindow, view: NSView, from: CGFloat, to: CGFloat, duration: Double, delay: Double = 0,
         timing: CAMediaTimingFunction, completion: @escaping () -> Void) {
        self.window = window
        self.from = from
        self.to = to
        self.duration = max(duration, 0.001)
        self.delay = delay
        self.curve = UnitBezier(timing)
        self.completion = completion
        super.init()
        link = view.displayLink(target: self, selector: #selector(step(_:)))
        link?.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        // Aim at the frame about to be shown, not the one just shown.
        let now = link.targetTimestamp
        let start = startTime ?? link.timestamp
        startTime = start
        let t = min(max((now - start - delay) / duration, 0), 1)
        let eased = curve.value(at: t)
        window?.alphaValue = from + (to - from) * eased
        if t >= 1 {
            stop()
            completion()
        }
    }
}

/// Steps an eased progress from 0 to 1 on a display link, for animating frames by hand.
final class FrameAnimation: NSObject {
    private let duration: Double
    private let curve: UnitBezier
    private let onStep: (CGFloat) -> Void
    private let completion: () -> Void
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval?

    init(view: NSView, duration: Double, timing: CAMediaTimingFunction,
         step: @escaping (CGFloat) -> Void, completion: @escaping () -> Void) {
        self.duration = max(duration, 0.001)
        self.curve = UnitBezier(timing)
        self.onStep = step
        self.completion = completion
        super.init()
        link = view.displayLink(target: self, selector: #selector(step(_:)))
        link?.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        // Aim at the frame about to be shown, not the one just shown.
        let start = startTime ?? link.timestamp
        startTime = start
        let t = min(max((link.targetTimestamp - start) / duration, 0), 1)
        onStep(CGFloat(curve.value(at: t)))
        if t >= 1 {
            stop()
            completion()
        }
    }
}

/// Evaluates a `CAMediaTimingFunction` at a point in time, for animations stepped by hand.
struct UnitBezier {
    private let p1: CGPoint
    private let p2: CGPoint

    init(_ function: CAMediaTimingFunction) {
        var a: [Float] = [0, 0], b: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &a)
        function.getControlPoint(at: 2, values: &b)
        p1 = CGPoint(x: CGFloat(a[0]), y: CGFloat(a[1]))
        p2 = CGPoint(x: CGFloat(b[0]), y: CGFloat(b[1]))
    }

    private func bezier(_ t: CGFloat, _ c1: CGFloat, _ c2: CGFloat) -> CGFloat {
        let u = 1 - t
        return 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t
    }

    /// The curve's progress at time `x` (0…1): solve for the parameter by bisection, then read y.
    func value(at x: Double) -> Double {
        let x = CGFloat(min(max(x, 0), 1))
        var low: CGFloat = 0, high: CGFloat = 1, t = x
        for _ in 0..<24 {
            t = (low + high) / 2
            if bezier(t, p1.x, p2.x) < x { low = t } else { high = t }
        }
        return Double(bezier(t, p1.y, p2.y))
    }
}

/// The window's clear root. A press in the margin around the card (its shadow) counts as a press
/// outside the panel.
final class PanelRootView: NSView {
    var onClickOutsideCard: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClickOutsideCard?()
    }
}

/// The card: draws a soft shadow that follows its rounded shape, so the shadow fades and scales
/// with it (the window's own shadow is computed once and could not).
final class PanelCardView: NSView {
    var cornerRadius: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.32
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -8)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Presses the content leaves unhandled (empty parts of the header, gaps between rows) bubble
    /// up to here; stop them so they don't reach the root, which would treat them as outside.
    override func mouseDown(with event: NSEvent) {}

    override func layout() {
        super.layout()
        updateShadowPath()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateShadowPath()
    }

    func updateShadowPath() {
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }
}

/// A borderless panel that can take keyboard focus without activating the app,
/// so the frontmost app keeps its menu bar while the calendar is open.
final class CalendarPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        // The card draws its own shadow, so it can fade and scale with the card.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Always draw as active. A press in another app's window takes key from the panel at the
    /// same moment it starts closing, and Liquid Glass (which, unlike NSVisualEffectView, has no
    /// `state` to pin) then switched to its paler inactive look in a single frame, which read as
    /// a blink. AppKit asks this private method; if it ever stops, the panel just looks as before.
    @objc func _hasActiveAppearance() -> Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
