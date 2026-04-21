import Foundation

public protocol TorrentEngine: Sendable {
    var name: String { get }
    func list() async throws -> [Torrent]
    func addMagnet(_ magnet: String) async throws -> Torrent
}
