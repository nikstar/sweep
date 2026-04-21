import AppKit
import SwiftUI
import SweepCore
import SweepRQBitBridge

@main
struct SweepApp: App {
    @StateObject private var store = AppEnvironment.makeTorrentStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 500)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView(
                engineName: store.engineName,
                downloadDirectory: store.downloadDirectory
            )
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Magnet Link...") {
                    store.showingAddSheet = true
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("Transfers") {
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
                    revealSelectedTorrentInFinder()
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
                    store.removeSelectedTorrent(deleteData: true)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(store.selectedTorrent == nil)
            }

            SidebarCommands()
        }
    }

    private func revealSelectedTorrentInFinder() {
        guard let torrent = store.selectedTorrent else { return }
        let directory = torrent.downloadDirectory ?? store.downloadDirectory
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(filePath: directory, directoryHint: .isDirectory)
        ])
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
