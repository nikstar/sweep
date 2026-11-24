import SwiftUI
import SweepCore

struct ContentView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(TorrentInspectorPanelPresenter.self) private var inspectorPanelPresenter
    @State private var presentedURL: URL?
    @State private var queuedURLs: [URL] = []

    var body: some View {
        @Bindable var store = store

        TorrentListView()
        .toolbar {
            ToolbarItemGroup {
                Button("Add Torrent File", systemImage: "doc.badge.plus") {
                    TorrentActions.openTorrent(in: store)
                }
                .help("Add Torrent File")

                Button("Add Magnet Link", systemImage: "link.badge.plus") {
                    TorrentActions.addLocationFromPasteboard(in: store)
                }
                .help("Add Magnet Link")

                Button("Remove from Library", systemImage: "minus") {
                    TorrentActions.remove(store.selectedTorrent, in: store)
                }
                .disabled(store.selectedTorrent == nil)
                .help("Remove from Library")
            }

            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible)
            } else {
                ToolbarItem { Spacer() }
            }

            ToolbarItemGroup {
                Button("Resume", systemImage: "play.fill") {
                    store.resumeSelectedTorrent()
                }
                .disabled(!store.canResumeSelectedTorrent)
                .help("Resume Selected Torrent")

                Button("Pause", systemImage: "pause.fill") {
                    store.pauseSelectedTorrent()
                }
                .disabled(!store.canPauseSelectedTorrent)
                .help("Pause Selected Torrent")
            }

            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }

            ToolbarItem {
                Button("Show Inspector", systemImage: "info") {
                    inspectorPanelPresenter.show(store: store)
                }
                .disabled(store.selectedTorrent == nil && !inspectorPanelPresenter.isPresented)
                .help("Show Inspector")
            }
        }
        .onOpenURL { url in
            guard url != presentedURL, !queuedURLs.contains(url) else { return }
            queuedURLs.append(url)
            presentNextURL()
        }
        .sheet(isPresented: $store.showingAddSheet, onDismiss: {
            presentedURL = nil
            presentNextURL()
        }) {
            AddTorrentView(
                source: store.pendingAddSource,
                downloadDirectory: store.downloadDirectory
            )
                .environment(store)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            store.beginAdding(url: url)
            return true
        }
        .dropDestination(for: String.self) { strings, _ in
            guard let magnet = strings.compactMap(firstMagnet(in:)).first else {
                return false
            }
            store.beginAddingMagnet(magnet)
            return true
        }
        .task(id: store.isWaitingForEngine) {
            if !store.isWaitingForEngine { store.startPolling() }
        }
    }

    private func presentNextURL() {
        guard presentedURL == nil, !store.showingAddSheet else { return }
        while !queuedURLs.isEmpty {
            let url = queuedURLs.removeFirst()
            store.beginAdding(url: url)
            if store.showingAddSheet {
                presentedURL = url
                return
            }
        }
    }
}
