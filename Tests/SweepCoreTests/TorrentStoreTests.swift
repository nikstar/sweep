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

    @Test
    @MainActor
    func removedTorrentIgnoresStaleRefreshResults() async throws {
        let databaseURL = FileManager.default
            .temporaryDirectory
            .appending(path: "\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let torrent = Torrent(
            name: "Ubuntu Desktop ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            magnet: "magnet:?xt=urn:btih:cab507494d02ebb1178b38f2e9d7be299c86b862",
            downloadDirectory: "/tmp/Sweep",
            state: "live",
            progressBytes: 734_003_200,
            totalBytes: 4_294_967_296,
            uploadedBytes: 86_507_520,
            downloadBps: 1_850_000,
            uploadBps: 240_000,
            error: nil
        )

        let database = try SweepDatabase.open(at: databaseURL)
        let persistence = AppPersistence(database: database)
        try await persistence.save(torrent: torrent)

        let engine = RecordingTorrentEngine(torrents: [torrent])
        let store = TorrentStore(
            engine: engine,
            persistence: persistence,
            downloadDirectory: "/tmp/Sweep",
            initialState: PersistedAppState(
                torrents: [torrent],
                selectedTorrentID: torrent.id,
                downloadDirectory: "/tmp/Sweep"
            )
        )

        _ = await waitUntil {
            await engine.listCallCount() > 0
        }

        store.selection = torrent.id
        store.removeSelectedTorrent(deleteData: true)

        let didRemove = await waitUntil {
            await engine.removeRequests() == [
                RecordedRemoveRequest(id: torrent.id, deleteData: true)
            ] && store.torrents.isEmpty
        }
        #expect(didRemove)

        await engine.enqueueListResponse([torrent])
        await store.refreshNow()

        #expect(store.torrents.isEmpty)
        #expect(try await persistence.loadState().torrents.isEmpty)
    }

    @Test
    @MainActor
    func removeTorrentWithDataDeletesPayloadFiles() async throws {
        let downloadDirectoryURL = FileManager.default
            .temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let rootFileURL = downloadDirectoryURL.appending(path: "Root File.txt")
        let nestedFileURL = downloadDirectoryURL
            .appending(path: "Linux ISO", directoryHint: .isDirectory)
            .appending(path: "disk.iso")
        let unrelatedFileURL = downloadDirectoryURL.appending(path: "Keep.txt")

        defer {
            try? FileManager.default.removeItem(at: downloadDirectoryURL)
        }

        try FileManager.default.createDirectory(
            at: nestedFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("root".utf8).write(to: rootFileURL)
        try Data("nested".utf8).write(to: nestedFileURL)
        try Data("keep".utf8).write(to: unrelatedFileURL)

        let torrent = Torrent(
            name: "Linux ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            magnet: "magnet:?xt=urn:btih:cab507494d02ebb1178b38f2e9d7be299c86b862",
            downloadDirectory: downloadDirectoryURL.path,
            state: "live",
            files: [
                TorrentFile(
                    id: 0,
                    path: "Root File.txt",
                    length: 4,
                    progressBytes: 4
                ),
                TorrentFile(
                    id: 1,
                    path: "Linux ISO/disk.iso",
                    length: 6,
                    progressBytes: 6
                )
            ],
            progressBytes: 10,
            totalBytes: 10,
            uploadedBytes: 0,
            downloadBps: 0,
            uploadBps: 0,
            error: nil
        )

        let engine = RecordingTorrentEngine(torrents: [torrent])
        let store = TorrentStore(
            engine: engine,
            downloadDirectory: downloadDirectoryURL.path,
            initialState: PersistedAppState(
                torrents: [torrent],
                selectedTorrentID: torrent.id,
                downloadDirectory: downloadDirectoryURL.path
            )
        )

        store.selection = torrent.id
        store.removeSelectedTorrent(deleteData: true)

        let didRemove = await waitUntil {
            await engine.removeRequests() == [
                RecordedRemoveRequest(id: torrent.id, deleteData: true)
            ]
                && !FileManager.default.fileExists(atPath: rootFileURL.path)
                && !FileManager.default.fileExists(atPath: nestedFileURL.path)
        }
        #expect(didRemove)
        #expect(!FileManager.default.fileExists(atPath: rootFileURL.path))
        #expect(!FileManager.default.fileExists(atPath: nestedFileURL.path))
        #expect(!FileManager.default.fileExists(atPath: nestedFileURL.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: unrelatedFileURL.path))
    }

    @Test
    @MainActor
    func partialEngineDataDeletionErrorDoesNotRestoreTorrent() async throws {
        let databaseURL = FileManager.default
            .temporaryDirectory
            .appending(path: "\(UUID().uuidString).sqlite")
        let downloadDirectoryURL = FileManager.default
            .temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let payloadURL = downloadDirectoryURL
            .appending(path: "Linux ISO", directoryHint: .isDirectory)
            .appending(path: "disk.iso")

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: downloadDirectoryURL)
        }

        try FileManager.default.createDirectory(
            at: payloadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("payload".utf8).write(to: payloadURL)

        let torrent = Torrent(
            name: "Linux ISO",
            infoHash: "cab507494d02ebb1178b38f2e9d7be299c86b862",
            magnet: "magnet:?xt=urn:btih:cab507494d02ebb1178b38f2e9d7be299c86b862",
            downloadDirectory: downloadDirectoryURL.path,
            state: "live",
            files: [
                TorrentFile(
                    id: 0,
                    path: "Linux ISO/disk.iso",
                    length: 7,
                    progressBytes: 7
                )
            ],
            progressBytes: 7,
            totalBytes: 7,
            uploadedBytes: 0,
            downloadBps: 0,
            uploadBps: 0,
            error: nil
        )

        let database = try SweepDatabase.open(at: databaseURL)
        let persistence = AppPersistence(database: database)
        try await persistence.save(torrent: torrent)

        let engine = RecordingTorrentEngine(
            torrents: [torrent],
            removeError: RecordingTorrentEngineError(
                "torrent 1 deleted, but could not delete files: could not delete all torrent payload files"
            )
        )
        let store = TorrentStore(
            engine: engine,
            persistence: persistence,
            downloadDirectory: downloadDirectoryURL.path,
            initialState: PersistedAppState(
                torrents: [torrent],
                selectedTorrentID: torrent.id,
                downloadDirectory: downloadDirectoryURL.path
            )
        )

        store.selection = torrent.id
        store.removeSelectedTorrent(deleteData: true)

        let didRemove = await waitUntil {
            await engine.removeRequests().contains(
                RecordedRemoveRequest(id: torrent.id, deleteData: true)
            )
                && store.torrents.isEmpty
                && !FileManager.default.fileExists(atPath: payloadURL.path)
        }
        #expect(didRemove)
        #expect(store.torrents.isEmpty)
        #expect(try await persistence.loadState().torrents.isEmpty)
        #expect(store.lastError?.contains("rqbit reported a file cleanup failure") == true)

        await engine.enqueueListResponse([torrent])
        await store.refreshNow()

        #expect(store.torrents.isEmpty)
        #expect(try await persistence.loadState().torrents.isEmpty)
    }
}

