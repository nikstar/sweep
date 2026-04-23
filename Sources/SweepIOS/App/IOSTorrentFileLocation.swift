import Foundation
import SweepCore

struct IOSDownloadedTorrentFileSnapshot {
    let url: URL
    let exists: Bool
    let isDirectory: Bool

    var isOpenable: Bool {
        exists && !isDirectory
    }
}

struct IOSTorrentDownloadLocationSnapshot {
    let directoryURL: URL
    let expectedItemURL: URL
    let directoryExists: Bool
    let itemExists: Bool
    let itemIsDirectory: Bool
    let itemSize: UInt64?

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

    static func fileURL(
        for file: TorrentFile,
        in torrent: Torrent,
        defaultDirectory: String
    ) -> URL {
        var url = directoryURL(for: torrent, defaultDirectory: defaultDirectory)
        for component in safeRelativePathComponents(file.path) {
            url.append(path: component)
        }
        return url
    }

    static func fileSnapshot(
        for file: TorrentFile,
        in torrent: Torrent,
        defaultDirectory: String
    ) -> IOSDownloadedTorrentFileSnapshot {
        let url = fileURL(for: file, in: torrent, defaultDirectory: defaultDirectory)
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return IOSDownloadedTorrentFileSnapshot(
            url: url,
            exists: exists,
            isDirectory: isDirectory.boolValue
        )
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

    private static func safeRelativePathComponents(_ path: String) -> [String] {
        path.split { character in
            character == "/" || character == "\\"
        }
        .compactMap { component in
            let value = String(component)
            return value == "." || value == ".." ? nil : value
        }
    }
}
