import Foundation
import SweepCore

public final class RqbitEngine: TorrentEngine, @unchecked Sendable {
    public let name = "rqbit"

    private let engine: SweepEngine

    public static func makeDefault(downloadDirectory: String) -> RqbitEngine? {
        do {
            return try RqbitEngine(downloadDirectory: downloadDirectory)
        } catch {
            return nil
        }
    }

    public init(downloadDirectory: String, stateDirectory: String? = nil, bindInterface: String? = nil) throws {
        do {
            let stateDirectory = try stateDirectory ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appending(path: "Sweep/Network", directoryHint: .isDirectory).path
            self.engine = try SweepEngine(downloadDir: downloadDirectory, stateDir: stateDirectory, bindInterface: bindInterface)
        } catch SweepError.Message(message: let message) {
            throw RqbitEngineError(message: message)
        }
    }

    public func cancelNetwork() { engine.cancelNetwork() }

    public func list() async throws -> [Torrent] {
        try await mapRqbitError {
            let snapshots = try await engine.listTorrents()
            return snapshots.map {
                Torrent(snapshot: $0)
            }
        }
    }

    public func sessionStats() async throws -> TorrentSessionStats {
        try await mapRqbitError {
            TorrentSessionStats(snapshot: try await engine.sessionSnapshot())
        }
    }

    public func addTorrent(
        _ source: TorrentAddSource,
        downloadDirectory: String,
        startPaused: Bool,
        createSubfolder: Bool
    ) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot: TorrentSnapshot
            switch source {
            case .magnet(let magnet):
                snapshot = try await engine.addMagnet(
                    magnet: magnet,
                    downloadDir: downloadDirectory,
                    startPaused: startPaused,
                    createSubfolder: createSubfolder
                )

            case .torrentFile(let file):
                snapshot = try await engine.addTorrentFile(
                    torrentBytes: Data(file.bytes),
                    downloadDir: downloadDirectory,
                    startPaused: startPaused,
                    createSubfolder: createSubfolder
                )
            }
            return Torrent(
                snapshot: snapshot,
                desiredState: startPaused ? .paused : .running
            ).withAddSource(source)
        }
    }

    public func pause(id: Torrent.ID) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.pauseTorrent(id: id)
            return Torrent(
                snapshot: snapshot,
                desiredState: .paused
            )
        }
    }

    public func resume(id: Torrent.ID) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.resumeTorrent(id: id)
            return Torrent(
                snapshot: snapshot,
                desiredState: .running
            )
        }
    }

    public func remove(id: Torrent.ID, deleteData: Bool) async throws {
        try await mapRqbitError {
            try await engine.removeTorrent(id: id, deleteData: deleteData)
        }
    }

    public func setFileSelection(id: Torrent.ID, includedFileIDs: [Int]) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.updateOnlyFiles(
                id: id,
                fileIds: includedFileIDs.map(UInt64.init)
            )
            return Torrent(snapshot: snapshot)
        }
    }

    public func cancelPendingAdd(id: Torrent.ID) async {
        engine.cancelPendingAdd(id: id)
    }

    public func torrentFile(id: Torrent.ID) async throws -> TorrentFileSource? {
        try await mapRqbitError {
            TorrentFileSource(fileName: "\(id).torrent", bytes: Array(try engine.torrentFile(id: id)))
        }
    }

    public func discoverySnapshots() async throws -> [TorrentDiscovery] {
        engine.discoverySnapshots().map {
            TorrentDiscovery(
                id: $0.infoHash, isActive: $0.isActive, elapsedSeconds: $0.elapsedSeconds,
                peersFound: $0.peersFound, peersTried: $0.peersTried,
                peersActive: $0.peersActive, peersFailed: $0.peersFailed,
                lastPeerError: $0.lastPeerError, trackers: $0.trackers.map(TorrentTracker.init(snapshot:)),
                retryInSeconds: $0.retryInSeconds,
                attempt: $0.attempt,
                socketsConnected: $0.socketsConnected,
                handshakesCompleted: $0.handshakesCompleted,
                metadataPeers: $0.metadataPeers,
                metadataBlocks: $0.metadataBlocks,
                connectFailures: $0.connectFailures,
                handshakeFailures: $0.handshakeFailures,
                metadataFailures: $0.metadataFailures,
                trackerCandidates: $0.trackerCandidates,
                dhtCandidates: $0.dhtCandidates,
                pexCandidates: $0.pexCandidates,
                otherCandidates: $0.otherCandidates
            )
        }
    }
}

private struct RqbitEngineError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

private func mapRqbitError<T>(_ operation: () async throws -> T) async throws -> T {
    do {
        return try await operation()
    } catch SweepError.Message(message: let message) {
        throw RqbitEngineError(message: message)
    }
}

