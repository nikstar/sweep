import SwiftUI
import SweepCore

struct TorrentInspectorWindowView: View {
    @Environment(TorrentStore.self) private var store
    @AppStorage("MacInspectorSelectedTab") private var selectedTab: InspectorTab = .info

    var body: some View {
        VStack(spacing: 0) {
            if let torrent = store.selectedTorrent {
                TorrentInspectorPrimaryActions(torrent: torrent, showFiles: { selectedTab = .files })
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

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
            TorrentOptionsInspector(torrent: torrent)
        }
    }
}

private struct TorrentInspectorPrimaryActions: View {
    @Environment(TorrentStore.self) private var store
    let torrent: Torrent
    let showFiles: () -> Void

    var body: some View {
        let media = TorrentMedia(files: torrent.files)
        VStack(alignment: .leading, spacing: 6) {
            Text(torrent.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(torrent.name)

            HStack(spacing: 8) {
                if let file = media.primaryVideo {
                    Button("Play", systemImage: "play.fill") {
                        TorrentActions.open(file, in: torrent, store: store)
                    }
                    .disabled(TorrentFileLocation.openableFileURL(
                        for: file, in: torrent, defaultDirectory: store.downloadDirectory
                    ) == nil)
                    .help("Open \(file.name) in your default player. Incomplete videos may need more data before they can play.")
                    .accessibilityIdentifier("torrent.play")
                } else if !media.videos.isEmpty {
                    Button(media.isSeries ? "Episodes (\(media.videos.count))" : "Videos (\(media.videos.count))",
                           systemImage: "play.rectangle.on.rectangle", action: showFiles)
                }

                Button(torrent.transferActionTitle, systemImage: torrent.transferActionSymbol) {
                    store.togglePause(torrent)
                }
                .disabled(store.engineError != nil)
                .accessibilityIdentifier("torrent.transfer")
                Spacer(minLength: 0)
            }
            .controlSize(.small)
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
