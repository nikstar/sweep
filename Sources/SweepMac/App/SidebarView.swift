import SwiftUI
import SweepCore

struct SidebarView: View {
    @EnvironmentObject private var store: TorrentStore

    var body: some View {
        List(selection: .constant("all")) {
            Label("All", systemImage: "tray.full")
                .tag("all")
            Label("Downloading", systemImage: "arrow.down.circle")
                .tag("downloading")
            Label("Completed", systemImage: "checkmark.circle")
                .tag("completed")
        }
        .navigationTitle("Sweep")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.engineName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = store.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
