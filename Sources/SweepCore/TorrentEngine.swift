import Foundation

public protocol TorrentEngine: Sendable {
    var name: String { get }
    func list() async throws -> [Torrent]
    func addMagnet(_ magnet: String, startPaused: Bool) async throws -> Torrent
    func pause(id: Torrent.ID) async throws -> Torrent
    func resume(id: Torrent.ID) async throws -> Torrent
    func remove(id: Torrent.ID, deleteData: Bool) async throws
}

public extension TorrentEngine {
    func addMagnet(_ magnet: String) async throws -> Torrent {
        try await addMagnet(magnet, startPaused: false)
    }
}
