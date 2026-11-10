import AppKit
import CoreGraphics
import Foundation

struct Variant {
    let name: String
    let bgTop: String
    let bgBottom: String
    let window: String
    let frame: String
    let prompt: String
    let dot: String
}

let variants = [
    Variant(name: "Light", bgTop: "#f4f4f2", bgBottom: "#e2e2de", window: "#ffffff", frame: "#d4d4cf", prompt: "#c47e10", dot: "#2f9a4c"),
    Variant(name: "Amber", bgTop: "#f6c25e", bgBottom: "#e49a2a", window: "#141416", frame: "#3a2a10", prompt: "#f0b14a", dot: "#4cc26a"),
    Variant(name: "Midnight", bgTop: "#252a48", bgBottom: "#121426", window: "#0f1020", frame: "#2f3460", prompt: "#7aa2f7", dot: "#bb9af7"),
    Variant(name: "Dracula", bgTop: "#3a3c4e", bgBottom: "#22232e", window: "#282a36", frame: "#44475a", prompt: "#ff79c6", dot: "#50fa7b"),
    Variant(name: "Mono", bgTop: "#1a1a1a", bgBottom: "#000000", window: "#000000", frame: "#333333", prompt: "#ffffff", dot: "#ffffff"),
    Variant(name: "Mint", bgTop: "#1d3b33", bgBottom: "#0d1f1a", window: "#0b1714", frame: "#24493f", prompt: "#7ee0b5", dot: "#f0b14a"),
]

func color(_ hex: String) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt64(s, radix: 16) ?? 0
    return CGColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

func render(_ v: Variant, size: Int = 1024) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let s = CGFloat(size) / 1024
    let grad = CGGradient(colorsSpace: cs, colors: [color(v.bgTop), color(v.bgBottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
    let win = CGRect(x: 155 * s, y: 185 * s, width: 734 * s, height: 634 * s)
    let path = CGPath(roundedRect: win, cornerWidth: 68 * s, cornerHeight: 68 * s, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(color(v.window))
    ctx.fillPath()
    ctx.addPath(path)
    ctx.setStrokeColor(color(v.frame))
    ctx.setLineWidth(10 * s)
    ctx.strokePath()
    ctx.setFillColor(color(v.prompt))
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: 243 * s, y: 618 * s))
    chevron.addLine(to: CGPoint(x: 398 * s, y: 556 * s))
    chevron.addLine(to: CGPoint(x: 398 * s, y: 525 * s))
    chevron.addLine(to: CGPoint(x: 243 * s, y: 462 * s))
    chevron.addLine(to: CGPoint(x: 243 * s, y: 499 * s))
    chevron.addLine(to: CGPoint(x: 360 * s, y: 540 * s))
    chevron.addLine(to: CGPoint(x: 243 * s, y: 581 * s))
    chevron.closeSubpath()
    ctx.addPath(chevron)
    ctx.fillPath()
    ctx.fill(CGRect(x: 391 * s, y: 389 * s, width: 180 * s, height: 29 * s))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 656 * s, y: 258 * s, width: 110 * s, height: 110 * s), cornerWidth: 34 * s, cornerHeight: 34 * s, transform: nil))
    ctx.setFillColor(color(v.dot))
    ctx.fillPath()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func scaled(_ data: Data, to size: Int) -> Data? {
    guard let src = NSImage(data: data), let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let w = CGFloat(cg.width), h = CGFloat(cg.height), side = min(w, h)
    let crop = cg.cropping(to: CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)) ?? cg
    ctx.interpolationQuality = .high
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: size, height: size))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Resources")
let assets = root.appendingPathComponent("Assets.xcassets")
let fm = FileManager.default

for entry in (try? fm.contentsOfDirectory(atPath: assets.path)) ?? [] where entry.hasPrefix("AppIcon-") || entry.hasPrefix("iconpreview-") {
    try? fm.removeItem(at: assets.appendingPathComponent(entry))
}

func write(name: String, png: Data) throws {
    let set = assets.appendingPathComponent("AppIcon-\(name).appiconset")
    try fm.createDirectory(at: set, withIntermediateDirectories: true)
    try png.write(to: set.appendingPathComponent("icon.png"))
    let json = #"{"images":[{"idiom":"universal","platform":"ios","size":"1024x1024","filename":"icon.png"}],"info":{"author":"xcode","version":1}}"#
    try json.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    let prev = assets.appendingPathComponent("iconpreview-\(name).imageset")
    try fm.createDirectory(at: prev, withIntermediateDirectories: true)
    try (scaled(png, to: 180) ?? png).write(to: prev.appendingPathComponent("preview.png"))
    let pjson = #"{"images":[{"idiom":"universal","filename":"preview.png"}],"info":{"author":"xcode","version":1}}"#
    try pjson.write(to: prev.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

let base = try Data(contentsOf: assets.appendingPathComponent("AppIcon.appiconset/icon.png"))
let prev = assets.appendingPathComponent("iconpreview-Default.imageset")
try fm.createDirectory(at: prev, withIntermediateDirectories: true)
try (scaled(base, to: 180) ?? base).write(to: prev.appendingPathComponent("preview.png"))
try #"{"images":[{"idiom":"universal","filename":"preview.png"}],"info":{"author":"xcode","version":1}}"#.write(to: prev.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for v in variants { try write(name: v.name, png: render(v)) }

let custom = root.appendingPathComponent("CustomIcons")
for f in ((try? fm.contentsOfDirectory(atPath: custom.path)) ?? []).sorted() where f.lowercased().hasSuffix(".png") || f.lowercased().hasSuffix(".jpg") {
    let raw = (f as NSString).deletingPathExtension.filter { $0.isLetter || $0.isNumber }
    guard !raw.isEmpty, let data = try? Data(contentsOf: custom.appendingPathComponent(f)), let png = scaled(data, to: 1024) else { continue }
    try write(name: "Custom\(raw)", png: png)
    print("custom icon: \(f) -> Custom\(raw)")
}
print("icons written")
