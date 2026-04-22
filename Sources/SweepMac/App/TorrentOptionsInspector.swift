import SwiftUI
import SweepCore

struct TorrentOptionsInspector: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let confirmRemoveData: () -> Void

    var body: some View {
        InspectorPane {
            InspectorGroup("Transfer") {
                InspectorRow("Desired", value: torrent.desiredState.rawValue.capitalized)
                InspectorRow("Current", value: torrent.statusLabel)

                HStack(spacing: 8) {
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
                }
                .controlSize(.small)
            }

            InspectorGroup("Source") {
                InspectorRow("Type", value: TorrentDisplayFormat.sourceType(torrent))
                InspectorRow("Restorable", value: torrent.addSource == nil ? "No" : "Yes")
            }

            InspectorGroup("File") {
                Button {
                    TorrentActions.reveal(torrent, in: store)
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
            }

            InspectorGroup("Remove") {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        TorrentActions.remove(torrent, in: store)
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }

                    Button(role: .destructive) {
                        TorrentActions.requestRemoveData(torrent, in: store, confirm: confirmRemoveData)
                    } label: {
                        Label("Remove Data", systemImage: "trash")
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
