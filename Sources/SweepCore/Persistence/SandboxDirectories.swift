import Foundation

public extension PersistedAppState {
    /// iOS may give an app a different container UUID when it is updated or restored.
    /// Only paths inside a recognized app data container are relocated; external paths stay intact.
    func rebasingSandboxDirectories(to home: URL) -> PersistedAppState {
        func rebase(_ path: String?) -> String? {
            guard let path else { return nil }
            let parts = URL(filePath: path).standardizedFileURL.pathComponents
            guard let index = parts.indices.first(where: { index in
                index + 4 < parts.count
                    && Array(parts[index..<(index + 3)]) == ["Containers", "Data", "Application"]
                    && UUID(uuidString: parts[index + 3]) != nil
                    && ["Documents", "Library", "tmp"].contains(parts[index + 4])
            }) else { return path }
            return parts.dropFirst(index + 4).reduce(home) { $0.appending(path: $1) }.path
        }
        return PersistedAppState(
            torrents: torrents.map { torrent in
                torrent.updating(downloadDirectory: rebase(torrent.downloadDirectory), updatedAt: torrent.updatedAt)
            },
            selectedTorrentID: selectedTorrentID,
            downloadDirectory: rebase(downloadDirectory)
        )
    }
}
