import SwiftUI
import SweepCore
import SweepRQBitBridge

@main
struct SweepApp: App {
    @State private var store = AppEnvironment.makeTorrentStore()
    @State private var inspectorPanelPresenter = TorrentInspectorPanelPresenter()
    @State private var confirmingRemoveData = false

    var body: some Scene {
        WindowGroup {
            ContentView(confirmingRemoveData: $confirmingRemoveData)
                .environment(store)
                .environment(inspectorPanelPresenter)
                .frame(minWidth: 820, minHeight: 500)
                .onOpenURL { url in
                    store.beginAdding(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Torrent...") {
                    TorrentActions.openTorrent(in: store)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Location...") {
                    TorrentActions.addLocationFromPasteboard(in: store)
                }
                .keyboardShortcut("u", modifiers: [.command])

                Button("Add from Clipboard") {
                    TorrentActions.addFromClipboard(in: store)
                }
                .disabled(!TorrentActions.canAddFromClipboard)
            }

            CommandMenu("Transfers") {
                Button("Show Inspector") {
                    inspectorPanelPresenter.show(store: store)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Divider()

                Button("Resume") {
                    store.resumeSelectedTorrent()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!store.canResumeSelectedTorrent)

                Button("Pause") {
                    store.pauseSelectedTorrent()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!store.canPauseSelectedTorrent)

                Button("Refresh") {
                    store.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Reveal in Finder") {
                    TorrentActions.revealSelectedTorrent(in: store)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.selectedTorrent == nil)

                Divider()

                Button("Remove") {
                    store.removeSelectedTorrent()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(store.selectedTorrent == nil)

                Button("Remove and Delete Data") {
                    confirmingRemoveData = true
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(store.selectedTorrent == nil)
            }
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}

private enum AppEnvironment {
    @MainActor
    static func makeTorrentStore() -> TorrentStore {
        let fallbackDownloadDirectory = defaultDownloadDirectory()

        do {
            let database = try SweepDatabase.openDefault()
            let persistedState = try AppPersistence.loadState(from: database)
            let downloadDirectory = persistedState.downloadDirectory ?? fallbackDownloadDirectory
            createDownloadDirectory(at: downloadDirectory)
            let persistence = AppPersistence(database: database)
            let engine = makeTorrentEngine(downloadDirectory: downloadDirectory)
            return TorrentStore(
                engine: engine,
                persistence: persistence,
                downloadDirectory: downloadDirectory,
                initialState: persistedState
            )
        } catch {
            createDownloadDirectory(at: fallbackDownloadDirectory)
            return TorrentStore(
                engine: makeTorrentEngine(downloadDirectory: fallbackDownloadDirectory),
                downloadDirectory: fallbackDownloadDirectory,
                initialError: error.localizedDescription
            )
        }
    }

    private static func makeTorrentEngine(downloadDirectory: String) -> TorrentEngine {
        RqbitEngine.makeDefault(downloadDirectory: downloadDirectory) ?? DemoTorrentEngine(downloadDirectory: downloadDirectory)
    }

    private static func defaultDownloadDirectory() -> String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appending(path: "Sweep", directoryHint: .isDirectory)
            .path
    }

    private static func createDownloadDirectory(at path: String) {
        try? FileManager.default.createDirectory(
            at: URL(filePath: path, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }
}
