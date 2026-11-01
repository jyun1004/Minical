import AppKit

/// A window-server Space of our own, shown above every desktop, that the panel lives in (after
/// AbleNotch's). A window that merely joins all Spaces is copied into each desktop and slides
/// out with it during a Space switch, whatever its level; one in this Space belongs to no desktop
/// and stays where it is. Uses private SkyLight calls resolved at runtime; if any is missing the
/// panel keeps its normal all-Spaces behaviour.
@MainActor
enum PinnedSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let skyLight, let pointer = dlsym(skyLight, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let connection: Int32? = symbol("SLSMainConnectionID", as: MainConnection.self)?()

    /// Created once and shown above all user Spaces.
    private static let space: Int32? = {
        guard let connection,
              let create = symbol("SLSSpaceCreate", as: SpaceCreate.self),
              let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = symbol("SLSShowSpaces", as: ShowSpaces.self) else { return nil }
        let space = create(connection, 1, 0)
        guard space != 0 else { return nil }
        _ = setLevel(connection, space, 100)
        _ = show(connection, [space] as CFArray)
        return space
    }()

    /// Moves `window` into the pinned Space. Needs a window number, so call it once the window
    /// has been ordered in.
    static func pin(_ window: NSWindow) {
        guard let connection, let space, window.windowNumber > 0,
              let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self) else { return }
        _ = add(connection, space, [window.windowNumber] as CFArray, 7)
    }
}