private struct RecordedAddRequest: Equatable, Sendable {
    let source: TorrentAddSource
    let downloadDirectory: String
    let startPaused: Bool
}

private struct RecordedRemoveRequest: Equatable, Sendable {
    let id: Torrent.ID
    let deleteData: Bool
}

private actor RecordingTorrentEngine: TorrentEngine {
    nonisolated let name = "Recording"

    private var requests: [RecordedAddRequest] = []
    private var removes: [RecordedRemoveRequest] = []
    private var torrents: [Torrent] = []
    private var queuedListResponses: [[Torrent]] = []
    private let removeError: (any Error & Sendable)?
    private var listCalls = 0

    init(torrents: [Torrent] = [], removeError: (any Error & Sendable)? = nil) {
        self.torrents = torrents
        self.removeError = removeError
    }

    func list() async throws -> [Torrent] {
        listCalls += 1
        if !queuedListResponses.isEmpty {
            return queuedListResponses.removeFirst()
        }
        return torrents
    }

    func sessionStats() async throws -> TorrentSessionStats {
        .empty
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
        removes.append(RecordedRemoveRequest(id: id, deleteData: deleteData))
        torrents.removeAll { $0.id == id }
        if let removeError {
            throw removeError
        }
    }

    func addRequests() -> [RecordedAddRequest] {
        requests
    }

    func removeRequests() -> [RecordedRemoveRequest] {
        removes
    }

    func enqueueListResponse(_ torrents: [Torrent]) {
        queuedListResponses.append(torrents)
    }

    func listCallCount() -> Int {
        listCalls
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

private struct RecordingTorrentEngineError: LocalizedError, Sendable {
    let message: String

    init(_ message: String = "Recording torrent engine error") {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

@MainActor
private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
