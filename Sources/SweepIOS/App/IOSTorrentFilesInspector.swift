import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentFilesInspector: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        let snapshot = TorrentFileLocation.snapshot(
            for: torrent,
            defaultDirectory: defaultDownloadDirectory
        )
        let includedCount = torrent.files.filter(\.included).count

        IOSInspectorPane {
            IOSInspectorGroup("Download") {
                IOSInspectorRow("Kind", value: snapshot.displayKind)
                IOSInspectorRow("Files", value: String(torrent.files.count))
                IOSInspectorRow("Save To") {
                    IOSCopyableValue(
                        TorrentDisplayFormat.abbreviatedPath(snapshot.directoryURL.path),
                        copyValue: snapshot.directoryURL.path
                    )
                }
                IOSInspectorRow("Item") {
                    IOSCopyableValue(
                        TorrentDisplayFormat.abbreviatedPath(snapshot.expectedItemURL.path),
                        copyValue: snapshot.expectedItemURL.path
                    )
                }
                if let itemSize = snapshot.itemSize {
                    IOSInspectorRow("On Disk", value: ByteFormatter.bytes(itemSize))
                }
            }

            if torrent.files.isEmpty {
                IOSInspectorEmptyState("No files yet")
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(torrent.files) { file in
                        IOSTorrentFileRow(
                            torrent: torrent,
                            file: file,
                            includedCount: includedCount
                        )
                    }
                }
            }
        }
    }
}

private struct IOSTorrentFileRow: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let file: TorrentFile
    let includedCount: Int

    var body: some View {
        let fileSnapshot = TorrentFileLocation.fileSnapshot(
            for: file,
            in: torrent,
            defaultDirectory: store.downloadDirectory
        )

        HStack(alignment: .top, spacing: 9) {
            Button {
                store.setFile(file, included: !file.included, in: torrent)
            } label: {
                Image(systemName: file.included ? "checkmark.circle.fill" : "slash.circle")
                    .foregroundStyle(file.included ? .green : .orange)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(file.included && includedCount <= 1)
            .accessibilityLabel(file.included ? "Download file" : "Skip file")

            Image(systemName: file.isPadding ? "doc.badge.gearshape" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(file.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(ByteFormatter.bytes(file.length))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                SegmentedProgressView(
                    runs: file.progressRuns,
                    fallbackProgress: file.progress,
                    state: file.included ? "Downloading" : "Paused",
                    height: 7
                )

                HStack(spacing: 8) {
                    Text(TorrentDisplayFormat.percent(file.progress))
                        .monospacedDigit()
                    Text("\(ByteFormatter.bytes(file.progressBytes)) downloaded")
                    Text(file.included ? file.priority.capitalized : "Skipped")
                        .foregroundStyle(file.included ? Color.secondary : Color.orange)
                    Spacer(minLength: 8)
                    Menu {
                        if let fileSnapshot, fileSnapshot.isOpenable {
                            Button {
                                open(fileSnapshot.url)
                            } label: {
                                Label("Open...", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                        }
                        Button("Download") {
                            store.setFile(file, included: true, in: torrent)
                        }
                        Button("Skip") {
                            store.setFile(file, included: false, in: torrent)
                        }
                        .disabled(file.included && includedCount <= 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let fileSnapshot, fileSnapshot.isOpenable {
                    open(fileSnapshot.url)
                } else {
                    store.lastError = "\(file.name) is not available on this device yet."
                }
            }
        }
    }

    private func open(_ url: URL) {
        guard IOSOpenInPresenter.shared.present(url: url) else {
            store.lastError = "No app is available to open \(url.lastPathComponent)."
            return
        }
        store.lastError = nil
    }
}
