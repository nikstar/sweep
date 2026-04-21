import AppKit
import Foundation

let defaultOutputPath = "Sources/SweepMac/Resources/Assets.xcassets/AppIcon.appiconset"
let defaultSourcePath = "\(defaultOutputPath)/AppIcon-1024.png"

let arguments = Array(CommandLine.arguments.dropFirst())
let fileManager = FileManager.default

let sourcePath: String
let outputPath: String

if let firstArgument = arguments.first {
    var isDirectory: ObjCBool = false
    let exists = fileManager.fileExists(atPath: firstArgument, isDirectory: &isDirectory)

    if exists, isDirectory.boolValue {
        sourcePath = defaultSourcePath
        outputPath = firstArgument
    } else {
        sourcePath = firstArgument
        outputPath = arguments.dropFirst().first ?? defaultOutputPath
    }
} else {
    sourcePath = defaultSourcePath
    outputPath = defaultOutputPath
}

let sourceURL = URL(fileURLWithPath: (sourcePath as NSString).expandingTildeInPath)
let outputDirectory = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Failed to load source icon at \(sourceURL.path)")
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let destinationSize = NSSize(width: size, height: size)
    let image = NSImage(size: destinationSize)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    sourceImage.draw(
        in: NSRect(origin: .zero, size: destinationSize),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
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
