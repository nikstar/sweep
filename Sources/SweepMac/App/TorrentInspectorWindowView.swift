import SwiftUI
import SweepCore

struct TorrentInspectorWindowView: View {
    @EnvironmentObject private var store: TorrentStore
    @State private var selectedTab: InspectorTab = .info
    @State private var confirmingRemoveData = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector Section", selection: $selectedTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 7)

            if let torrent = store.selectedTorrent {
                ScrollView {
                    selectedContent(for: torrent)
                        .padding(.horizontal, 12)
                        .padding(.top, 3)
                        .padding(.bottom, 12)
                }
            } else {
                ContentUnavailableView("No Torrent Selected", systemImage: "info")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 430, idealWidth: 460, minHeight: 500, idealHeight: 560)
        .removeTorrentDataConfirmation(isPresented: $confirmingRemoveData, store: store)
        .task {
            store.startPolling()
        }
    }

    @ViewBuilder
    private func selectedContent(for torrent: Torrent) -> some View {
        switch selectedTab {
        case .info:
            TorrentInfoInspector(torrent: torrent, defaultDownloadDirectory: store.downloadDirectory)

        case .activity:
            TorrentActivityInspector(torrent: torrent)

        case .trackers:
            TorrentTrackersInspector(torrent: torrent)

        case .peers:
            TorrentPeersInspector(torrent: torrent)

        case .files:
            TorrentFilesInspector(torrent: torrent, defaultDownloadDirectory: store.downloadDirectory)

        case .options:
            TorrentOptionsInspector(
                torrent: torrent,
                confirmRemoveData: { confirmingRemoveData = true }
            )
            .environmentObject(store)
        }
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
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

    var systemImage: String {
        switch self {
        case .info:
            "info.circle"
        case .activity:
            "speedometer"
        case .trackers:
            "antenna.radiowaves.left.and.right"
        case .peers:
            "person.2"
        case .files:
            "folder"
        case .options:
            "slider.horizontal.3"
        }
    }
}
