import SwiftUI
import SweepCore

struct ContentView: View {
    @EnvironmentObject private var store: TorrentStore
    @EnvironmentObject private var inspectorPanelPresenter: TorrentInspectorPanelPresenter
    @Binding var confirmingRemoveData: Bool

    init(confirmingRemoveData: Binding<Bool> = .constant(false)) {
        self._confirmingRemoveData = confirmingRemoveData
    }

    var body: some View {
        TorrentListView(confirmingRemoveData: $confirmingRemoveData)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openTorrent()
                } label: {
                    Label("Add File", systemImage: "doc.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("Add Torrent File")

                Button {
                    store.beginAddingMagnet(magnetFromPasteboard() ?? "")
                } label: {
                    Label("Add URL", systemImage: "link.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("Add Magnet Link")

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

                Button {
                    inspectorPanelPresenter.show(store: store)
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                }
                .disabled(store.selectedTorrent == nil)
                .help("Show Inspector")

                Menu {
                    ForEach(TorrentListColumn.allCases) { column in
                        Toggle(
                            column.title,
                            isOn: Binding(
                                get: { store.isColumnVisible(column) },
                                set: { store.setColumn(column, visible: $0) }
                            )
                        )
                    }
                } label: {
                    Label("Columns", systemImage: "tablecells")
                        .labelStyle(.iconOnly)
                }
                .help("Choose Columns")
            }
        }
        .confirmationDialog(
            removeDataConfirmationTitle,
            isPresented: $confirmingRemoveData,
            titleVisibility: .visible
        ) {
            Button("Delete Torrent and Files", role: .destructive) {
                store.removeSelectedTorrent(deleteData: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded files for this torrent will be deleted from disk.")
        }
        .sheet(isPresented: $store.showingAddSheet) {
            AddTorrentView(
                source: store.pendingAddSource,
                downloadDirectory: store.downloadDirectory
            )
                .environmentObject(store)
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

    private func openTorrent() {
        guard let url = chooseTorrentFileURL() else { return }
        store.beginAdding(url: url)
    }

    private var removeDataConfirmationTitle: String {
        guard let name = store.selectedTorrent?.name else {
            return "Delete the selected torrent and its downloaded files?"
        }
        return "Delete \"\(name)\" and its downloaded files?"
    }
}
