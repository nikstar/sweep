import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/SweepMac/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.08, green: 0.35, blue: 0.72, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).fill()

    let inset = CGFloat(size) * 0.18
    let innerRect = rect.insetBy(dx: inset, dy: inset)
    NSColor(calibratedRed: 0.10, green: 0.76, blue: 0.58, alpha: 1).setStroke()
    let path = NSBezierPath()
    path.lineWidth = max(2, CGFloat(size) * 0.075)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: innerRect.minX, y: innerRect.midY))
    path.line(to: NSPoint(x: innerRect.midX, y: innerRect.minY))
    path.line(to: NSPoint(x: innerRect.maxX, y: innerRect.midY))
    path.stroke()

    NSColor.white.withAlphaComponent(0.92).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = max(2, CGFloat(size) * 0.085)
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: rect.midX, y: rect.maxY - inset * 0.95))
    arrow.line(to: NSPoint(x: rect.midX, y: rect.minY + inset * 1.35))
    arrow.move(to: NSPoint(x: rect.midX, y: rect.minY + inset * 1.35))
    arrow.line(to: NSPoint(x: rect.midX - inset * 0.72, y: rect.minY + inset * 2.08))
    arrow.move(to: NSPoint(x: rect.midX, y: rect.minY + inset * 1.35))
    arrow.line(to: NSPoint(x: rect.midX + inset * 0.72, y: rect.minY + inset * 2.08))
    arrow.stroke()

    image.unlockFocus()

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Failed to render \(size)x\(size) icon")
    }

    try pngData.write(to: outputDirectory.appending(path: "AppIcon-\(size).png"))
}
