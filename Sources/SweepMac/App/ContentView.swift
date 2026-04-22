import SwiftUI
import SweepCore

struct ContentView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(TorrentInspectorPanelPresenter.self) private var inspectorPanelPresenter
    @Binding var confirmingRemoveData: Bool

    init(confirmingRemoveData: Binding<Bool> = .constant(false)) {
        self._confirmingRemoveData = confirmingRemoveData
    }

    var body: some View {
        @Bindable var store = store

        TorrentListView(confirmingRemoveData: $confirmingRemoveData)
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
                        store.removeSelectedTorrent()
                    } label: {
                        Label("Remove", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(store.selectedTorrent == nil)
                    .help("Remove")

                    Button(role: .destructive) {
                        confirmingRemoveData = true
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
        .removeTorrentDataConfirmation(isPresented: $confirmingRemoveData, store: store)
        .sheet(isPresented: $store.showingAddSheet) {
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
        .task {
            store.startPolling()
        }
    }
}
