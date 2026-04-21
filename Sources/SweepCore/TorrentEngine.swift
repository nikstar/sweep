import Foundation

public protocol TorrentEngine {
    var name: String { get }
    func list() throws -> [Torrent]
    func addMagnet(_ magnet: String) throws -> Torrent
}
