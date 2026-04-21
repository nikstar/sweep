import Foundation
import SweepCore

public final class RqbitEngine: TorrentEngine {
    public let name = "rqbit"

    private let bridge: RqbitBridge
    private let client: OpaquePointer

    public static func makeDefault() -> RqbitEngine? {
        guard let bridge = RqbitBridge.loadDefault() else {
            return nil
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appending(path: "Sweep")
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        do {
            return try RqbitEngine(bridge: bridge, downloadDirectory: downloads.path)
        } catch {
            return nil
        }
    }

    init(bridge: RqbitBridge, downloadDirectory: String) throws {
        self.bridge = bridge
        self.client = try bridge.createClient(downloadDirectory: downloadDirectory)
    }

    deinit {
        bridge.destroyClient(client)
    }

    public func list() throws -> [Torrent] {
        try bridge.list(client: client)
    }

    public func addMagnet(_ magnet: String) throws -> Torrent {
        try bridge.addMagnet(client: client, magnet: magnet).torrent
    }
}
