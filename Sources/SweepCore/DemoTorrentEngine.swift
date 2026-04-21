import Foundation

public actor DemoTorrentEngine: TorrentEngine {
    public nonisolated let name = "Demo engine - build rust/sweep-rqbit to enable rqbit"
    private let downloadDirectory: String
    private var torrents: [Torrent] = [
        Torrent(
            engineID: 1,
            name: "Ubuntu Desktop ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            downloadDirectory: nil,
            state: "live",
            progressBytes: 734_003_200,
            totalBytes: 4_294_967_296,
            uploadedBytes: 86_507_520,
            downloadBps: 1_850_000,
            uploadBps: 240_000,
            error: nil
        )
    ]

    public init(downloadDirectory: String = "/tmp/Sweep") {
        self.downloadDirectory = downloadDirectory
        torrents = torrents.map { $0.updating(downloadDirectory: downloadDirectory) }
    }

    public func list() async throws -> [Torrent] {
        torrents
    }

    public func addMagnet(_ magnet: String, startPaused: Bool) async throws -> Torrent {
        let infoHash = infoHash(from: magnet) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let torrent = Torrent(
            engineID: (torrents.compactMap(\.engineID).max() ?? 0) + 1,
            name: magnetName(from: magnet) ?? "Magnet Torrent",
            infoHash: infoHash,
            magnet: magnet,
            downloadDirectory: downloadDirectory,
            desiredState: startPaused ? .paused : .running,
            state: startPaused ? "paused" : "live",
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

    public func pause(id: Torrent.ID) async throws -> Torrent {
        try update(id: id) { torrent in
            torrent.updating(desiredState: .paused, state: "paused", downloadBps: 0, uploadBps: 0)
        }
    }

    public func resume(id: Torrent.ID) async throws -> Torrent {
        try update(id: id) { torrent in
            torrent.updating(desiredState: .running, state: "live")
        }
    }

    public func remove(id: Torrent.ID, deleteData: Bool) async throws {
        torrents.removeAll { $0.id == id }
    }

    private func update(id: Torrent.ID, apply: (Torrent) -> Torrent) throws -> Torrent {
        guard let index = torrents.firstIndex(where: { $0.id == id }) else {
            throw DemoTorrentEngineError(message: "No torrent with info hash \(id)")
        }
        let torrent = apply(torrents[index])
        torrents[index] = torrent
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

private struct DemoTorrentEngineError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}
