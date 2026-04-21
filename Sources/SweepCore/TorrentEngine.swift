import Foundation

public protocol TorrentEngine: Sendable {
    var name: String { get }
    func list() async throws -> [Torrent]
    func addTorrent(
        _ source: TorrentAddSource,
        downloadDirectory: String,
        startPaused: Bool
    ) async throws -> Torrent
    func pause(id: Torrent.ID) async throws -> Torrent
    func resume(id: Torrent.ID) async throws -> Torrent
    func remove(id: Torrent.ID, deleteData: Bool) async throws
}

public extension TorrentEngine {
    func addMagnet(
        _ magnet: String,
        downloadDirectory: String,
        startPaused: Bool = false
    ) async throws -> Torrent {
        try await addTorrent(
            .magnet(magnet),
            downloadDirectory: downloadDirectory,
            startPaused: startPaused
        )
    }
}
