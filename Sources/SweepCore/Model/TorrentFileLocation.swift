import Foundation

public struct TorrentDownloadLocationSnapshot {
    public let directoryURL: URL
    public let expectedItemURL: URL
    public let directoryExists: Bool
    public let itemExists: Bool
    public let itemIsDirectory: Bool
    public let itemSize: UInt64?

    public var revealURL: URL {
        itemExists ? expectedItemURL : directoryURL
    }

    public var displayKind: String {
        if itemExists {
            itemIsDirectory ? "Folder" : "File"
        } else if directoryExists {
            "Not Found"
        } else {
            "Missing Folder"
        }
    }
}

public enum TorrentFileLocation {
    /// The original payload URL, including partial/preallocated files. Opening does not
    /// promise complete or playable contents; the reader decides which data it can use.
    public static func openableFileURL(for file: TorrentFile, in torrent: Torrent, defaultDirectory: String) -> URL? {
        guard !file.isPadding,
              let snapshot = fileSnapshot(for: file, in: torrent, defaultDirectory: defaultDirectory),
              snapshot.isOpenable else { return nil }
        return snapshot.url
    }

    public static func fileURL(for file: TorrentFile, in torrent: Torrent, defaultDirectory: String) -> URL? {
        let components = file.path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        guard !components.isEmpty, !file.path.hasPrefix("/"), !file.path.hasPrefix("\\"),
              !components.contains(".."), !components.contains("."),
              !components[0].hasSuffix(":") else { return nil }
        let directory = directoryURL(for: torrent, defaultDirectory: defaultDirectory).resolvingSymlinksInPath()
        let url = components.reduce(directory) { $0.appending(path: $1) }.resolvingSymlinksInPath()
        guard url.pathComponents.starts(with: directory.pathComponents),
              url.pathComponents.count > directory.pathComponents.count else { return nil }
        return url
    }

    public static func fileSnapshot(for file: TorrentFile, in torrent: Torrent, defaultDirectory: String) -> TorrentFileLocationSnapshot? {
        guard let url = fileURL(for: file, in: torrent, defaultDirectory: defaultDirectory) else { return nil }
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return TorrentFileLocationSnapshot(url: url, exists: exists, isDirectory: isDirectory.boolValue)
    }

    public static func directoryURL(for torrent: Torrent, defaultDirectory: String) -> URL {
        URL(
            filePath: torrent.downloadDirectory ?? defaultDirectory,
            directoryHint: .isDirectory
        )
    }

    public static func expectedItemURL(for torrent: Torrent, defaultDirectory: String) -> URL {
        let directory = directoryURL(for: torrent, defaultDirectory: defaultDirectory)
        let files = torrent.files.filter { !$0.isPadding }
        guard !files.isEmpty else {
            let pendingFile = TorrentFile(id: 0, path: torrent.name, length: 0, progressBytes: 0)
            return fileURL(for: pendingFile, in: torrent, defaultDirectory: defaultDirectory) ?? directory
        }
        let urls = files.compactMap { fileURL(for: $0, in: torrent, defaultDirectory: defaultDirectory) }
        guard urls.count == files.count else { return directory }
        if urls.count == 1 { return urls[0] }
        // The persisted directory is the engine's exact destination. Find the
        // shared parent of the payload paths instead of appending the display name.
        var common = urls[0].deletingLastPathComponent()
        for url in urls.dropFirst() {
            while !url.deletingLastPathComponent().pathComponents.starts(with: common.pathComponents) {
                common.deleteLastPathComponent()
            }
        }
        return common
    }

    public static func snapshot(for torrent: Torrent, defaultDirectory: String) -> TorrentDownloadLocationSnapshot {
        let directoryURL = directoryURL(for: torrent, defaultDirectory: defaultDirectory)
        let itemURL = expectedItemURL(for: torrent, defaultDirectory: defaultDirectory)
        let fileManager = FileManager.default

        var isDirectory = ObjCBool(false)
        let itemExists = fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory)
        let directoryExists = fileManager.fileExists(atPath: directoryURL.path)

        let itemSize: UInt64?
        if itemExists, !isDirectory.boolValue {
            let values = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            itemSize = UInt64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
        } else {
            itemSize = nil
        }

        return TorrentDownloadLocationSnapshot(
            directoryURL: directoryURL,
            expectedItemURL: itemURL,
            directoryExists: directoryExists,
            itemExists: itemExists,
            itemIsDirectory: isDirectory.boolValue,
            itemSize: itemSize
        )
    }

}

public struct TorrentFileLocationSnapshot {
    public let url: URL
    public let exists: Bool
    public let isDirectory: Bool
    public var isOpenable: Bool { exists && !isDirectory }
}
