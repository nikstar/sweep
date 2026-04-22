import AppKit
import Foundation
import SweepCore

struct TorrentDownloadLocationSnapshot {
    let directoryURL: URL
    let expectedItemURL: URL
    let directoryExists: Bool
    let itemExists: Bool
    let itemIsDirectory: Bool
    let itemSize: UInt64?

    var revealURL: URL {
        itemExists ? expectedItemURL : directoryURL
    }

    var displayKind: String {
        if itemExists {
            itemIsDirectory ? "Folder" : "File"
        } else if directoryExists {
            "Not Found"
        } else {
            "Missing Folder"
        }
    }
}

enum TorrentFileLocation {
    static func directoryURL(for torrent: Torrent, defaultDirectory: String) -> URL {
        URL(
            filePath: torrent.downloadDirectory ?? defaultDirectory,
            directoryHint: .isDirectory
        )
    }

    static func expectedItemURL(for torrent: Torrent, defaultDirectory: String) -> URL {
        directoryURL(for: torrent, defaultDirectory: defaultDirectory)
            .appending(path: torrent.name)
    }

    static func snapshot(for torrent: Torrent, defaultDirectory: String) -> TorrentDownloadLocationSnapshot {
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

    @MainActor
    static func revealInFinder(torrent: Torrent, defaultDirectory: String) {
        let snapshot = snapshot(for: torrent, defaultDirectory: defaultDirectory)
        NSWorkspace.shared.activateFileViewerSelecting([snapshot.revealURL])
    }

    @MainActor
    static func copyExpectedPath(torrent: Torrent, defaultDirectory: String) {
        let url = expectedItemURL(for: torrent, defaultDirectory: defaultDirectory)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}
