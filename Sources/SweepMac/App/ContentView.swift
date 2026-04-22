import SwiftUI
import SweepCore

struct ContentView: View {
    @EnvironmentObject private var store: TorrentStore
    @EnvironmentObject private var inspectorPanelPresenter: TorrentInspectorPanelPresenter
    @State private var confirmingRemoveData = false

    var body: some View {
        TorrentListView()
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openTorrent()
                } label: {
                    Label("Add File", systemImage: "doc.badge.plus")
                }

                Button {
                    store.beginAddingMagnet(magnetFromPasteboard() ?? "")
                } label: {
                    Label("Add URL", systemImage: "link.badge.plus")
                }

                Button {
                    store.resumeSelectedTorrent()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .disabled(!store.canResumeSelectedTorrent)

                Button {
                    store.pauseSelectedTorrent()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(!store.canPauseSelectedTorrent)

                Button {
                    store.removeSelectedTorrent()
                } label: {
                    Label("Remove", systemImage: "xmark")
                }
                .disabled(store.selectedTorrent == nil)

                Button(role: .destructive) {
                    confirmingRemoveData = true
                } label: {
                    Label("Remove Data", systemImage: "trash")
                }
                .disabled(store.selectedTorrent == nil)

                Button {
                    inspectorPanelPresenter.show(store: store)
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }

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
                }
            }
        }
        .confirmationDialog(
            "Delete the selected torrent and its downloaded files?",
            isPresented: $confirmingRemoveData,
            titleVisibility: .visible
        ) {
            Button("Delete Torrent and Files", role: .destructive) {
                store.removeSelectedTorrent(deleteData: true)
            }
            Button("Cancel", role: .cancel) {}
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
}
