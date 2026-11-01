import AppKit
import QuartzCore

/// The glass's lens, after AbleNotch's (`GlassTuner.lens` and `GlassShaper.sizeValues`): clear and
/// sharp along the edge, where it bends what's behind and splits its colours a little; a light
/// haze further in, so the content over it reads. No milky veil: blacks stay black, whites white.
/// Set on the Liquid Glass's backdrop (a `CABackdropLayer` with a "glassBackground" filter) by
/// key path, and again whenever the glass resets it. Private layer details: if they're not there,
/// nothing is changed and the system's glass stays as it is.
@MainActor
enum GlassLens {
    /// The values for a glass whose shorter side is `side` (`clear`: the clear glass's).
    static func values(side: CGFloat, clear: Bool) -> [String: CGFloat] {
        systemValues(side, clear: clear).merging(lens(side: side)) { $1 }
    }

    private static func lens(side: CGFloat) -> [String: CGFloat] {
        [
            "inputBlurRadius": 1.2,
            // The blur's strength by depth into the glass (negative inside): none for the outer
            // 12 pt, all of it from 30 pt in.
            "inputBlurDistance0": -400, "inputBlurOpacity0": 1,
            "inputBlurDistance1": -30, "inputBlurOpacity1": 1,
            "inputBlurDistance2": -12, "inputBlurOpacity2": 0,
            "inputBlurDistance3": 0, "inputBlurOpacity3": 0,
            "inputBleedAmount": 0,
            "inputFaceColorMatrixWhite": 1, "inputFaceColorMatrixBlack": 0,
            "inputFaceColorMatrixMaxLuma": 1, "inputFaceColorMatrixMaxLumaSDR": 1,
            // The colours split along the edge.
            "inputAberrationAmount": 3, "inputAberrationHeight": min(16, 0.4 * max(side, 0)),
        ]
    }

    /// The values the system sets by the glass's size, read off its glass (macOS 27), regular and
    /// clear: the bend along the edge and its light.
    private static func systemValues(_ side: CGFloat, clear: Bool) -> [String: CGFloat] {
        let h = max(side, 0)
        let bend = min(1, max(0, (h - 44) / 56))
        if clear {
            return [
                "inputInnerRefractionAmount": -min(0.65 * h, 60) * bend,
                "inputInnerRefractionHeight": min(0.36 * h, 20),
                "inputShadowAmount": min(0.625 * h, 75),
                "inputShadowHeight": min(0.4 * h, 80),
            ]
        }
        return [
            "inputInnerRefractionAmount": -min(0.5 * h, 60) * bend,
            "inputInnerRefractionHeight": min(0.25 * h, 20),
            "inputBleedHeight": 0.35 * h,
        ]
    }

    /// Sets `values` on every glass backdrop under `layer`. Returns whether one was found.
    @discardableResult
    static func apply(_ layer: CALayer?, _ values: [String: CGFloat]) -> Bool {
        guard let layer else { return false }
        var found = false
        if String(describing: type(of: layer)).contains("Backdrop"), let filters = layer.filters as? [NSObject],
           let filter = filters.first(where: { ($0.value(forKey: "name") as? String) == "glassBackground" }) {
            found = true
            for (key, value) in values {
                let current = (filter.value(forKey: key) as? NSNumber)?.doubleValue
                guard current.map({ abs($0 - Double(value)) > 1e-6 }) ?? true else { continue }
                // By key path: the filter's own values changed in place don't reach the render server.
                layer.setValue(NSNumber(value: Double(value)), forKeyPath: "filters.glassBackground." + key)
            }
            watch(layer) { apply($0, values) }
        }
        for sublayer in layer.sublayers ?? [] where apply(sublayer, values) { found = true }
        return found
    }

    /// The glass resets its filter as it's resized: watched, so it's retuned the moment it changes
    /// rather than at the next layout.
    private static var watched: [ObjectIdentifier: NSKeyValueObservation] = [:]
    /// The latest retune asked for each watched layer (a theme or size change asks for others).
    private static var retunes: [ObjectIdentifier: @MainActor (CALayer) -> Void] = [:]

    private static func watch(_ layer: CALayer, _ retune: @escaping @MainActor (CALayer) -> Void) {
        let id = ObjectIdentifier(layer)
        retunes[id] = retune
        guard watched[id] == nil else { return }
        watched[id] = layer.observe(\.filters, options: []) { layer, _ in
            guard Thread.isMainThread else { return }
            nonisolated(unsafe) let layer = layer
            MainActor.assumeIsolated { retunes[ObjectIdentifier(layer)]?(layer) }
        }
        // Dropped with the layer (the glass rebuilds its layers now and then).
        if watched.count > 16 {
            watched = watched.filter { $0.key == id }
            retunes = retunes.filter { $0.key == id }
        }
    }
}
