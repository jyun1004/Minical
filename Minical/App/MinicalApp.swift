import AppKit
import SwiftUI

@main
struct MinicalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item and its panel are AppKit-managed by `StatusItemController`.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = CalendarModel()
    private var statusItemController: StatusItemController?

    #if DEBUG
    private var previewWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(model: model)
        // Starts the daily update check.
        _ = AppUpdater.shared
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--sample-data") {
            model.loadSampleData(selecting: arguments.contains("--select-tomorrow") ? 1 : 0)
        }
        if let index = arguments.firstIndex(of: "--mode"), index + 1 < arguments.count,
           let mode = ViewMode(rawValue: arguments[index + 1]) {
            model.setMode(mode)
        }
        if arguments.contains("--compose") {
            model.showComposerForPreview()
        }
        // `--theme <name>` previews a theme without saving it; `--appearance` opens the sheet.
        let previewTheme = arguments.firstIndex(of: "--theme").flatMap { index in
            index + 1 < arguments.count ? PanelTheme(rawValue: arguments[index + 1]) : nil
        }
        if previewTheme != nil || arguments.contains("--appearance") {
            model.showAppearanceForPreview(theme: previewTheme, sheet: arguments.contains("--appearance"))
        }
        if arguments.contains("--preview-window") {
            showPreviewWindow()
        }
        if arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.statusItemController?.show() }
        }
        if arguments.contains("--demo") {
            playDemo()
        }
        #endif
    }

    #if DEBUG
    /// `--demo`: walks through the views and themes on its own, for recording the app's video.
    private func playDemo() {
        let model = model
        let steps: [(TimeInterval, @MainActor () -> Void)] = [
            (3.0, { model.moveSelection(byDays: 3) }),
            (4.6, { model.navigate(1) }),
            (6.0, { model.navigate(-1) }),
            (7.6, { model.setMode(.week) }),
            (9.4, { model.navigate(1) }),
            (10.8, { model.navigate(-1) }),
            (12.4, { model.setMode(.day) }),
            (14.6, { model.showAppearanceForPreview(theme: .duskGlass, sheet: false) }),
            (16.2, { model.showAppearanceForPreview(theme: .fadedGlass, sheet: false) }),
            (17.8, { model.showAppearanceForPreview(theme: .liquidGlass, sheet: false) }),
            (18.4, { model.setMode(.month) }),
            (20.0, { model.goToToday() }),
        ]
        for (time, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { MainActor.assumeIsolated(step) }
        }
    }
    #endif

    #if DEBUG
    /// Shows the popover content in a regular window so it can be inspected and screenshotted.
    private func showPreviewWindow() {
        let hosting = NSHostingView(rootView: CalendarPopover().environment(model))
        let size = hosting.fittingSize

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Minical Preview"
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.contentView = effect
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        previewWindow = window
    }
    #endif
}
