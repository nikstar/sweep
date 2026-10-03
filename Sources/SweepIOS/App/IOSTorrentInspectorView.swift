import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentInspectorView: View {
    @Environment(TorrentStore.self) private var store

    let torrentID: Torrent.ID

    @State private var selectedTab: IOSInspectorTab = .info
    @State private var torrentToDelete: Torrent?

    var body: some View {
        Group {
            if let torrent {
                VStack(spacing: 0) {
                    Picker("Inspector Section", selection: $selectedTab) {
                        ForEach(IOSInspectorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    ScrollView {
                        selectedContent(for: torrent)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    }
                }
                .navigationTitle(torrent.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            store.togglePause(torrent)
                        } label: {
                            Label(
                                torrent.transferActionTitle,
                                systemImage: torrent.transferActionSymbol
                            )
                        }

                        Menu {
                            Button {
                                store.refresh()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }

                            Button(role: .destructive) {
                                store.selection = torrent.id
                                store.removeSelectedTorrent()
                            } label: {
                                Label("Remove", systemImage: "xmark")
                            }

                            Button(role: .destructive) {
                                torrentToDelete = torrent
                            } label: {
                                Label("Delete Data", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Torrent Removed", systemImage: "xmark.circle")
            }
        }
        .safeAreaInset(edge: .bottom) { IOSSessionStatusBar() }
        .removeTorrentDataConfirmation(torrent: $torrentToDelete, store: store)
        .task {
            store.selection = torrentID
            store.startPolling()
        }
        .onAppear {
            store.selection = torrentID
        }
    }

    private var torrent: Torrent? {
        store.torrents.first { $0.id == torrentID }
    }

    @ViewBuilder
    private func selectedContent(for torrent: Torrent) -> some View {
        switch selectedTab {
        case .info:
            IOSTorrentInfoInspector(torrent: torrent, defaultDownloadDirectory: store.downloadDirectory)

        case .activity:
            IOSTorrentActivityInspector(torrent: torrent)

        case .trackers:
            IOSTorrentTrackersInspector(torrent: torrent)

        case .peers:
            IOSTorrentPeersInspector(torrent: torrent)

        case .files:
            IOSTorrentFilesInspector(torrent: torrent, defaultDownloadDirectory: store.downloadDirectory)

        case .options:
            IOSTorrentOptionsInspector(
                torrent: torrent,
                defaultDownloadDirectory: store.downloadDirectory,
                confirmRemoveData: { torrentToDelete = torrent }
            )
        }
    }
}

private enum IOSInspectorTab: String, CaseIterable, Identifiable {
    case info
    case activity
    case trackers
    case peers
    case files
    case options

    var id: Self { self }

    var title: String {
        switch self {
        case .info:
            "Info"
        case .activity:
            "Activity"
        case .trackers:
            "Trackers"
        case .peers:
            "Peers"
        case .files:
            "Files"
        case .options:
            "Options"
        }
    }
}
