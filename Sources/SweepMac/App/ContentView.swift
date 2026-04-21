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
                    store.showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $store.showingAddSheet) {
            AddTorrentView()
                .environmentObject(store)
        }
        .task {
            store.startPolling()
        }
    }
}
