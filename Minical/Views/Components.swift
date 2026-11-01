import AppKit
import SwiftUI

enum Layout {
    static let width: CGFloat = 300
    static let gutter: CGFloat = 12
    static let cellHeight: CGFloat = 42
    /// Taller than wide so the tile wraps the number and its event dots as one unit.
    static let tileSize = CGSize(width: 32, height: 40)
    static let tileCornerRadius: CGFloat = 12
    static let numberOffset: CGFloat = -3.5
    static let dotsOffset: CGFloat = 9.5
    static let rowHeight: CGFloat = 40
    /// The most room the agenda takes; past three and a half rows it scrolls.
    static let agendaHeight: CGFloat = 3.5 * rowHeight
    /// The agenda's height with no events: room for the message and its button.
    static let agendaEmptyHeight: CGFloat = 1.6 * rowHeight
    /// Visible height of the scrolling hour timeline in week and day views when all-day events
    /// take their most room; it grows into whatever room they leave free.
    static let timelineHeight: CGFloat = 290
    static let timeGutter: CGFloat = 46
}

/// A borderless icon button with a soft rounded hover highlight and a springy press, like Control Center.
struct HoverButtonStyle: ButtonStyle {
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration, size: size)
    }
}

private struct HoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(hovering || pressed ? .primary : .secondary)
            .frame(minWidth: size, minHeight: size)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.primary.opacity(pressed ? 0.15 : hovering ? 0.08 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(pressed ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.press, value: pressed)
    }
}

/// A full-width row: hover wash, deeper wash and a slight shrink while pressed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowButtonBody(configuration: configuration)
    }
}

private struct RowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .environment(\.isHovered, hovering)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(pressed ? 0.12 : hovering ? 0.065 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(pressed ? 0.98 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.press, value: pressed)
    }
}

/// Capsule push button used for primary and secondary actions inside the popover.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct CapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.highlight) private var highlight
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background {
                Capsule()
                    .fill(prominent ? AnyShapeStyle(highlight.gradient) : AnyShapeStyle(.primary.opacity(0.08)))
                    .overlay {
                        Capsule().fill(.white.opacity(hovering && !pressed ? 0.08 : 0))
                    }
                    .overlay {
                        Capsule().fill(.black.opacity(pressed ? 0.12 : 0))
                    }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(pressed ? 0.95 : 1)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.press, value: pressed)
    }
}

/// Only scales on press; the label draws its own hover and selection states.
struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension EnvironmentValues {
    @Entry var isHovered = false
    /// The user's chosen highlight color; read this instead of `Color.accentColor`.
    @Entry var highlight: Color = .accentColor
}

/// A short slide-and-fade used when paging.
struct PageModifier: ViewModifier {
    let offset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// The outgoing page fades out fast, and the incoming one waits for it before fading in,
    /// so the two pages are never both visible: no ghosting. Offset and opacity only: both are
    /// composited on the GPU, and neither leaves a filter on the settled page that would change
    /// how its text renders.
    static func page(direction: Int) -> AnyTransition {
        let distance: CGFloat = 28 * CGFloat(direction)
        return .asymmetric(
            insertion: .modifier(
                active: PageModifier(offset: distance, opacity: 0),
                identity: PageModifier(offset: 0, opacity: 1)
            )
            .animation(Motion.page.delay(0.08)),
            removal: .modifier(
                active: PageModifier(offset: -distance * 0.5, opacity: 0),
                identity: PageModifier(offset: 0, opacity: 1)
            )
            .animation(.easeOut(duration: 0.09))
        )
    }
}

extension AnyTransition {
    /// The header title changing page: the old title leaves upward (or downward going back) in a
    /// blink, then the new one rises in after it, so the two never overlap.
    static func title(direction: Int) -> AnyTransition {
        let distance: CGFloat = 8 * CGFloat(direction == 0 ? 1 : direction)
        return .asymmetric(
            insertion: .modifier(
                active: TitleModifier(offset: distance, opacity: 0),
                identity: TitleModifier(offset: 0, opacity: 1)
            )
            .animation(Motion.page.delay(0.06)),
            removal: .modifier(
                active: TitleModifier(offset: -distance * 0.6, opacity: 0),
                identity: TitleModifier(offset: 0, opacity: 1)
            )
            .animation(.easeOut(duration: 0.09))
        )
    }
}

private struct TitleModifier: ViewModifier {
    let offset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
    }
}

/// Reports the hosting `NSWindow` once the view is installed in one.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {}

    final class WindowTrackingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
