import Foundation
@testable import SweepCore
import Testing

@Suite
struct AppPersistenceTests {
    @Test
    func persistsTorrentMetadataAndSettings() async throws {
        let databaseURL = FileManager.default
            .temporaryDirectory
            .appending(path: "\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let database = try SweepDatabase.open(at: databaseURL)
        let persistence = AppPersistence(database: database)
        let addedAt = Date(timeIntervalSince1970: 1_775_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_775_000_120)
        let torrent = Torrent(
            engineID: 42,
            name: "Ubuntu Desktop ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            magnet: "magnet:?xt=urn:btih:cab507494d02ebb1178b38f2e9d7be299c86b862",
            torrentFileName: "ubuntu.torrent",
            torrentFileBytes: [0x64, 0x38, 0x3a, 0x61],
            downloadDirectory: "/tmp/Sweep",
            desiredState: .paused,
            state: "live",
            files: [
                TorrentFile(
                    id: 0,
                    path: "Ubuntu Desktop ISO/ubuntu.iso",
                    length: 4_294_967_296,
                    progressBytes: 734_003_200
                )
            ],
            trackers: [
                TorrentTracker(id: 0, url: "udp://tracker.opentrackr.org:1337/announce")
            ],
            progressBytes: 734_003_200,
            totalBytes: 4_294_967_296,
            uploadedBytes: 86_507_520,
            downloadBps: 1_850_000,
            uploadBps: 240_000,
            error: nil,
            addedAt: addedAt,
            updatedAt: updatedAt
        )

        try await persistence.save(torrent: torrent)
        try await persistence.saveSetting(.downloadDirectory, value: "/tmp/Sweep")
        try await persistence.saveSetting(.selectedTorrentID, value: torrent.id)

        let state = try await persistence.loadState()
        #expect(state.torrents == [torrent])
        #expect(state.downloadDirectory == "/tmp/Sweep")
        #expect(state.selectedTorrentID == torrent.id)

        try await persistence.saveSetting(.selectedTorrentID, value: nil)
        let stateAfterSelectionClear = try await persistence.loadState()
        #expect(stateAfterSelectionClear.selectedTorrentID == nil)

        try await persistence.deleteTorrent(id: torrent.id)
        let stateAfterDelete = try await persistence.loadState()
        #expect(stateAfterDelete.torrents.isEmpty)
    }
}
