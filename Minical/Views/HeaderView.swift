import SwiftUI

struct HeaderView: View {
    @Environment(CalendarModel.self) private var model
    /// Three 26 pt buttons: ‹ today ›.
    private static let sideWidth: CGFloat = 78

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ArrowButton(direction: -1)
                TodayButton()
                ArrowButton(direction: 1)
            }
            .frame(width: Self.sideWidth, alignment: .leading)

            // Both button groups get the same width, so the title sits on the panel's center line.
            // `minWidth: 0` makes the title take exactly the space left, however long it is; a
            // longer title shrinks to fit rather than pushing the buttons aside.
            GeometryReader { geometry in
                RollingTitle(text: model.title, direction: model.pageDirection)
                    .scaleEffect(RollingTitle.fitScale(model.title, width: geometry.size.width - 8))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(minWidth: 0, maxWidth: .infinity)

            HStack(spacing: 0) {
                if model.canCreateEvents {
                    Button {
                        model.isComposing ? model.endComposing() : model.beginComposing()
                    } label: {
                        Image(systemName: "plus")
                            .rotationEffect(.degrees(model.isComposing ? 45 : 0))
                            .animation(Motion.panel, value: model.isComposing)
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help(model.isComposing ? Text("Cancel") : Text("New Event"))
                }

                MoreMenu()
            }
            .frame(width: Self.sideWidth, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(HoverButtonStyle())
        .frame(height: 30)
    }
}

/// A chevron that briefly darts in its own direction each time the calendar steps that way,
/// whether from a click, a swipe or the keyboard.
private struct ArrowButton: View {
    let direction: Int
    @Environment(CalendarModel.self) private var model

    var body: some View {
        let steps = direction > 0 ? model.forwardSteps : model.backwardSteps
        Button { model.navigate(direction) } label: {
            Image(systemName: direction > 0 ? "chevron.right" : "chevron.left")
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: steps) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(CGFloat(direction) * 5, duration: 0.11, spring: .snappy)
                        SpringKeyframe(0, duration: 0.42, spring: .bouncy(duration: 0.42, extraBounce: 0.15))
                    }
                }
        }
        .help(direction > 0 ? Text("Next") : Text("Previous"))
    }
}

/// Jumps back to today; lit in the highlight color while today is the selected day.
private struct TodayButton: View {
    @Environment(CalendarModel.self) private var model
    @Environment(\.highlight) private var highlight

    var body: some View {
        let showingToday = model.isShowingToday
        Button { model.goToToday() } label: {
            TodayGlyph(day: model.calendar.component(.day, from: model.today))
                // Lit in the highlight color while today is the selected day; otherwise it reads
                // like the other header buttons.
                .foregroundStyle(showingToday ? AnyShapeStyle(highlight) : AnyShapeStyle(.foreground))
                .animation(Motion.fade, value: showingToday)
        }
        .buttonStyle(HoverButtonStyle())
        .accessibilityLabel(Text("Today"))
        .help(Text("Go to Today"))
    }
}

/// The menu bar's calendar-page glyph at button size, tinted by the surrounding style.
private struct TodayGlyph: View {
    let day: Int

    var body: some View {
        Image(nsImage: CalendarGlyph.image(day: day, size: NSSize(width: 15, height: 14)))
            .renderingMode(.template)
    }
}

/// Month · Week · Day, with a selection pill that glides between segments.
struct ModeBar: View {
    @Environment(CalendarModel.self) private var model
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { mode in
                ModeSegment(mode: mode, isSelected: model.mode == mode, pill: pill) {
                    model.setMode(mode)
                }
            }
        }
        .padding(2)
        .background {
            Capsule().fill(.primary.opacity(0.07))
        }
        .frame(height: 26)
    }
}

private struct ModeSegment: View {
    let mode: ViewMode
    let isSelected: Bool
    let pill: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(mode.title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.primary.opacity(0.14))
                            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    } else {
                        Capsule()
                            .fill(.primary.opacity(hovering ? 0.06 : 0))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.95))
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// The header title, rolling letter by letter when the page changes. Every letter moves, even
/// those the old and new titles share ("ber" in October → November): the old word lifts away
/// letter after letter, then the new one rises in the same way, as one wave.
private struct RollingTitle: View {
    let text: String
    let direction: Int
    @State private var shown: String
    @State private var previous: String?
    @State private var rollDirection = 1
    @State private var progress = 1.0

    init(text: String, direction: Int) {
        self.text = text
        self.direction = direction
        _shown = State(initialValue: text)
    }

    static let font = NSFont.systemFont(ofSize: 15, weight: .semibold)

    /// How far to shrink `text` so it fits `width`: never enlarged, never below 80%.
    static func fitScale(_ text: String, width: CGFloat) -> CGFloat {
        let natural = (text as NSString).size(withAttributes: [.font: font]).width
        guard natural > width, width > 0 else { return 1 }
        return max(width / natural, 0.8)
    }

    var body: some View {
        RollingFrame(current: shown, previous: previous, direction: rollDirection, progress: progress)
            .onChange(of: text) { old, new in
                // Start from the beginning without animating the reset, then roll.
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    previous = shown
                    shown = new
                    rollDirection = direction == 0 ? 1 : direction
                    progress = 0
                }
                withAnimation(.linear(duration: 0.52)) { progress = 1 }
            }
    }
}

/// Draws both words for one moment of the roll; `progress` runs 0 → 1 across the whole roll.
private struct RollingFrame: View, Animatable {
    let current: String
    let previous: String?
    let direction: Int
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var distance: CGFloat { 9 * CGFloat(direction) }

    var body: some View {
        ZStack {
            if let previous, progress < 1 {
                letters(previous) { index, count in
                    let t = Self.window(progress, index: index, count: count, start: 0, spread: 0.14, length: 0.26)
                    let eased = Self.easeIn(t)
                    return (-distance * 0.7 * eased, 1 - t)
                }
            }
            letters(current) { index, count in
                guard previous != nil else { return (0, 1) }
                let t = Self.window(progress, index: index, count: count, start: 0.3, spread: 0.2, length: 0.5)
                return (distance * (1 - Self.easeOut(t)), min(1, t * 1.6))
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(current))
    }

    private func letters(_ word: String, motion: @escaping (Int, Int) -> (CGFloat, Double)) -> some View {
        let characters = Array(word)
        return HStack(spacing: 0) {
            ForEach(characters.indices, id: \.self) { index in
                let (offset, opacity) = motion(index, characters.count)
                Text(String(characters[index]))
                    .offset(y: offset)
                    .opacity(opacity)
            }
        }
    }

    /// A letter's own progress: letters start one after another across `spread`, each taking `length`.
    private static func window(_ progress: Double, index: Int, count: Int, start: Double, spread: Double, length: Double) -> Double {
        let begin = start + spread * Double(index) / Double(max(count - 1, 1))
        return min(max((progress - begin) / length, 0), 1)
    }

    private static func easeOut(_ t: Double) -> CGFloat { CGFloat(1 - pow(1 - t, 3)) }
    private static func easeIn(_ t: Double) -> CGFloat { CGFloat(t * t) }
}
