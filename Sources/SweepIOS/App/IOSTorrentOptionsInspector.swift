import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentOptionsInspector: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let defaultDownloadDirectory: String
    let confirmRemoveData: () -> Void

    var body: some View {
        let snapshot = TorrentFileLocation.snapshot(
            for: torrent,
            defaultDirectory: defaultDownloadDirectory
        )

        IOSInspectorPane {
            IOSInspectorGroup("Transfer") {
                IOSInspectorRow("Desired", value: torrent.desiredState.rawValue.capitalized)
                IOSInspectorRow("Current", value: torrent.statusLabel)

                HStack(spacing: 8) {
                    Button {
                        store.selection = torrent.id
                        store.resumeSelectedTorrent()
                    } label: {
                        Label(torrent.error == nil ? "Resume" : "Retry", systemImage: torrent.error == nil ? "play.fill" : "arrow.clockwise")
                    }
                    .disabled(!torrent.canResume || store.engineError != nil)

                    Button {
                        store.selection = torrent.id
                        store.pauseSelectedTorrent()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .disabled(torrent.desiredState != .running || store.engineError != nil)

                    Button {
                        store.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            IOSInspectorGroup("Source") {
                IOSInspectorRow("Type", value: TorrentDisplayFormat.sourceType(torrent))
                IOSInspectorRow("Restorable", value: torrent.addSource == nil ? "No" : "Yes")
            }

            IOSInspectorGroup("Files") {
                if !snapshot.itemExists && !snapshot.directoryExists {
                    IOSInspectorEmptyState("No downloaded files on this device")
                }
            }

            IOSInspectorGroup("Remove") {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        store.selection = torrent.id
                        store.removeSelectedTorrent()
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }

                    Button(role: .destructive) {
                        store.selection = torrent.id
                        confirmRemoveData()
                    } label: {
                        Label("Delete Data", systemImage: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
