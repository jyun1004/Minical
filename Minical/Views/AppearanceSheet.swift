import SwiftUI

/// Theme, pane colour and strength, and the highlight colour, chosen in place over the calendar.
/// Every change shows on the panel itself right away.
struct AppearanceSheet: View {
    @Environment(CalendarModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Appearance")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { model.hideAppearance() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(HoverButtonStyle(size: 22))
                .help(Text("Close"))
            }

            section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(PanelTheme.allCases) { theme in
                        ThemeTile(theme: theme, paneColor: model.paneColor, paneStrength: model.paneStrength,
                                  isSelected: model.theme == theme) {
                            model.setTheme(theme)
                        }
                    }
                }
            }

            if model.theme == .pane {
                section("Pane Color") {
                    HStack(spacing: 0) {
                        ForEach(PaneColor.presets, id: \.hex) { preset in
                            Swatch(color: PaneColor.color(preset.hex), isSelected: model.paneColor == preset.hex) {
                                model.setPaneColor(preset.hex)
                            }
                            .help(Text(preset.name))
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                section("Strength") {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted")
                            .foregroundStyle(.tertiary)
                        Slider(value: Binding(get: { model.paneStrength }, set: { model.setPaneStrength($0) }), in: 0...1)
                            .controlSize(.small)
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10))
                }
                .transition(.opacity)
            }

            section("Highlight") {
                HStack(spacing: 0) {
                    ForEach(HighlightColor.allCases) { option in
                        Swatch(color: option.color, isSelected: model.highlight == option) {
                            model.setHighlight(option)
                        }
                        .help(Text(option.name))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .animation(Motion.panel, value: model.theme == .pane)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// A small picture of the panel in a theme, over a colourful backdrop so the glass reads as glass.
private struct ThemeTile: View {
    let theme: PanelTheme
    let paneColor: String
    let paneStrength: Double
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.highlight) private var highlight
    @State private var hovering = false

    private let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    backdrop
                    fill
                    miniCalendar
                    rim
                }
                .frame(height: 50)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(highlight, lineWidth: 2)
                        .padding(-3.5)
                        .opacity(isSelected ? 1 : 0)
                }
                .scaleEffect(hovering && !isSelected ? 1.04 : 1)

                Text(theme.name)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.95))
        .onHover { hovering = $0 }
        .animation(Motion.hoverSpring, value: hovering)
        .animation(Motion.select, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backdrop: some View {
        LinearGradient(colors: [Color(red: 0.18, green: 0.29, blue: 0.48), Color(red: 0.48, green: 0.36, blue: 0.56),
                                Color(red: 0.85, green: 0.6, blue: 0.48)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topLeading) {
                Circle().fill(Color(red: 1, green: 0.85, blue: 0.5)).frame(width: 22).offset(x: 34, y: 6)
            }
    }

    @ViewBuilder private var fill: some View {
        switch theme {
        case .system:
            Rectangle().fill(.regularMaterial)
        case .black:
            Color.black
        case .fadedGlass, .duskGlass, .liquidGlass:
            // The smoke as it lies on a panel of a typical height.
            let smoke = theme.smoke(height: 400)
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .mask {
                        // Dusk's glass fades out toward the bottom, as the panel's does.
                        if theme == .duskGlass {
                            let floor = PanelTheme.duskGlassFloor
                            LinearGradient(stops: smoke.map { .init(color: .black.opacity(floor + (1 - floor) * $0.black), location: $0.location) },
                                           startPoint: .top, endPoint: .bottom)
                        } else {
                            Color.black
                        }
                    }
                Color.black.opacity(theme.glassTint)
                if !smoke.isEmpty {
                    LinearGradient(stops: smoke.map { .init(color: .black.opacity($0.black), location: $0.location) },
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .environment(\.colorScheme, .dark)
        case .pane:
            let veil = PaneColor.veil(paneColor, strength: paneStrength)
            let color = PaneColor.color(paneColor)
            ZStack {
                Rectangle().fill(.thinMaterial)
                LinearGradient(stops: [.init(color: color.opacity(veil.edge), location: 0),
                                       .init(color: color.opacity(veil.middle), location: 0.5),
                                       .init(color: color.opacity(veil.edge), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    /// A hint of the calendar: a title bar and a few rows of days.
    private var miniCalendar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().frame(width: 22, height: 3)
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { column in
                        Circle()
                            .frame(width: 3, height: 3)
                            .opacity(row == 1 && column == 2 ? 0 : 1)
                            .overlay {
                                if row == 1 && column == 2 {
                                    Circle().fill(highlight).frame(width: 5, height: 5)
                                }
                            }
                    }
                }
            }
        }
        .foregroundStyle(theme == .system ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white.opacity(0.75)))
    }

    @ViewBuilder private var rim: some View {
        if !theme.rim.isEmpty {
            // The panel's edge: a dark line under the light one.
            shape.strokeBorder(.black.opacity(0.3), lineWidth: 1.6)
            shape.strokeBorder(
                LinearGradient(stops: theme.rim.map { .init(color: .white.opacity($0.white), location: $0.location) },
                               startPoint: .top, endPoint: .bottom),
                lineWidth: theme == .pane ? 0.75 : 0.9
            )
        } else {
            shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }
}

/// A colour dot with a ring when chosen.
private struct Swatch: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                .frame(width: 16, height: 16)
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(color, lineWidth: 1.5)
                        .opacity(isSelected ? 1 : 0)
                }
                .scaleEffect(hovering ? 1.12 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.85))
        .onHover { hovering = $0 }
        .animation(Motion.hoverSpring, value: hovering)
        .animation(Motion.select, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
