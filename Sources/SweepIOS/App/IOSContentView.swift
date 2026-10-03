import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SweepCore
import SweepUI

struct IOSContentView: View {
    @Environment(TorrentStore.self) private var store

    @State private var isImportingTorrent = false
    @State private var torrentToDelete: Torrent?

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Group {
                if store.torrents.isEmpty {
                    ContentUnavailableView {
                        Label("No Torrents", systemImage: "tray")
                    } actions: {
                        Button {
                            isImportingTorrent = true
                        } label: {
                            Label("Add File", systemImage: "doc.badge.plus")
                        }

                        Button {
                            store.beginAddingMagnet("")
                        } label: {
                            Label("Add URL", systemImage: "link.badge.plus")
                        }
                    }
                } else {
                    List {
                        ForEach(store.torrents) { torrent in
                            NavigationLink {
                                IOSTorrentInspectorView(torrentID: torrent.id)
                                    .environment(store)
                            } label: {
                                IOSTorrentRow(torrent: torrent)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.togglePause(torrent)
                                } label: {
                                    Label(
                                        torrent.transferActionTitle,
                                        systemImage: torrent.transferActionSymbol
                                    )
                                }
                                .tint(torrent.canResume ? .green : .orange)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    store.removeSelectedTorrent()
                                } label: {
                                    Label("Remove", systemImage: "xmark")
                                }

                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    torrentToDelete = torrent
                                } label: {
                                    Label("Delete Data", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    store.togglePause(torrent)
                                } label: {
                                    Label(
                                        torrent.transferActionTitle,
                                        systemImage: torrent.transferActionSymbol
                                    )
                                }

                                Button {
                                    store.selection = torrent.id
                                    store.refresh()
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    store.removeSelectedTorrent()
                                } label: {
                                    Label("Remove", systemImage: "xmark")
                                }

                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    torrentToDelete = torrent
                                } label: {
                                    Label("Delete Data", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await store.refreshNow()
                    }
                }
            }
            .navigationTitle("Sweep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isImportingTorrent = true
                        } label: {
                            Label("Add File", systemImage: "doc.badge.plus")
                        }

                        Button {
                            store.beginAddingMagnet("")
                        } label: {
                            Label("Add URL", systemImage: "link.badge.plus")
                        }

                        Button {
                            addFromClipboard()
                        } label: {
                            Label("Add from Clipboard", systemImage: "doc.on.clipboard")
                        }

                        Divider()

                        Button {
                            store.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                IOSSessionStatusBar()
                    .environment(store)
            }
            .fileImporter(
                isPresented: $isImportingTorrent,
                allowedContentTypes: [torrentContentType],
                allowsMultipleSelection: false,
                onCompletion: importTorrentFile
            )
            .sheet(isPresented: $store.showingAddSheet) {
                IOSAddTorrentSheet(
                    source: store.pendingAddSource,
                    downloadDirectory: store.downloadDirectory
                )
                .environment(store)
            }
            .removeTorrentDataConfirmation(torrent: $torrentToDelete, store: store)
            .task {
                store.startPolling()
            }
        }
    }

    private var torrentContentType: UTType {
        UTType(importedAs: "org.bittorrent.torrent")
    }

    private func importTorrentFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            store.beginAddingTorrentFile(at: url)
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func addFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.lowercased().hasPrefix("magnet:")
        else {
            store.lastError = "Clipboard does not contain a magnet link."
            return
        }
        store.beginAddingMagnet(text)
    }

}

extension View {
    func removeTorrentDataConfirmation(
        torrent: Binding<Torrent?>,
        store: TorrentStore
    ) -> some View {
        confirmationDialog(
            removeTorrentDataConfirmationTitle(for: torrent.wrappedValue),
            isPresented: Binding(
                get: { torrent.wrappedValue != nil },
                set: { if !$0 { torrent.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: torrent.wrappedValue
        ) { target in
            Button("Delete Torrent and Files", role: .destructive) {
                store.selection = target.id
                store.removeSelectedTorrent(deleteData: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Downloaded files for this torrent will be deleted from this device.")
        }
    }

    private func removeTorrentDataConfirmationTitle(for torrent: Torrent?) -> String {
        guard let name = torrent?.name else {
            return "Delete the selected torrent and its downloaded files?"
        }
        return "Delete \"\(name)\" and its downloaded files?"
    }
}
