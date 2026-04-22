import Foundation

public protocol TorrentEngine: Sendable {
    var name: String { get }
    func list() async throws -> [Torrent]
    func sessionStats() async throws -> TorrentSessionStats
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
    func sessionStats() async throws -> TorrentSessionStats {
        let torrents = try await list()
        return TorrentSessionStats(
            downloadBps: torrents.reduce(0) { $0 + $1.downloadBps },
            uploadBps: torrents.reduce(0) { $0 + $1.uploadBps },
            downloadedBytes: torrents.reduce(0) { $0 + $1.progressBytes },
            uploadedBytes: torrents.reduce(0) { $0 + $1.uploadedBytes },
            livePeers: UInt32(clamping: torrents.reduce(0) { $0 + $1.peers.count }),
            seenPeers: UInt32(clamping: torrents.reduce(0) { $0 + $1.peers.count })
        )
    }

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
