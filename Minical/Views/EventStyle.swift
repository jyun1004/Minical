import AppKit
import SwiftUI

/// The event look shared by the agenda, timeline and day strip: a card tinted in the calendar's
/// color, a bright accent bar, and the title in that accent (after AbleNotch's Alcove-measured rows).
extension Color {
    /// The calendar color lifted for a dark surface or deepened for a light one, so colored text
    /// stays readable on its own tint.
    func eventAccent(for scheme: ColorScheme) -> Color {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let isDark = scheme == .dark
        return Color(nsColor: NSColor(
            colorSpace: .sRGB, hue: hue,
            saturation: isDark ? saturation * 0.8 : saturation,
            brightness: isDark ? min(1, brightness * 1.28) : brightness * 0.78,
            alpha: alpha
        ))
    }
}

/// Slightly tighter at the top than at the bottom, like Alcove's event cards.
nonisolated struct EventCardShape: Shape {
    var top: CGFloat = 5.5
    var bottom: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top,
            style: .continuous
        )
        .path(in: rect)
    }
}

extension EnvironmentValues {
    /// Tint strength for event cards; a touch stronger in light mode where the wash reads weaker.
    var eventTint: Double { colorScheme == .dark ? 0.16 : 0.13 }
}

/// A card's tinted fill that brightens on hover and deepens on press; also publishes `isHovered`.
struct EventCardButtonStyle: ButtonStyle {
    let color: Color
    var shape = EventCardShape()
    /// Added to the usual tint, for cards that should read stronger (all-day banners).
    var extraTint: Double = 0

    func makeBody(configuration: Configuration) -> some View {
        EventCardButtonBody(configuration: configuration, color: color, shape: shape, extraTint: extraTint)
    }
}

private struct EventCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let shape: EventCardShape
    let extraTint: Double
    @Environment(\.eventTint) private var tint
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .environment(\.isHovered, hovering)
            .background {
                shape.fill(color.opacity(tint + extraTint + (pressed ? 0.14 : hovering ? 0.08 : 0)))
            }
            .contentShape(shape)
            .scaleEffect(pressed ? 0.98 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.press, value: pressed)
    }
}

extension AnyTransition {
    /// Content for a newly selected day: the old content is gone in a blink, then the new one
    /// rises a few points into place, so the two never overlap. No blur: a filter left on the
    /// settled view would change how its text renders over the vibrant background.
    static var eventSwap: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4))
                .animation(.easeOut(duration: 0.18).delay(0.1)),
            removal: .opacity
                .animation(.easeOut(duration: 0.1))
        )
    }
}

/// The current time, where the timeline's filled rail ends: a dot of the
/// highlight color, ringed in dark so it stands clear of the rail and of any event under it.
struct NowDot: View {
    static let size: CGFloat = 7
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Self.size, height: Self.size)
            .background {
                Circle()
                    .fill(.black.opacity(0.45))
                    .padding(-2)
            }
            .allowsHitTesting(false)
    }
}
