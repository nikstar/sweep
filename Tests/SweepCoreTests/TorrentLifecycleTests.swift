import Foundation
import Testing
@testable import SweepCore

@Suite
struct TorrentLifecycleTests {
    @Test @MainActor
    func pausedFilesCanBeSelectedBeforeEngineRestoration() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let files = (0..<2).map { TorrentFile(id: $0, path: "episode\($0).mp4", length: 100, progressBytes: 0) }
        let torrent = sampleTorrent().updating(desiredState: .paused, files: files)
            .withAddSource(.torrentFile(TorrentFileSource(fileName: "cached.torrent", bytes: [1, 2, 3])))
        let engine = LifecycleEngine()
        let store = fixture.store(engine: engine, initialState: PersistedAppState(torrents: [torrent], selectedTorrentID: torrent.id, downloadDirectory: fixture.directory.path))
        await store.refreshNow()
        #expect(await engine.addCount() == 0)
        store.setFile(files[0], included: false, in: torrent)
        #expect(await eventually { !store.changingFileSelection.contains(torrent.id) })
        #expect(store.lastError == nil)
        #expect(try await fixture.persistence.loadState().torrents.first?.files.filter(\.included).map(\.id) == [1])
        store.resumeSelectedTorrent()
        #expect(await eventually { await engine.selectedFiles() == [1] })
    }

    private static let hash = "0123456789abcdef0123456789abcdef01234567"
    private static let magnet = "magnet:?xt=urn:btih:\(hash)&dn=Lifecycle%20test"

    @Test @MainActor
    func savedLibraryIsAvailableWhileTransfersWaitForAnEngine() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let saved = sampleTorrent()
        try await fixture.persistence.save(torrent: saved)
        try await fixture.persistence.saveSetting(.selectedTorrentID, value: saved.id)
        let store = TorrentStoreFactory.make(defaultDownloadDirectory: fixture.directory.path,
            openDatabase: { try SweepDatabase.open(at: fixture.directory.appending(path: "state.sqlite")) }, makeEngine: nil)

        #expect(store.selectedTorrent?.progressBytes == saved.progressBytes)
        #expect(store.selectedTorrent?.statusLabel == "Waiting")
        #expect(store.selectedTorrent?.downloadBps == 0)
        await store.refreshNow()
        #expect(store.isWaitingForEngine)
        #expect(store.lastRefreshAt == nil)
        #expect(store.pendingTorrentCount == 0)
        store.pauseSelectedTorrent()
        #expect(await eventually { try? await fixture.persistence.loadState().torrents.first?.desiredState == .paused })

        let queuedHash = String(repeating: "a", count: 40)
        let queued = await store.addTorrent(.magnet("magnet:?xt=urn:btih:\(queuedHash)"),
                                            downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(queued?.statusLabel == "Waiting")
        #expect(store.pendingTorrentCount == 0)
        let engine = LifecycleEngine()
        store.startTransfers(with: engine)
        store.startTransfers(with: engine)
        await store.refreshNow()
        #expect(await eventually { store.selectedTorrent?.state == "live" })
        #expect(await engine.addCount() == 1)
        #expect(try await engine.list().map(\.id) == [queuedHash])
        #expect(store.torrents.first { $0.id == saved.id }?.statusLabel == "Paused")
    }

    @Test @MainActor
    func immediateEngineAttachmentWaitsForLibraryLoad() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.persistence.save(torrent: sampleTorrent())
        let store = TorrentStore(engine: nil, persistence: fixture.persistence, downloadDirectory: fixture.directory.path)
        let engine = LifecycleEngine()
        store.startTransfers(with: engine)
        await store.refreshNow()
        #expect(await eventually { store.torrents.first?.state == "live" })
        #expect(await engine.addCount() == 1)
    }

    @Test
    func validatesMagnetIdentity() throws {
        #expect(try MagnetLink(Self.magnet).infoHash == Self.hash)
        #expect(try MagnetLink("magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA").infoHash == String(repeating: "0", count: 40))
        #expect(throws: (any Error).self) { try MagnetLink("magnet:?xt=urn:btih:invalid") }
        #expect(try MagnetLink("MAGNET:?xt=URN:BTIH:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA").value == "magnet:?xt=urn:btih:\(String(repeating: "0", count: 40))")
        #expect(throws: (any Error).self) {
            try MagnetLink("\(Self.magnet)&xt=urn:btih:\(String(repeating: "b", count: 40))")
        }
    }

    @Test @MainActor
    func rapidFileChoicesUseLatestSelectionAndPersistBulkChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let files = (0..<3).map { TorrentFile(id: $0, path: "file\($0).mp4", length: 100, progressBytes: 0) }
        let torrent = sampleTorrent().updating(files: files)
        let engine = LifecycleEngine(torrents: [torrent])
        let store = fixture.store(engine: engine, initialState: PersistedAppState(torrents: [torrent], selectedTorrentID: torrent.id, downloadDirectory: fixture.directory.path))
        await store.refreshNow()
        store.setFile(files[0], included: false, in: torrent)
        store.setFile(files[1], included: false, in: torrent)
        #expect(store.changingFileSelection.contains(torrent.id))
        #expect(await eventually { !store.changingFileSelection.contains(torrent.id) })
        #expect(await engine.selectedFiles() == [2])
        #expect(try await fixture.persistence.loadState().torrents.first?.files.filter(\.included).map(\.id) == [2])
        store.setFiles(includedFileIDs: [], in: torrent)
        #expect(await eventually { !store.changingFileSelection.contains(torrent.id) })
        #expect(store.lastError == "At least one file must remain selected for download.")
        #expect(await engine.selectedFiles() == [2])
        store.setFiles(includedFileIDs: [0, 1, 2], in: torrent)
        #expect(await eventually { !store.changingFileSelection.contains(torrent.id) })
        #expect(await engine.selectedFiles() == [0, 1, 2])
        #expect(store.lastError == nil)
    }

    @Test @MainActor
    func pendingMagnetIsSavedBeforeDiscoveryAndPauseCancelsIt() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine(holdMetadata: true)
        let store = fixture.store(engine: engine)
        let accepted = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(accepted?.state == "resolving")
        #expect(try await fixture.persistence.loadState().torrents.first?.magnet == Self.magnet)
        #expect(await eventually { await engine.addCount() == 1 })
        _ = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(await engine.addCount() == 1)
        store.pauseSelectedTorrent()
        #expect(await eventually { store.selectedTorrent?.state == "paused" && store.pendingTorrentCount == 0 })
        #expect(await eventually { await engine.cancelCount() == 1 })
        #expect(try await fixture.persistence.loadState().torrents.first?.desiredState == .paused)
    }

    @Test @MainActor
    func pausedPendingMagnetRestoresWithoutNetworkAndCanResume() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = fixture.store(engine: LifecycleEngine())
        _ = await original.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: true)
        #expect(await eventually { try? await fixture.persistence.loadState().selectedTorrentID == Self.hash })
        let state = try await fixture.persistence.loadState()
        let engine = LifecycleEngine(holdMetadata: true)
        let restored = fixture.store(engine: engine, initialState: state)
        await restored.refreshNow()
        #expect(await engine.addCount() == 0)
        #expect(restored.selectedTorrent?.statusLabel == "Paused")
        #expect(restored.selectedTorrent?.downloadBps == 0)
        restored.resumeSelectedTorrent()
        #expect(await eventually { await engine.addCount() == 1 })
        await engine.failMetadata()
        #expect(await eventually { restored.selectedTorrent?.error != nil })
        await restored.refreshNow()
        #expect(restored.selectedTorrent?.error == "Test metadata timeout")
        #expect(restored.canResumeSelectedTorrent)
    }

    @Test @MainActor
    func successfulPollDoesNotEraseActionOrStartupErrors() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = TorrentStore(engine: LifecycleEngine(), persistence: fixture.persistence,
                                 downloadDirectory: fixture.directory.path, initialError: "Storage recovery failed")
        store.lastError = "Action failed"
        await store.refreshNow()
        #expect(store.lastError == "Action failed")
        #expect(store.healthError == "Storage recovery failed")
        #expect(store.lastRefreshAt != nil)
    }

    @Test @MainActor
    func failedEngineDoesNotInventTorrentsOrClearItsFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.store(engine: UnavailableTorrentEngine(reason: "Listener failed"))
        await store.refreshNow()
        #expect(store.torrents.isEmpty)
        #expect(store.engineError == "Listener failed")
        #expect(store.lastRefreshAt == nil)
    }

    @Test @MainActor
    func pollFailureRemainsVisibleUntilRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine()
        let store = fixture.store(engine: engine)
        await store.refreshNow()
        let lastResponse = store.lastRefreshAt
        await engine.failNextList()
        await store.refreshNow()
        #expect(store.refreshError != nil)
        #expect(store.healthError != nil)
        #expect(store.lastRefreshAt == lastResponse)
        await store.refreshNow()
        #expect(store.refreshError == nil)
        #expect(store.lastRefreshAt != nil)
    }

    @Test @MainActor
    func stalePollCannotOverwritePause() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let torrent = sampleTorrent()
        let engine = LifecycleEngine(torrents: [torrent])
        let store = fixture.store(engine: engine, initialState: PersistedAppState(torrents: [torrent], selectedTorrentID: torrent.id, downloadDirectory: fixture.directory.path))
        await store.refreshNow()
        await engine.holdNextList()
        let refresh = Task { await store.refreshNow() }
        #expect(await eventually { await engine.hasHeldList() })
        store.pauseSelectedTorrent()
        #expect(await eventually { store.selectedTorrent?.isPausedInEngine == true })
        await engine.releaseList()
        await refresh.value
        #expect(store.selectedTorrent?.desiredState == .paused)
        #expect(store.selectedTorrent?.isPausedInEngine == true)
    }

    @Test @MainActor
    func resolvedMetadataAndFileSelectionSurviveRestoration() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine()
        let store = fixture.store(engine: engine)
        _ = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(await eventually { store.pendingTorrentCount == 0 && store.selectedTorrent?.torrentFileBytes != nil })
        #expect(await engine.lastCreateSubfolder() == true)
        let resolved = try #require(store.selectedTorrent)
        #expect(resolved.magnet == Self.magnet)
        #expect(resolved.torrentFileBytes == [1, 2, 3])
        let skipped = TorrentFile(id: 1, path: "skip.txt", length: 10, progressBytes: 0, included: false)
        let included = TorrentFile(id: 0, path: "keep.txt", length: 10, progressBytes: 0)
        try await fixture.persistence.save(torrent: resolved.updating(downloadDirectory: fixture.directory.appending(path: "Resolved Folder").path, files: [included, skipped]))
        let state = try await fixture.persistence.loadState()
        let restoredEngine = LifecycleEngine()
        let restored = fixture.store(engine: restoredEngine, initialState: state)
        #expect(await eventually { !restored.isRestoringSession && restored.pendingTorrentCount == 0 })
        #expect(await restoredEngine.firstSource()?.torrentFile?.bytes == [1, 2, 3])
        #expect(await restoredEngine.selectedFiles() == [0])
        #expect(await restoredEngine.lastCreateSubfolder() == false)
        #expect(await restoredEngine.lastDirectory() == fixture.directory.appending(path: "Resolved Folder").path)
        #expect(restored.torrents.first?.desiredState == .running)
    }

    @Test @MainActor
    func unreachableMagnetDoesNotBlockAnotherRestoration() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let first = sampleTorrent().withAddSource(.magnet(Self.magnet))
        let otherHash = String(repeating: "b", count: 40)
        let second = Torrent(name: "Other", infoHash: otherHash, magnet: "magnet:?xt=urn:btih:\(otherHash)", state: "live", progressBytes: 0, totalBytes: 0, uploadedBytes: 0, downloadBps: 0, uploadBps: 0, error: nil)
        let engine = LifecycleEngine(holdMetadata: true)
        let store = fixture.store(engine: engine, initialState: PersistedAppState(torrents: [first, second], selectedTorrentID: first.id, downloadDirectory: fixture.directory.path))
        #expect(await eventually { await engine.addCount() == 2 })
        #expect(await eventually { !store.isRestoringSession })
        #expect(store.pendingTorrentCount == 2)
        await engine.failMetadata()
        #expect(await eventually { store.pendingTorrentCount == 0 })
    }

    @Test @MainActor
    func fileCheckingNeverBecomesDownloadedProgress() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let cached = sampleTorrent().updating(desiredState: .paused, state: "paused")
        let checking = Torrent(name: "Test", infoHash: Self.hash, state: "initializing",
            progressBytes: 0, checkedBytes: 100, totalBytes: 100, uploadedBytes: 0,
            downloadBps: 0, uploadBps: 0, error: nil)
        let merged = checking.mergingCachedMetadata(from: cached)
        #expect(merged.progressBytes == 20)
        #expect(merged.checkingProgress == 1)
        try await fixture.persistence.save(torrent: merged)
        let saved = try #require(try await fixture.persistence.loadState().torrents.first)
        #expect(saved.progressBytes == 20)
        #expect(saved.checkedBytes == nil)
        // A completed check may discover missing/corrupt pieces. Accept the
        // actual verified result even when it is lower than the saved count.
        let verified = sampleTorrent().updating(progressBytes: 10).mergingCachedMetadata(from: merged)
        #expect(verified.progressBytes == 10)
        #expect(verified.checkingProgress == nil)
        #expect(verified.updating(state: "paused").checkedBytes == nil)
    }

    private func sampleTorrent() -> Torrent {
        Torrent(name: "Test", infoHash: Self.hash, magnet: Self.magnet, state: "live", progressBytes: 20, totalBytes: 100, uploadedBytes: 0, downloadBps: 123, uploadBps: 0, error: nil)
    }

    @Test @MainActor
    func discoveryDiagnosticsPreserveIntentAndStopOnPause() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine(holdMetadata: true)
        let store = fixture.store(engine: engine)
        _ = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(await eventually { await engine.addCount() == 1 })
        let tracker = TorrentTracker(id: 0, url: "http://localhost/announce", kind: "HTTP", status: "Working", lastPeerCount: 4)
        await engine.setDiscovery(TorrentDiscovery(id: Self.hash, isActive: true, elapsedSeconds: 12,
            peersFound: 4, peersTried: 3, peersActive: 1, peersFailed: 2,
            lastPeerError: "Peer disconnected during handshake", trackers: [tracker],
            retryInSeconds: 15, attempt: 2, socketsConnected: 2, handshakeFailures: 2))
        await store.refreshNow()
        #expect(store.discoveries[Self.hash]?.peersFound == 4)
        #expect(store.selectedTorrent?.state == "resolving")
        #expect(store.selectedTorrent?.desiredState == .running)
        #expect(store.selectedTorrent?.error == nil)
        #expect(store.discoveries[Self.hash]?.retryInSeconds == 15)
        #expect(TorrentDisplayFormat.statusSummary(store.selectedTorrent!, discovery: store.discoveries[Self.hash]).contains("Retry in 15s"))
        #expect(store.selectedTorrent?.trackers.first?.status == "Working")
        store.pauseSelectedTorrent()
        #expect(await eventually { await engine.cancelCount() == 1 })
        await store.refreshNow()
        #expect(store.discoveries[Self.hash]?.isActive == false)
        #expect(store.discoveries[Self.hash]?.peersActive == 0)
        #expect(store.selectedTorrent?.desiredState == .paused)
        #expect(!TorrentDisplayFormat.statusSummary(store.selectedTorrent!, discovery: store.discoveries[Self.hash]).contains("Retry in"))
    }

    @Test @MainActor
    func failedDiscoveryKeepsItsFinalEvidenceUntilRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine(holdMetadata: true)
        let store = fixture.store(engine: engine)
        _ = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(await eventually { await engine.addCount() == 1 })
        await engine.setDiscovery(TorrentDiscovery(id: Self.hash, isActive: false, elapsedSeconds: 90,
            peersFound: 5, peersTried: 5, peersActive: 0, peersFailed: 5,
            lastPeerError: "Handshake timed out", trackers: []))
        await engine.failMetadata()
        #expect(await eventually { store.pendingTorrentCount == 0 })
        await store.refreshNow()
        #expect(store.discoveries[Self.hash]?.peersFailed == 5)
        #expect(store.selectedTorrent?.error == "Test metadata timeout")
        let failed = try #require(store.selectedTorrent)
        #expect(failed.transferActionTitle == "Retry")
        store.togglePause(failed)
        #expect(await eventually { await engine.addCount() == 2 })
        #expect(store.discoveries[Self.hash] == nil)
        #expect(store.selectedTorrent?.error == nil)
        await engine.completeMetadata()
        #expect(await eventually { store.pendingTorrentCount == 0 })
        await store.refreshNow()
        #expect(store.selectedTorrent?.error == nil)
        #expect(store.selectedTorrent?.state == "live")
        #expect(store.selectedTorrent?.transferActionTitle == "Pause")
        #expect(store.discoveries[Self.hash] == nil)
        #expect(try await fixture.persistence.loadState().torrents.first?.error == nil)
    }

    @Test @MainActor
    func undoRemovalRestoresPausedEntryAndLeavesPayloadAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = TorrentFile(id: 0, path: "fixture.bin", length: 100, progressBytes: 20)
        let source = TorrentFileSource(fileName: "fixture.torrent", bytes: [1, 2, 3])
        let saved = sampleTorrent().updating(downloadDirectory: fixture.directory.path, desiredState: .paused, files: [file])
            .withAddSource(.torrentFile(source))
        let payload = fixture.directory.appending(path: file.path)
        try Data(repeating: 9, count: 20).write(to: payload)
        let store = fixture.store(engine: LifecycleEngine(), initialState: PersistedAppState(
            torrents: [saved], selectedTorrentID: saved.id, downloadDirectory: fixture.directory.path))
        let removed = try #require(await store.removeTorrent(id: saved.id))
        #expect(store.torrents.isEmpty)
        #expect(try await fixture.persistence.loadState().torrents.isEmpty)
        await store.restoreRemovedTorrent(removed)
        let row = try #require(store.selectedTorrent)
        #expect(row.id == saved.id && row.addedAt == saved.addedAt)
        #expect(row.files == [file] && row.addSource == .torrentFile(source))
        #expect(row.downloadDirectory == saved.downloadDirectory && row.progressBytes == 20)
        #expect(row.desiredState == .paused && row.state == "paused")
        #expect(try await fixture.persistence.loadState().torrents.first?.files == [file])
        #expect(try Data(contentsOf: payload) == Data(repeating: 9, count: 20))
        #expect(await store.removeTorrent(id: saved.id, deleteData: true) == nil)
        await store.restoreRemovedTorrent(removed)
        #expect(store.torrents.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: payload.path))
    }

    @Test @MainActor
    func undoRunningTransferWaitsForItsEngineAndRestoresOnlyOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let saved = sampleTorrent()
        let store = TorrentStore(engine: nil, persistence: fixture.persistence, downloadDirectory: fixture.directory.path,
                                 initialState: .init(torrents: [saved], selectedTorrentID: saved.id, downloadDirectory: fixture.directory.path))
        let removed = try #require(await store.removeTorrent(id: saved.id))
        await store.restoreRemovedTorrent(removed)
        await store.restoreRemovedTorrent(removed)
        #expect(store.torrents.count == 1)
        #expect(store.selectedTorrent?.state == "waiting")
        #expect(store.selectedTorrent?.desiredState == .running)
        let engine = LifecycleEngine()
        store.startTransfers(with: engine)
        #expect(await eventually { store.selectedTorrent?.state == "live" })
        #expect(await engine.addCount() == 1)
    }

    @Test
    func removalRequiresKnownFinishedBytes() {
        let partial = sampleTorrent()
        #expect(!partial.isDownloadFinished)
        #expect(!partial.updating(progressBytes: 0, totalBytes: 0).isDownloadFinished)
        let complete = partial.updating(progressBytes: partial.totalBytes)
        #expect(complete.isDownloadFinished)
        #expect(complete.updating(state: "paused").isDownloadFinished)
        #expect(!complete.updating(state: "initializing").isDownloadFinished)
    }

    @Test @MainActor
    func undoPendingMagnetRestartsDiscoveryAfterTheOldAddFinishes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine(holdMetadata: true, ignoresCancellation: true)
        let store = fixture.store(engine: engine)
        _ = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(await eventually { await engine.addCount() == 1 })
        let removal = Task { await store.removeTorrent(id: Self.hash) }
        #expect(await eventually { store.torrents.isEmpty })
        await engine.completeMetadata()
        let receipt = try #require(await removal.value)
        #expect(try await engine.list().isEmpty)
        await store.restoreRemovedTorrent(receipt)
        #expect(await eventually { await engine.addCount() == 2 })
        await engine.completeMetadata()
        #expect(await eventually { store.selectedTorrent?.state == "live" })
        #expect(try await engine.list().map(\.id) == [Self.hash])
        #expect(try await fixture.persistence.loadState().torrents.map(\.id) == [Self.hash])
    }

    @Test @MainActor
    func readdingDuringRemovalPreservesNewIntentAndInvalidatesOldUndo() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine(holdMetadata: true, ignoresCancellation: true)
        let store = fixture.store(engine: engine)
        _ = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(await eventually { await engine.addCount() == 1 })
        let remove = Task { await store.removeTorrent(id: Self.hash) }
        #expect(await eventually { store.torrents.isEmpty })
        let readd = Task { await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: true) }
        await engine.completeMetadata()
        let oldRemoval = try #require(await remove.value)
        _ = await readd.value
        await store.restoreRemovedTorrent(oldRemoval)
        #expect(store.selectedTorrent?.desiredState == .paused)
        #expect(try await fixture.persistence.loadState().torrents.first?.desiredState == .paused)
        #expect(await engine.addCount() == 1)
    }

    @Test @MainActor
    func removedPendingAddCannotReturnAsAGhostTorrent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let engine = LifecycleEngine(holdMetadata: true, ignoresCancellation: true)
        let store = fixture.store(engine: engine)
        _ = await store.addTorrent(.magnet(Self.magnet), downloadDirectory: fixture.directory.path, startPaused: false)
        #expect(await eventually { await engine.addCount() == 1 })
        store.removeSelectedTorrent()
        #expect(await eventually { store.torrents.isEmpty })
        await engine.completeMetadata()
        #expect(await eventually {
            await store.refreshNow()
            return try? await engine.list().isEmpty
        })
        #expect(store.torrents.isEmpty)
        #expect(try await fixture.persistence.loadState().torrents.isEmpty)
        #expect(try await engine.list().isEmpty)
    }
}

