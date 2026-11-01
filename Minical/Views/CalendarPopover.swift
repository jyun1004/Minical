import AppKit
import SwiftUI

struct CalendarPopover: View {
    /// Receives the content's natural height, so the panel can size itself to each view mode.
    var onHeightChange: ((CGFloat) -> Void)?

    @Environment(CalendarModel.self) private var model
    @State private var pager = ScrollPager()
    @State private var window: NSWindow?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HeaderView()
                ModeBar()
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ZStack(alignment: .top) {
                switch model.mode {
                case .month:
                    MonthPage { pager.activeRect = $0 }
                        .transition(modeTransition)
                case .week:
                    WeekPage()
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pager.activeRect = $0 }
                        .transition(modeTransition)
                case .day:
                    DayPage()
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pager.activeRect = $0 }
                        .transition(modeTransition)
                }
            }
        }
        .frame(width: Layout.width)
        .overlay(alignment: .bottom) { composer }
        .overlay(alignment: .bottom) { appearance }
        // Measure the natural height, then pin to the top of whatever size the panel currently is,
        // so the window can animate around the content.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange?($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.highlight, model.highlight.color)
        .environment(\.locale, model.calendar.locale ?? AppLocale.current)
        .tint(model.highlight.color)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .background(WindowAccessor { window in
            self.window = window
            pager.window = window
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window, note.object as? NSWindow === window else { return }
            focused = true
        }
        .onAppear {
            pager.onPage = { [model] offset in model.navigate(offset) }
            pager.allowsVertical = model.mode == .month
            pager.start()
            focused = true
        }
        .onChange(of: model.mode) { _, mode in pager.allowsVertical = mode == .month }
        .onDisappear { pager.stop() }
    }

    /// The outgoing mode leaves quickly so the window's resize follows the incoming one.
    private var modeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(Motion.fade.delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    @ViewBuilder
    private var composer: some View {
        if model.isComposing {
            ZStack(alignment: .bottom) {
                // A light scrim; clicking it dismisses the composer.
                Color.black.opacity(0.12)
                    .contentShape(Rectangle())
                    .onTapGesture { model.endComposing() }
                    .transition(.opacity)

                EventComposer()
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    }
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var appearance: some View {
        if model.isShowingAppearance {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.12)
                    .contentShape(Rectangle())
                    .onTapGesture { model.hideAppearance() }
                    .transition(.opacity)

                AppearanceSheet()
                    .padding(14)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    }
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // The composer's text fields own the keyboard while it is open.
        guard !model.isComposing else { return .ignored }
        // Over the calendar, the Appearance sheet takes Esc for itself and leaves the rest alone.
        if model.isShowingAppearance {
            guard press.key == .escape else { return .ignored }
            model.hideAppearance()
            return .handled
        }
        let command = press.modifiers.contains(.command)
        let paging = command || press.modifiers.contains(.option)

        // ⌘1 / ⌘2 / ⌘3, as in Calendar: day, week, month.
        if command, let mode = ["1": ViewMode.day, "2": .week, "3": .month][press.characters] {
            model.setMode(mode)
            return .handled
        }

        switch press.key {
        case .leftArrow:
            paging ? model.navigate(-1) : model.moveSelection(byDays: -1)
        case .rightArrow:
            paging ? model.navigate(1) : model.moveSelection(byDays: 1)
        case .upArrow:
            paging ? model.navigate(-1) : model.moveSelection(byDays: -7)
        case .downArrow:
            paging ? model.navigate(1) : model.moveSelection(byDays: 7)
        case .pageUp:
            model.navigate(-1)
        case .pageDown:
            model.navigate(1)
        case .return:
            SystemCalendar.openApp()
        default:
            guard press.modifiers.isEmpty else { return .ignored }
            switch press.characters.lowercased() {
            case "t": model.goToToday()
            case "m": model.setMode(.month)
            case "w": model.setMode(.week)
            case "d": model.setMode(.day)
            default: return .ignored
            }
        }
        return .handled
    }
}
