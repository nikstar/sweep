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

    public init(downloadDirectory: String) throws {
        do {
            self.engine = try SweepEngine(downloadDir: downloadDirectory)
        } catch SweepError.Message(message: let message) {
            throw RqbitEngineError(message: message)
        }
    }

    public func list() async throws -> [Torrent] {
        try await mapRqbitError {
            let snapshots = try await engine.listTorrents()
            return snapshots.map {
                Torrent(snapshot: $0, downloadDirectory: nil)
            }
        }
    }

    public func addTorrent(
        _ source: TorrentAddSource,
        downloadDirectory: String,
        startPaused: Bool
    ) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot: TorrentSnapshot
            switch source {
            case .magnet(let magnet):
                snapshot = try await engine.addMagnet(
                    magnet: magnet,
                    downloadDir: downloadDirectory,
                    startPaused: startPaused
                )

            case .torrentFile(let file):
                snapshot = try await engine.addTorrentFile(
                    torrentBytes: Data(file.bytes),
                    downloadDir: downloadDirectory,
                    startPaused: startPaused
                )
            }
            return Torrent(
                snapshot: snapshot,
                downloadDirectory: downloadDirectory,
                desiredState: startPaused ? .paused : .running
            ).withAddSource(source)
        }
    }

    public func pause(id: Torrent.ID) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.pauseTorrent(id: id)
            return Torrent(
                snapshot: snapshot,
                downloadDirectory: nil,
                desiredState: .paused
            )
        }
    }

    public func resume(id: Torrent.ID) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.resumeTorrent(id: id)
            return Torrent(
                snapshot: snapshot,
                downloadDirectory: nil,
                desiredState: .running
            )
        }
    }

    public func remove(id: Torrent.ID, deleteData: Bool) async throws {
        try await mapRqbitError {
            try await engine.removeTorrent(id: id, deleteData: deleteData)
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
        downloadDirectory: String?,
        desiredState: TorrentDesiredState? = nil
    ) {
        self.init(
            engineID: Int(snapshot.id),
            name: snapshot.name,
            infoHash: snapshot.infoHash,
            downloadDirectory: downloadDirectory,
            desiredState: desiredState ?? (snapshot.state.lowercased() == "paused" ? .paused : .running),
            state: snapshot.state,
            files: snapshot.files.map(TorrentFile.init(snapshot:)),
            trackers: snapshot.trackers.map(TorrentTracker.init(snapshot:)),
            peers: snapshot.peers.map(TorrentPeer.init(snapshot:)),
            progressBytes: snapshot.progressBytes,
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
            url: snapshot.url
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
            downloadedBytes: snapshot.downloadedBytes,
            uploadedBytes: snapshot.uploadedBytes,
            connectionAttempts: snapshot.connectionAttempts,
            connections: snapshot.connections,
            errors: snapshot.errors
        )
    }
}

private extension TorrentFile {
    init(snapshot: TorrentFileSnapshot) {
        self.init(
            id: Int(snapshot.id),
            path: snapshot.path,
            length: snapshot.length,
            progressBytes: snapshot.progressBytes,
            included: snapshot.included,
            isPadding: snapshot.isPadding
        )
    }
}