private struct Fixture {
    let directory: URL
    let persistence: AppPersistence

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        persistence = AppPersistence(database: try SweepDatabase.open(at: directory.appending(path: "state.sqlite")))
    }

    @MainActor func store(engine: any TorrentEngine, initialState: PersistedAppState? = nil) -> TorrentStore {
        TorrentStore(engine: engine, persistence: persistence, downloadDirectory: directory.path, initialState: initialState)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

private actor LifecycleEngine: TorrentEngine {
    nonisolated let name = "Test engine"
    private var torrents: [Torrent]
    private let holdMetadata: Bool
    private let ignoresCancellation: Bool
    private var sources: [TorrentAddSource] = []
    private var createSubfolderRequest: Bool?
    private var directoryRequest: String?
    func lastCreateSubfolder() -> Bool? { createSubfolderRequest }
    func lastDirectory() -> String? { directoryRequest }
    private var pending: [String: CheckedContinuation<Torrent, any Error>] = [:]
    private var cancellations = 0
    private var fileSelection: [Int] = []
    private var shouldHoldList = false
    private var shouldFailList = false
    private var heldList: CheckedContinuation<[Torrent], Never>?
    private var heldSnapshot: [Torrent] = []
    private var discovery: TorrentDiscovery?

    init(torrents: [Torrent] = [], holdMetadata: Bool = false, ignoresCancellation: Bool = false) {
        self.torrents = torrents
        self.holdMetadata = holdMetadata
        self.ignoresCancellation = ignoresCancellation
    }

    func list() async throws -> [Torrent] {
        if shouldFailList { shouldFailList = false; throw LifecycleFailure() }
        if shouldHoldList {
            shouldHoldList = false
            heldSnapshot = torrents
            return await withCheckedContinuation { heldList = $0 }
        }
        return torrents
    }
    func sessionStats() async throws -> TorrentSessionStats { .empty }
    func addTorrent(_ source: TorrentAddSource, downloadDirectory: String, startPaused: Bool, createSubfolder: Bool) async throws -> Torrent {
        sources.append(source)
        createSubfolderRequest = createSubfolder
        directoryRequest = downloadDirectory
        let id = try source.magnet.map { try MagnetLink($0).infoHash } ?? "0123456789abcdef0123456789abcdef01234567"
        if holdMetadata {
            return try await withCheckedThrowingContinuation { pending[id] = $0 }
        }
        let torrent = Torrent(name: "Resolved", infoHash: id, state: startPaused ? "paused" : "live", progressBytes: 0, totalBytes: 100, uploadedBytes: 0, downloadBps: 0, uploadBps: 0, error: nil)
        torrents.append(torrent)
        return torrent
    }
    func pause(id: String) async throws -> Torrent { update(id, state: "paused") }
    func resume(id: String) async throws -> Torrent { update(id, state: "live") }
    private func update(_ id: String, state: String) -> Torrent {
        let index = torrents.firstIndex { $0.id == id }!
        torrents[index] = torrents[index].updating(state: state)
        return torrents[index]
    }
    func remove(id: String, deleteData: Bool) async throws { torrents.removeAll { $0.id == id } }
    func setFileSelection(id: String, includedFileIDs: [Int]) async throws -> Torrent {
        fileSelection = includedFileIDs
        let index = torrents.firstIndex { $0.id == id }!
        let files = torrents[index].files.map {
            TorrentFile(id: $0.id, path: $0.path, length: $0.length, progressBytes: $0.progressBytes,
                        included: includedFileIDs.contains($0.id), isPadding: $0.isPadding)
        }
        torrents[index] = torrents[index].updating(files: files)
        return torrents[index]
    }
    func cancelPendingAdd(id: String) async {
        guard !ignoresCancellation else { return }
        if let continuation = pending.removeValue(forKey: id) {
            cancellations += 1
            continuation.resume(throwing: CancellationError())
        }
    }
    func completeMetadata() {
        let continuations = pending
        pending.removeAll()
        for (id, continuation) in continuations {
            let torrent = Torrent(name: "Late result", infoHash: id, state: "paused", progressBytes: 0, totalBytes: 100, uploadedBytes: 0, downloadBps: 0, uploadBps: 0, error: nil)
            torrents.append(torrent)
            continuation.resume(returning: torrent)
        }
    }
    func torrentFile(id: String) async throws -> TorrentFileSource? { TorrentFileSource(fileName: "cached.torrent", bytes: [1, 2, 3]) }
    func failMetadata() {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: LifecycleFailure()) }
    }
    func addCount() -> Int { sources.count }
    func cancelCount() -> Int { cancellations }
    func firstSource() -> TorrentAddSource? { sources.first }
    func selectedFiles() -> [Int] { fileSelection }
    func discoverySnapshots() async throws -> [TorrentDiscovery] { discovery.map { [$0] } ?? [] }
    func setDiscovery(_ value: TorrentDiscovery) { discovery = value }
    func holdNextList() { shouldHoldList = true }
    func failNextList() { shouldFailList = true }
    func hasHeldList() -> Bool { heldList != nil }
    func releaseList() { heldList?.resume(returning: heldSnapshot); heldList = nil }
}

private struct LifecycleFailure: LocalizedError {
    var errorDescription: String? { "Test metadata timeout" }
}

@MainActor private func eventually(_ condition: @MainActor () async -> Bool?) async -> Bool {
    for _ in 0..<100 {
        if await condition() == true { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition() == true
}