private extension Torrent {
    init(
        snapshot: TorrentSnapshot,
        desiredState: TorrentDesiredState? = nil
    ) {
        self.init(
            engineID: Int(snapshot.id),
            name: snapshot.name,
            infoHash: snapshot.infoHash,
            downloadDirectory: snapshot.downloadDirectory,
            desiredState: desiredState ?? (snapshot.state.lowercased() == "paused" ? .paused : .running),
            state: snapshot.state,
            files: snapshot.files.map(TorrentFile.init(snapshot:)),
            trackers: snapshot.trackers.map(TorrentTracker.init(snapshot:)),
            peers: snapshot.peers.map(TorrentPeer.init(snapshot:)),
            pieceRuns: snapshot.pieceRuns.map(TorrentPieceRun.init(snapshot:)),
            progressBytes: snapshot.progressBytes,
            checkedBytes: snapshot.checkedBytes,
            totalBytes: snapshot.totalBytes,
            uploadedBytes: snapshot.uploadedBytes,
            downloadBps: snapshot.downloadBps,
            uploadBps: snapshot.uploadBps,
            error: snapshot.error
        )
    }
}

private extension TorrentTracker {
    init(snapshot: TorrentTrackerSnapshot) {
        self.init(
            id: Int(snapshot.id),
            url: snapshot.url,
            kind: snapshot.kind,
            scrapeURL: snapshot.scrapeUrl,
            status: snapshot.status,
            lastError: snapshot.lastError,
            lastAnnounceAt: date(unixSeconds: snapshot.lastAnnounceUnixSeconds),
            nextAnnounceAt: date(unixSeconds: snapshot.nextAnnounceUnixSeconds),
            seeders: snapshot.seeders,
            leechers: snapshot.leechers,
            downloads: snapshot.downloads,
            lastPeerCount: snapshot.lastPeerCount
        )
    }
}

private extension TorrentPieceRun {
    init(snapshot: TorrentPieceRunSnapshot) {
        self.init(
            id: Int(snapshot.id),
            state: TorrentPieceState(rawValue: snapshot.state) ?? .unknown,
            pieceCount: snapshot.pieceCount,
            byteCount: snapshot.byteCount
        )
    }
}

private extension TorrentPeer {
    init(snapshot: TorrentPeerSnapshot) {
        self.init(
            id: snapshot.id,
            address: snapshot.address,
            state: snapshot.state,
            connectionKind: snapshot.connectionKind,
            peerID: snapshot.peerId,
            client: snapshot.client,
            featureFlags: snapshot.featureFlags,
            countryCode: snapshot.countryCode,
            availability: snapshot.availability,
            availablePieces: snapshot.availablePieces,
            downloadedBytes: snapshot.downloadedBytes,
            uploadedBytes: snapshot.uploadedBytes,
            downloadBps: snapshot.downloadBps,
            uploadBps: snapshot.uploadBps,
            connectionAttempts: snapshot.connectionAttempts,
            connections: snapshot.connections,
            errors: snapshot.errors
        )
    }
}

private func date(unixSeconds: UInt64?) -> Date? {
    unixSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
}

private extension TorrentFile {
    init(snapshot: TorrentFileSnapshot) {
        self.init(
            id: Int(snapshot.id),
            path: snapshot.path,
            length: snapshot.length,
            progressBytes: snapshot.progressBytes,
            progressRuns: snapshot.progressRuns.map(TorrentPieceRun.init(snapshot:)),
            included: snapshot.included,
            isPadding: snapshot.isPadding,
            priority: snapshot.priority
        )
    }
}

private extension TorrentSessionStats {
    init(snapshot: TorrentSessionSnapshot) {
        self.init(
            downloadBps: snapshot.downloadBps,
            uploadBps: snapshot.uploadBps,
            downloadedBytes: snapshot.downloadedBytes,
            uploadedBytes: snapshot.uploadedBytes,
            livePeers: snapshot.livePeers,
            connectingPeers: snapshot.connectingPeers,
            queuedPeers: snapshot.queuedPeers,
            seenPeers: snapshot.seenPeers,
            uptimeSeconds: snapshot.uptimeSeconds,
            network: TorrentNetworkStats(
                dhtNodesV4: snapshot.network.dhtNodesV4,
                dhtNodesV6: snapshot.network.dhtNodesV6,
                dhtOutstanding: snapshot.network.dhtOutstanding,
                transports: snapshot.network.transports.map {
                    TorrentTransportStats(name: $0.name, attempts: $0.attempts, connected: $0.connected, failed: $0.failed)
                },
                liveTCP: snapshot.network.liveTcp,
                liveUTP: snapshot.network.liveUtp,
                dhtQueries: snapshot.network.dhtQueries,
                dhtResponses: snapshot.network.dhtResponses,
                dhtTimeouts: snapshot.network.dhtTimeouts,
                dhtLastResponseAgeSeconds: snapshot.network.dhtLastResponseAgeSeconds,
                dhtBootstrap: snapshot.network.dhtBootstrap.map {
                    DHTBootstrapStats(address: $0.address, resolvedAddresses: $0.resolvedAddresses,
                                      attempts: $0.attempts, lastError: $0.lastError)
                },
                dhtPersistenceError: snapshot.network.dhtPersistenceError
            )
        )
    }
}
