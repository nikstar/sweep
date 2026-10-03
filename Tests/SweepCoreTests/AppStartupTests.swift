import Foundation
import Testing
@testable import SweepCore

@Suite
struct AppStartupTests {
    private static let hash = "0123456789abcdef0123456789abcdef01234567"

    @Test @MainActor
    func engineFailurePreservesSavedSessionAndStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SweepDatabase.open(at: root.appending(path: "session.sqlite"))
        let persistence = AppPersistence(database: database)
        let torrent = Torrent(name: "Saved transfer", infoHash: Self.hash,
                              magnet: "magnet:?xt=urn:btih:\(Self.hash)",
                              downloadDirectory: root.path, desiredState: .paused,
                              state: "paused", progressBytes: 512, totalBytes: 1024, uploadedBytes: 0,
                              downloadBps: 0, uploadBps: 0, error: nil)
        try await persistence.save(torrent: torrent)
        try await persistence.saveSetting(.selectedTorrentID, value: torrent.id)
        let store = TorrentStoreFactory.make(defaultDownloadDirectory: root.path,
                                             openDatabase: { database },
                                             makeEngine: { _ in throw StartupFailure.listener })
        await store.refreshNow()
        #expect(store.hasPersistence)
        #expect(store.startupError == nil)
        #expect(store.engineError == "Listener unavailable")
        #expect(store.torrents.map(\.id) == [torrent.id])
        #expect(store.selectedTorrent?.progressBytes == 512)
        #expect(store.selectedTorrent?.desiredState == .paused)
        #expect(try await persistence.loadState().torrents.map(\.id) == [torrent.id])
    }

    @Test @MainActor
    func storageFailureIsReportedSeparatelyFromEngineFailure() async {
        let store = TorrentStoreFactory.make(defaultDownloadDirectory: "/tmp",
            openDatabase: { throw StartupFailure.database },
            makeEngine: { _ in throw StartupFailure.listener })
        await store.refreshNow()
        #expect(!store.hasPersistence)
        #expect(store.startupError?.contains("Session storage is unavailable") == true)
        #expect(store.engineError == "Listener unavailable")
        #expect(store.torrents.isEmpty)
    }

    @Test
    func sandboxRelocationPreservesSubdirectoriesAndExternalLocations() {
        let oldHome = "/var/mobile/Containers/Data/Application/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let newHome = URL(filePath: "/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555")
        let date = Date(timeIntervalSince1970: 100)
        let torrent = Torrent(name: "Saved", infoHash: Self.hash,
                              downloadDirectory: "\(oldHome)/Documents/Downloads", state: "paused",
                              progressBytes: 0, totalBytes: 0, uploadedBytes: 0,
                              downloadBps: 0, uploadBps: 0, error: nil, updatedAt: date)
        let state = PersistedAppState(torrents: [torrent], selectedTorrentID: torrent.id,
                                      downloadDirectory: "\(oldHome)/Documents")
        let rebased = state.rebasingSandboxDirectories(to: newHome)
        #expect(rebased.downloadDirectory == newHome.appending(path: "Documents").path)
        #expect(rebased.torrents[0].downloadDirectory == newHome.appending(path: "Documents/Downloads").path)
        #expect(rebased.torrents[0].updatedAt == date)
        #expect(rebased.selectedTorrentID == torrent.id)
        #expect(rebased.rebasingSandboxDirectories(to: newHome).torrents == rebased.torrents)
        let external = PersistedAppState(torrents: [], selectedTorrentID: nil, downloadDirectory: "/Volumes/Downloads")
        #expect(external.rebasingSandboxDirectories(to: newHome).downloadDirectory == "/Volumes/Downloads")
    }
}

private enum StartupFailure: LocalizedError {
    case listener, database
    var errorDescription: String? { self == .listener ? "Listener unavailable" : "Database unavailable" }
}
