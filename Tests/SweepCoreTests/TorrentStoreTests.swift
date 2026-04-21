import Foundation
@testable import SweepCore
import Testing

@Suite
struct TorrentStoreTests {
    @Test
    @MainActor
    func addTorrentPassesDestinationAndPersistsMetadata() async throws {
        let databaseURL = FileManager.default
            .temporaryDirectory
            .appending(path: "\(UUID().uuidString).sqlite")
        let downloadDirectory = FileManager.default
            .temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .path
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: downloadDirectory)
        }

        let database = try SweepDatabase.open(at: databaseURL)
        let persistence = AppPersistence(database: database)
        let engine = RecordingTorrentEngine()
        let store = TorrentStore(
            engine: engine,
            persistence: persistence,
            downloadDirectory: "/tmp/Sweep",
            initialState: PersistedAppState(
                torrents: [],
                selectedTorrentID: nil,
                downloadDirectory: "/tmp/Sweep"
            )
        )
        let source = TorrentAddSource.torrentFile(
            TorrentFileSource(fileName: "sample.torrent", bytes: [0x64, 0x31, 0x3a, 0x61])
        )

        let torrent = await store.addTorrent(
            source,
            downloadDirectory: downloadDirectory,
            startPaused: true
        )

        #expect(torrent?.downloadDirectory == downloadDirectory)
        #expect(torrent?.desiredState == .paused)
        #expect(torrent?.addSource == source)
        #expect(store.selection == torrent?.id)

        let requests = await engine.addRequests()
        #expect(requests == [
            RecordedAddRequest(
                source: source,
                downloadDirectory: downloadDirectory,
                startPaused: true
            )
        ])

        let state = try await persistence.loadState()
        #expect(state.torrents.first?.downloadDirectory == downloadDirectory)
        #expect(state.torrents.first?.desiredState == .paused)
        #expect(state.torrents.first?.addSource == source)
    }
}

private struct RecordedAddRequest: Equatable, Sendable {
    let source: TorrentAddSource
    let downloadDirectory: String
    let startPaused: Bool
}

private actor RecordingTorrentEngine: TorrentEngine {
    nonisolated let name = "Recording"

    private var requests: [RecordedAddRequest] = []
    private var torrents: [Torrent] = []

    func list() async throws -> [Torrent] {
        torrents
    }

    func addTorrent(
        _ source: TorrentAddSource,
        downloadDirectory: String,
        startPaused: Bool
    ) async throws -> Torrent {
        requests.append(
            RecordedAddRequest(
                source: source,
                downloadDirectory: downloadDirectory,
                startPaused: startPaused
            )
        )
        let torrent = Torrent(
            name: source.displayName,
            infoHash: "0123456789abcdef0123456789abcdef01234567",
            downloadDirectory: nil,
            desiredState: startPaused ? .paused : .running,
            state: startPaused ? "paused" : "live",
            progressBytes: 0,
            totalBytes: 0,
            uploadedBytes: 0,
            downloadBps: 0,
            uploadBps: 0,
            error: nil
        )
        torrents.append(torrent.withAddSource(source))
        return torrent
    }

    func pause(id: Torrent.ID) async throws -> Torrent {
        try update(id: id) { $0.updating(desiredState: .paused, state: "paused") }
    }

    func resume(id: Torrent.ID) async throws -> Torrent {
        try update(id: id) { $0.updating(desiredState: .running, state: "live") }
    }

    func remove(id: Torrent.ID, deleteData: Bool) async throws {
        torrents.removeAll { $0.id == id }
    }

    func addRequests() -> [RecordedAddRequest] {
        requests
    }

    private func update(id: Torrent.ID, apply: (Torrent) -> Torrent) throws -> Torrent {
        guard let index = torrents.firstIndex(where: { $0.id == id }) else {
            throw RecordingTorrentEngineError()
        }
        let torrent = apply(torrents[index])
        torrents[index] = torrent
        return torrent
    }
}

private struct RecordingTorrentEngineError: Error {}
