import AppKit

/// Turns trackpad swipes and mouse wheel ticks over the calendar into page changes.
/// Follows the user's scroll direction setting: content moving left or up means "next page".
final class ScrollPager {
    /// `ignored`: the gesture began outside the active area, so it belongs to whatever is under it.
    private enum Axis { case undecided, horizontal, vertical, ignored }

    weak var window: NSWindow?
    /// The active area in SwiftUI's global space (window content, top-left origin).
    var activeRect: CGRect = .zero
    /// Off over scrollable timelines, where vertical scrolling must move the hours instead.
    var allowsVertical = true
    var onPage: ((Int) -> Void)?

    private var monitor: Any?
    private var axis = Axis.undecided
    private var accumulated: CGFloat = 0
    private var didPageThisGesture = false
    /// Whether this gesture is being consumed for paging, so its inertia is swallowed too.
    private var consumingGesture = false
    private var lastWheelPage = Date.distantPast

    private let swipeThreshold: CGFloat = 28
    private let wheelInterval: TimeInterval = 0.16

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the event was consumed as paging.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, let content = window.contentView else { return false }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            let location = content.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: location.x, y: content.isFlipped ? location.y : content.bounds.height - location.y)
            axis = activeRect.contains(point) ? .undecided : .ignored
            accumulated = 0
            didPageThisGesture = false
            consumingGesture = false
        }

        // Inertia belongs to whoever owned the gesture.
        if !event.momentumPhase.isEmpty { return consumingGesture }

        if event.phase.isEmpty {
            return handleWheel(event, content: content, dx: dx, dy: dy)
        }
        if axis == .ignored { return false }

        // Never claim a gesture before its direction is known: claiming it here also swallowed
        // the inertia of every vertical scroll over the timeline, which made it stutter and stop.
        if axis == .undecided {
            guard abs(dx) + abs(dy) > 0.5 else { return false }
            axis = abs(dx) > abs(dy) ? .horizontal : .vertical
        }
        if axis == .vertical, !allowsVertical { return false }

        consumingGesture = true
        accumulated += axis == .horizontal ? dx : dy
        if !didPageThisGesture, abs(accumulated) > swipeThreshold {
            didPageThisGesture = true
            onPage?(accumulated < 0 ? 1 : -1)
        }
        return true
    }

    /// A classic mouse wheel: one page per notch, lightly debounced. Vertical only when allowed.
    private func handleWheel(_ event: NSEvent, content: NSView, dx: CGFloat, dy: CGFloat) -> Bool {
        let location = content.convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: location.x, y: content.isFlipped ? location.y : content.bounds.height - location.y)
        guard activeRect.contains(point) else { return false }
        let horizontal = abs(dx) > abs(dy)
        guard horizontal || allowsVertical else { return false }

        let delta = horizontal ? dx : dy
        guard abs(delta) > 0.1 else { return true }
        guard Date().timeIntervalSince(lastWheelPage) > wheelInterval else { return true }
        lastWheelPage = Date()
        onPage?(delta < 0 ? 1 : -1)
        return true
    }
}
