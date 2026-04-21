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
        let torrent = Torrent(
            id: 42,
            name: "Ubuntu Desktop ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            magnet: "magnet:?xt=urn:btih:cab507494d02ebb1178b38f2e9d7be299c86b862",
            state: "live",
            progressBytes: 734_003_200,
            totalBytes: 4_294_967_296,
            uploadedBytes: 86_507_520,
            downloadBps: 1_850_000,
            uploadBps: 240_000,
            error: nil
        )

        try await persistence.save(torrent: torrent)
        try await persistence.saveSetting(.downloadDirectory, value: "/tmp/Sweep")
        try await persistence.saveSetting(.selectedTorrentID, value: "42")

        let state = try await persistence.loadState()
        #expect(state.torrents == [torrent])
        #expect(state.downloadDirectory == "/tmp/Sweep")
        #expect(state.selectedTorrentID == 42)

        try await persistence.saveSetting(.selectedTorrentID, value: nil)
        let stateAfterSelectionClear = try await persistence.loadState()
        #expect(stateAfterSelectionClear.selectedTorrentID == nil)
    }
}
