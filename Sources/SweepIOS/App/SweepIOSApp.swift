import SwiftUI
import SweepCore
import SweepRQBitBridge

@main
struct SweepIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = IOSAppEnvironment.makeTorrentStore()
    @State private var backgroundDownloadService = IOSBackgroundDownloadService()

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
                .onChange(of: scenePhase) {
                    handleScenePhaseChange()
                }
        }
    }

    private func handleScenePhaseChange() {
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
            let database = try SweepDatabase.openDefault()
            let persistedState = try AppPersistence.loadState(from: database)
            let downloadDirectory = persistedState.downloadDirectory ?? fallbackDownloadDirectory
            createDownloadDirectory(at: downloadDirectory)
            let persistence = AppPersistence(database: database)
            let engine = try RqbitEngine(downloadDirectory: downloadDirectory)
            return TorrentStore(
                engine: engine,
                persistence: persistence,
                downloadDirectory: downloadDirectory,
                initialState: persistedState
            )
        } catch {
            createDownloadDirectory(at: fallbackDownloadDirectory)
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

    private static func createDownloadDirectory(at path: String) {
        try? FileManager.default.createDirectory(
            at: URL(filePath: path, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }
}
