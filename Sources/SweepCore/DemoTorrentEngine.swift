import Foundation

public actor DemoTorrentEngine: TorrentEngine {
    public nonisolated let name = "Demo engine - build rust/sweep-rqbit to enable rqbit"
    private var torrents: [Torrent] = [
        Torrent(
            id: 1,
            name: "Ubuntu Desktop ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            state: "live",
            progressBytes: 734_003_200,
            totalBytes: 4_294_967_296,
            uploadedBytes: 86_507_520,
            downloadBps: 1_850_000,
            uploadBps: 240_000,
            error: nil
        )
    ]

    public init() {}

    public func list() async throws -> [Torrent] {
        torrents
    }

    public func addMagnet(_ magnet: String) async throws -> Torrent {
        let torrent = Torrent(
            id: (torrents.map(\.id).max() ?? 0) + 1,
            name: magnetName(from: magnet) ?? "Magnet Torrent",
            infoHash: infoHash(from: magnet) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            state: "paused",
            progressBytes: 0,
            totalBytes: 0,
            uploadedBytes: 0,
            downloadBps: 0,
            uploadBps: 0,
            error: nil
        )
        torrents.append(torrent)
        return torrent
    }

    private func infoHash(from magnet: String) -> String? {
        URLComponents(string: magnet)?
            .queryItems?
            .first { $0.name == "xt" }?
            .value?
            .split(separator: ":")
            .last
            .map(String.init)
    }

    private func magnetName(from magnet: String) -> String? {
        URLComponents(string: magnet)?
            .queryItems?
            .first { $0.name == "dn" }?
            .value
    }
}
