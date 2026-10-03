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
        TorrentStoreFactory.make(
            defaultDownloadDirectory: defaultDownloadDirectory(),
            makeEngine: { try RqbitEngine(downloadDirectory: $0) }
        )
    }

    private static func defaultDownloadDirectory() -> String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appending(path: "Sweep", directoryHint: .isDirectory)
            .path
    }
}
