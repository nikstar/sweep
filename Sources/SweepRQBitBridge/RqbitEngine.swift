import Foundation
import SweepCore

public final class RqbitEngine: TorrentEngine, @unchecked Sendable {
    public let name = "rqbit"

    private let engine: SweepEngine
    private let downloadDirectory: String

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
            self.downloadDirectory = downloadDirectory
        } catch SweepError.Message(message: let message) {
            throw RqbitEngineError(message: message)
        }
    }

    public func list() async throws -> [Torrent] {
        try await mapRqbitError {
            let snapshots = try await engine.listTorrents()
            return snapshots.map {
                Torrent(snapshot: $0, downloadDirectory: downloadDirectory)
            }
        }
    }

    public func addMagnet(_ magnet: String) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.addMagnet(magnet: magnet, startPaused: false)
            return Torrent(snapshot: snapshot, downloadDirectory: downloadDirectory)
        }
    }

    public func addMagnet(_ magnet: String, startPaused: Bool) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.addMagnet(magnet: magnet, startPaused: startPaused)
            return Torrent(
                snapshot: snapshot,
                downloadDirectory: downloadDirectory,
                desiredState: startPaused ? .paused : .running
            )
        }
    }

    public func pause(id: Torrent.ID) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.pauseTorrent(id: id)
            return Torrent(
                snapshot: snapshot,
                downloadDirectory: downloadDirectory,
                desiredState: .paused
            )
        }
    }

    public func resume(id: Torrent.ID) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.resumeTorrent(id: id)
            return Torrent(
                snapshot: snapshot,
                downloadDirectory: downloadDirectory,
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
        downloadDirectory: String,
        desiredState: TorrentDesiredState? = nil
    ) {
        self.init(
            engineID: Int(snapshot.id),
            name: snapshot.name,
            infoHash: snapshot.infoHash,
            downloadDirectory: downloadDirectory,
            desiredState: desiredState ?? (snapshot.state.lowercased() == "paused" ? .paused : .running),
            state: snapshot.state,
            progressBytes: snapshot.progressBytes,
            totalBytes: snapshot.totalBytes,
            uploadedBytes: snapshot.uploadedBytes,
            downloadBps: snapshot.downloadBps,
            uploadBps: snapshot.uploadBps,
            error: snapshot.error
        )
    }
}
