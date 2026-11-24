import SwiftUI
import SweepCore

@main
struct SweepApp: App {
    @State private var updates = AppUpdates()
    @State private var network = MacNetworkSession()
    @State private var inspectorPanelPresenter = TorrentInspectorPanelPresenter()
    @State private var confirmingRemoveData = false

    var body: some Scene {
        WindowGroup {
            let store = network.store
            ContentView(confirmingRemoveData: $confirmingRemoveData)
                .environment(store)
                .environment(network)
                .environment(inspectorPanelPresenter)
                .frame(minWidth: 820, minHeight: 500)
                .task { network.start() }
                .onChange(of: network.mustRelaunch) { _, lost in
                    if lost { inspectorPanelPresenter.close() }
                }
                .onOpenURL { store.beginAdding(url: $0) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updates.checkForUpdates)
                    .disabled(!updates.canCheckForUpdates)
            }
        }

        Settings {
            SettingsView(updates: updates, network: network)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                let store = network.store
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
                let store = network.store
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
