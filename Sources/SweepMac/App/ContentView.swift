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
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button {
                        TorrentActions.openTorrent(in: store)
                    } label: {
                        Label("Add File", systemImage: "doc.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                    .help("Add Torrent File")

                    Button {
                        TorrentActions.addLocationFromPasteboard(in: store)
                    } label: {
                        Label("Add URL", systemImage: "link.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                    .help("Add Magnet Link")
                }
            }

            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button {
                        store.resumeSelectedTorrent()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!store.canResumeSelectedTorrent)
                    .help("Resume")

                    Button {
                        store.pauseSelectedTorrent()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!store.canPauseSelectedTorrent)
                    .help("Pause")
                }
            }

            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button {
                        TorrentActions.remove(store.selectedTorrent, in: store)
                    } label: {
                        Label("Remove", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(store.selectedTorrent == nil)
                    .help("Remove")

                    Button(role: .destructive) {
                        TorrentActions.remove(store.selectedTorrent, in: store, deleteData: true)
                    } label: {
                        Label("Remove Data", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(store.selectedTorrent == nil)
                    .help("Remove and Delete Files")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPanelPresenter.show(store: store)
                } label: {
                    Label("Inspector", systemImage: "info")
                        .labelStyle(.iconOnly)
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
