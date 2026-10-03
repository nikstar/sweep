import Foundation

public struct TorrentTransportStats: Hashable, Codable, Sendable {
    public let name: String
    public let attempts: UInt64
    public let connected: UInt64
    public let failed: UInt64

    public init(name: String, attempts: UInt64, connected: UInt64, failed: UInt64) {
        self.name = name
        self.attempts = attempts
        self.connected = connected
        self.failed = failed
    }
}

/// Cumulative transport counters for this engine session. A connected socket
/// does not imply a successful BitTorrent handshake or payload transfer.
public struct TorrentNetworkStats: Hashable, Codable, Sendable {
    public let dhtNodesV4: UInt64?
    public let dhtNodesV6: UInt64?
    public let dhtOutstanding: UInt64?
    public let transports: [TorrentTransportStats]
    public let liveTCP: UInt32
    public let liveUTP: UInt32

    public init(dhtNodesV4: UInt64?, dhtNodesV6: UInt64?, dhtOutstanding: UInt64?,
                transports: [TorrentTransportStats], liveTCP: UInt32, liveUTP: UInt32) {
        self.dhtNodesV4 = dhtNodesV4
        self.dhtNodesV6 = dhtNodesV6
        self.dhtOutstanding = dhtOutstanding
        self.transports = transports
        self.liveTCP = liveTCP
        self.liveUTP = liveUTP
    }
}

/// Session-only diagnostics; these are not payload peer counts or durable state.
public struct TorrentDiscovery: Sendable, Equatable {
    public let id: Torrent.ID
    public var isActive: Bool
    public let elapsedSeconds: UInt64
    public let peersFound: UInt64
    public let peersTried: UInt64
    public var peersActive: UInt64
    public let peersFailed: UInt64
    public let lastPeerError: String?
    public let trackers: [TorrentTracker]

    public init(id: Torrent.ID, isActive: Bool, elapsedSeconds: UInt64, peersFound: UInt64,
                peersTried: UInt64, peersActive: UInt64, peersFailed: UInt64,
                lastPeerError: String?, trackers: [TorrentTracker]) {
        self.id = id
        self.isActive = isActive
        self.elapsedSeconds = elapsedSeconds
        self.peersFound = peersFound
        self.peersTried = peersTried
        self.peersActive = peersActive
        self.peersFailed = peersFailed
        self.lastPeerError = lastPeerError
        self.trackers = trackers
    }
}

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
    func discoverySnapshots() async throws -> [TorrentDiscovery]
}

public extension TorrentEngine {
    var unavailabilityReason: String? { nil }
    func cancelPendingAdd(id: Torrent.ID) async {}
    func torrentFile(id: Torrent.ID) async throws -> TorrentFileSource? { nil }
    func discoverySnapshots() async throws -> [TorrentDiscovery] { [] }
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
