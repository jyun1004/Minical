import AppKit
import Observation
import Sparkle

/// Updates through Sparkle: the feed (`SUFeedURL`) is checked once a day in the background, and
/// "Check for Updates…" in the ⋯ menu checks at once. Debug builds don't check on their own, so a
/// development build never offers to replace itself with a release.
@MainActor
@Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    /// False while a check is under way (the menu item is disabled then).
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    @ObservationIgnored private let driverDelegate = DriverDelegate()

    private override init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: driverDelegate)
        super.init()
        #if DEBUG
        controller.updater.automaticallyChecksForUpdates = false
        #endif
        controller.startUpdater()
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in AppUpdater.shared.canCheckForUpdates = value }
        }
    }

    /// A menu bar app is never the active app, and Sparkle leaves an update found by the daily
    /// check unshown until it is. The system doesn't let an app take focus on its own either, so
    /// the update's window is put in front of the others without it.
    private final class DriverDelegate: NSObject, SPUStandardUserDriverDelegate {
        var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            guard handleShowingUpdate else { return }
            NSApp.activate()
            // Sparkle shows its window after this, a moment later.
            for delay in [0.1, 0.5, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    for window in NSApp.windows where window.isVisible && !(window is NSPanel) && window.styleMask.contains(.titled) {
                        window.orderFrontRegardless()
                    }
                }
            }
        }
    }

    func checkForUpdates() {
        // A menu bar app isn't active; without this the update window opens behind other apps.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}
