#!/usr/bin/env swift
// Renders the Minical app icon into an .appiconset.
// Usage: swift scripts/make-icon.swift Minical/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)

    // Laid out top-down, as the mockup was drawn.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824pt body inside a 1024pt canvas, white, lit a touch from above.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(shape)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let light = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).cgColor,
        NSColor(srgbRed: 0.933, green: 0.941, blue: 0.953, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(light, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
    ctx.restoreGState()

    // Its edge, for a white icon on a light desktop.
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
    ctx.setLineWidth(1)
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.strokePath()

    // The menu bar glyph (`CalendarGlyph`), grown: a page with its binding strip along the top,
    // and a pair of tall eyes looking out of it.
    let ink = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1).cgColor
    ctx.setFillColor(ink)
    ctx.setStrokeColor(ink)
    let page = CGRect(x: 262, y: 250, width: 500, height: 520)
    ctx.setLineWidth(30)
    ctx.addPath(CGPath(roundedRect: page.insetBy(dx: 15, dy: 15), cornerWidth: 82, cornerHeight: 82, transform: nil))
    ctx.strokePath()

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: page, cornerWidth: 96, cornerHeight: 96, transform: nil))
    ctx.clip()
    ctx.fill(CGRect(x: page.minX, y: page.minY, width: page.width, height: 118))
    ctx.restoreGState()

    for x: CGFloat in [420, 604] {
        let eye = CGRect(x: x - 20, y: 510 - 56, width: 40, height: 112)
        ctx.addPath(CGPath(roundedRect: eye, cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(pixels: points * scale).write(to: outputDirectory.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outputDirectory.path)")
