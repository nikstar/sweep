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
            return snapshots.map(Torrent.init(snapshot:))
        }
    }

    public func addMagnet(_ magnet: String) async throws -> Torrent {
        try await mapRqbitError {
            let snapshot = try await engine.addMagnet(magnet: magnet)
            return Torrent(snapshot: snapshot)
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
    init(snapshot: TorrentSnapshot) {
        self.init(
            id: Int(snapshot.id),
            name: snapshot.name,
            infoHash: snapshot.infoHash,
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
