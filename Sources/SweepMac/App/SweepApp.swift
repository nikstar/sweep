import AppKit
import SwiftUI
import SweepCore
import SweepRQBitBridge

@main
struct SweepApp: App {
    @StateObject private var store = AppEnvironment.makeTorrentStore()
    @StateObject private var inspectorPanelPresenter = TorrentInspectorPanelPresenter()
    @State private var confirmingRemoveData = false

    var body: some Scene {
        WindowGroup {
            ContentView(confirmingRemoveData: $confirmingRemoveData)
                .environmentObject(store)
                .environmentObject(inspectorPanelPresenter)
                .frame(minWidth: 820, minHeight: 500)
                .onOpenURL { url in
                    store.beginAdding(url: url)
                }
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Torrent...") {
                    openTorrent()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Location...") {
                    store.beginAddingMagnet(magnetFromPasteboard() ?? "")
                }
                .keyboardShortcut("u", modifiers: [.command])

                Button("Add from Clipboard") {
                    addFromClipboard()
                }
                .disabled(!canAddFromClipboard)
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
                    confirmingRemoveData = true
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(store.selectedTorrent == nil)
            }
        }
        .windowToolbarStyle(.unifiedCompact)
    }

    private func revealSelectedTorrentInFinder() {
        guard let torrent = store.selectedTorrent else { return }
        TorrentFileLocation.revealInFinder(
            torrent: torrent,
            defaultDirectory: store.downloadDirectory
        )
    }

    private var canAddFromClipboard: Bool {
        magnetFromPasteboard() != nil || torrentFileURLFromPasteboard() != nil
    }

    private func openTorrent() {
        guard let url = chooseTorrentFileURL() else { return }
        store.beginAdding(url: url)
    }

    private func addFromClipboard() {
        if let magnet = magnetFromPasteboard() {
            store.beginAddingMagnet(magnet)
        } else if let url = torrentFileURLFromPasteboard() {
            store.beginAdding(url: url)
        }
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
