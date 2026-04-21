import SwiftUI
import SweepCore

struct ContentView: View {
    @EnvironmentObject private var store: TorrentStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            TorrentListView()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.beginAddingMagnet(magnetFromPasteboard() ?? "")
                } label: {
                    Label("Add", systemImage: "plus")
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
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    store.removeSelectedTorrent()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(store.selectedTorrent == nil)
            }
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
}
