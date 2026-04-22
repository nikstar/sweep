import SwiftUI
import SweepCore

struct TorrentInfoInspector: View {
    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        InspectorPane {
            InspectorGroup("Torrent") {
                InspectorRow("Name") {
                    CopyableValue(torrent.name)
                }
                InspectorRow("Status", value: torrent.statusLabel)
                InspectorRow("Progress", value: TorrentDisplayFormat.percent(torrent.progress))
                InspectorRow("Size", value: TorrentDisplayFormat.bytesOrUnknown(torrent.totalBytes))
                InspectorRow("Engine ID", value: torrent.engineID.map(String.init) ?? "None")
            }

            InspectorGroup("Identity") {
                InspectorRow("Info Hash") {
                    CopyableValue(torrent.infoHash, monospaced: true)
                }
                if let magnet = torrent.magnet {
                    InspectorRow("Magnet") {
                        CopyableValue(magnet, lineLimit: 3)
                    }
                }
                if let torrentFileName = torrent.torrentFileName {
                    InspectorRow("Torrent File", value: torrentFileName)
                }
            }

            InspectorGroup("Location") {
                let directory = TorrentFileLocation.directoryURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )
                let item = TorrentFileLocation.expectedItemURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )

                InspectorRow("Save To") {
                    CopyableValue(abbreviatedPath(directory.path), copyValue: directory.path)
                }
                InspectorRow("Item") {
                    CopyableValue(abbreviatedPath(item.path), copyValue: item.path)
                }
            }

            InspectorGroup("Dates") {
                InspectorRow("Added", value: TorrentDisplayFormat.date(torrent.addedAt))
                InspectorRow("Updated", value: TorrentDisplayFormat.date(torrent.updatedAt))
            }

            if let error = torrent.error, !error.isEmpty {
                InspectorGroup("Error") {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
