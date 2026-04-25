import SwiftUI
import SweepCore
import SweepRQBitBridge

@main
struct SweepIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = IOSAppEnvironment.makeTorrentStore()
    @State private var backgroundDownloadService = IOSBackgroundDownloadService()
    @State private var liveActivityService = IOSLiveActivityService()

    var body: some Scene {
        WindowGroup {
            IOSContentView()
                .environment(store)
                .onOpenURL { url in
                    store.beginAdding(url: url)
                }
                .task {
                    await backgroundDownloadService.prepareConfiguredMode()
                }
                .task {
                    liveActivityService.startMonitoring(store: store)
                    liveActivityService.refresh(store: store)
                }
                .onChange(of: store.torrents) {
                    liveActivityService.refresh(store: store)
                }
                .onChange(of: store.sessionStats) {
                    liveActivityService.refresh(store: store)
                }
                .onChange(of: scenePhase) {
                    handleScenePhaseChange()
                }
        }
    }

    private func handleScenePhaseChange() {
        liveActivityService.refresh(store: store)

        switch scenePhase {
        case .active:
            backgroundDownloadService.stop()

        case .background:
            backgroundDownloadService.startIfNeeded(store: store)

        case .inactive:
            break

        @unknown default:
            break
        }
    }
}

private enum IOSAppEnvironment {
    @MainActor
    static func makeTorrentStore() -> TorrentStore {
        let fallbackDownloadDirectory = defaultDownloadDirectory()

        do {
            prepareAppSupportDirectoryForBackupExclusion()
            let database = try SweepDatabase.openDefault()
            let persistedState = try AppPersistence.loadState(from: database)
            let downloadDirectory = persistedState.downloadDirectory ?? fallbackDownloadDirectory
            prepareDownloadDirectory(at: downloadDirectory)
            excludePersistedTorrentDirectoriesFromBackup(persistedState)
            let persistence = AppPersistence(database: database)
            let engine = try RqbitEngine(downloadDirectory: downloadDirectory)
            return TorrentStore(
                engine: engine,
                persistence: persistence,
                downloadDirectory: downloadDirectory,
                initialState: persistedState
            )
        } catch {
            prepareDownloadDirectory(at: fallbackDownloadDirectory)
            return TorrentStore(
                engine: DemoTorrentEngine(downloadDirectory: fallbackDownloadDirectory),
                downloadDirectory: fallbackDownloadDirectory,
                initialError: error.localizedDescription
            )
        }
    }

    private static func defaultDownloadDirectory() -> String {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .path
    }

    private static func prepareDownloadDirectory(at path: String) {
        try? FileManager.default.createDirectory(
            at: URL(filePath: path, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        IOSBackupExclusion.excludeItem(atPath: path)
    }

    private static func prepareAppSupportDirectoryForBackupExclusion() {
        guard let appSupportDirectory = try? FileManager.default
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "Sweep", directoryHint: .isDirectory)
        else {
            return
        }

        try? FileManager.default.createDirectory(
            at: appSupportDirectory,
            withIntermediateDirectories: true
        )
        IOSBackupExclusion.excludeItem(at: appSupportDirectory)
    }

    private static func excludePersistedTorrentDirectoriesFromBackup(_ persistedState: PersistedAppState) {
        let torrentDirectories = Set(
            persistedState.torrents.compactMap(\.downloadDirectory).filter { !$0.isEmpty }
        )

        for directory in torrentDirectories {
            IOSBackupExclusion.excludeItem(atPath: directory)
        }
    }
}
