import Foundation

public protocol TorrentEngine: Sendable {
    var name: String { get }
    var unavailabilityReason: String? { get }
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
    func setFileSelection(id: Torrent.ID, includedFileIDs: [Int]) async throws -> Torrent
    func cancelPendingAdd(id: Torrent.ID) async
    func torrentFile(id: Torrent.ID) async throws -> TorrentFileSource?
}

public extension TorrentEngine {
    var unavailabilityReason: String? { nil }
    func cancelPendingAdd(id: Torrent.ID) async {}
    func torrentFile(id: Torrent.ID) async throws -> TorrentFileSource? { nil }
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

    func setFileSelection(id: Torrent.ID, includedFileIDs: [Int]) async throws -> Torrent {
        throw TorrentEngineUnsupportedOperation(message: "This engine cannot change file selection.")
    }
}

public struct UnavailableTorrentEngine: TorrentEngine {
    public let name = "rqbit unavailable"
    public let unavailabilityReason: String?

    public init(reason: String) { self.unavailabilityReason = reason }

    private var failure: TorrentEngineUnsupportedOperation {
        TorrentEngineUnsupportedOperation(message: unavailabilityReason ?? "The torrent engine is unavailable.")
    }

    public func list() async throws -> [Torrent] { throw failure }
    public func sessionStats() async throws -> TorrentSessionStats { throw failure }
    public func addTorrent(_ source: TorrentAddSource, downloadDirectory: String, startPaused: Bool) async throws -> Torrent { throw failure }
    public func pause(id: Torrent.ID) async throws -> Torrent { throw failure }
    public func resume(id: Torrent.ID) async throws -> Torrent { throw failure }
    public func remove(id: Torrent.ID, deleteData: Bool) async throws { throw failure }
}

private struct TorrentEngineUnsupportedOperation: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}
