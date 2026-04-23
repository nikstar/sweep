import SwiftUI
import SweepCore
import SweepRQBitBridge

@main
struct SweepIOSApp: App {
    @State private var store = IOSAppEnvironment.makeTorrentStore()

    var body: some Scene {
        WindowGroup {
            IOSContentView()
                .environment(store)
                .onOpenURL { url in
                    store.beginAdding(url: url)
                }
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
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "SweepDownloads", directoryHint: .isDirectory)
            .path
    }

    private static func createDownloadDirectory(at path: String) {
        try? FileManager.default.createDirectory(
            at: URL(filePath: path, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }
}
