import Foundation
import SweepCore

struct IOSTorrentDownloadLocationSnapshot {
    let directoryURL: URL
    let expectedItemURL: URL
    let directoryExists: Bool
    let itemExists: Bool
    let itemIsDirectory: Bool
    let itemSize: UInt64?

    var shareURL: URL {
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

enum IOSTorrentFileLocation {
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

    static func snapshot(for torrent: Torrent, defaultDirectory: String) -> IOSTorrentDownloadLocationSnapshot {
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

        return IOSTorrentDownloadLocationSnapshot(
            directoryURL: directoryURL,
            expectedItemURL: itemURL,
            directoryExists: directoryExists,
            itemExists: itemExists,
            itemIsDirectory: isDirectory.boolValue,
            itemSize: itemSize
        )
    }
}
