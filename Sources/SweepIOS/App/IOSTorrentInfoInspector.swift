import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentInfoInspector: View {
    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        IOSInspectorPane {
            IOSInspectorGroup("Torrent") {
                IOSInspectorRow("Name") {
                    IOSCopyableValue(torrent.name)
                }
                IOSInspectorRow("Status", value: torrent.statusLabel)
                IOSInspectorRow("Progress", value: TorrentDisplayFormat.percent(torrent.progress))
                IOSInspectorRow("Size", value: TorrentDisplayFormat.bytesOrUnknown(torrent.totalBytes))
                IOSInspectorRow("Engine ID", value: torrent.engineID.map(String.init) ?? "None")
            }

            IOSInspectorGroup("Identity") {
                IOSInspectorRow("Info Hash") {
                    IOSCopyableValue(torrent.infoHash, monospaced: true)
                }
                if let magnet = torrent.magnet {
                    IOSInspectorRow("Magnet") {
                        IOSCopyableValue(magnet, lineLimit: 3)
                    }
                }
                if let torrentFileName = torrent.torrentFileName {
                    IOSInspectorRow("Torrent File", value: torrentFileName)
                }
            }

            IOSInspectorGroup("Location") {
                let directory = TorrentFileLocation.directoryURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )
                let item = TorrentFileLocation.expectedItemURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )

                IOSInspectorRow("Save To") {
                    IOSCopyableValue(
                        TorrentDisplayFormat.abbreviatedPath(directory.path),
                        copyValue: directory.path
                    )
                }
                IOSInspectorRow("Item") {
                    IOSCopyableValue(
                        TorrentDisplayFormat.abbreviatedPath(item.path),
                        copyValue: item.path
                    )
                }
            }

            IOSInspectorGroup("Dates") {
                IOSInspectorRow("Added", value: TorrentDisplayFormat.date(torrent.addedAt))
                IOSInspectorRow("Updated", value: TorrentDisplayFormat.date(torrent.updatedAt))
            }

            if let error = torrent.error, !error.isEmpty {
                IOSInspectorGroup("Error") {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
