import AppKit
import SweepCore
import UniformTypeIdentifiers

@MainActor
func chooseTorrentFileURL() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "Open Torrent"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [torrentFileType()]
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func chooseTorrentFile() -> TorrentFileSource? {
    guard let url = chooseTorrentFileURL() else { return nil }
    return try? TorrentFileSource(contentsOf: url)
}

@MainActor
func chooseDownloadDirectory(initialPath: String) -> String? {
    let panel = NSOpenPanel()
    panel.title = "Choose Download Location"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(filePath: initialPath, directoryHint: .isDirectory)
    return panel.runModal() == .OK ? panel.url?.path : nil
}

@MainActor
func magnetFromPasteboard() -> String? {
    guard let string = NSPasteboard.general.string(forType: .string) else { return nil }
    return firstMagnet(in: string)
}

@MainActor
func torrentFileURLFromPasteboard() -> URL? {
    let objects = NSPasteboard.general.readObjects(
        forClasses: [NSURL.self],
        options: nil
    ) ?? []
    let urls = objects.compactMap { object -> URL? in
        if let url = object as? URL {
            return url
        }
        if let url = object as? NSURL {
            return url as URL
        }
        return nil
    }
    return urls.first { $0.pathExtension.lowercased() == "torrent" }
}

func firstMagnet(in string: String) -> String? {
    string
        .components(separatedBy: .whitespacesAndNewlines)
        .first { $0.lowercased().hasPrefix("magnet:") }
}

func abbreviatedPath(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

private func torrentFileType() -> UTType {
    UTType(filenameExtension: "torrent") ?? .data
}
