import SwiftUI
import SweepCore

struct TorrentFilesInspector: View {
    @EnvironmentObject private var store: TorrentStore

    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        let snapshot = TorrentFileLocation.snapshot(
            for: torrent,
            defaultDirectory: defaultDownloadDirectory
        )
        let includedCount = torrent.files.filter(\.included).count

        InspectorPane {
            InspectorGroup("Download") {
                InspectorRow("Kind", value: snapshot.displayKind)
                InspectorRow("Files", value: String(torrent.files.count))
                InspectorRow("Save To") {
                    CopyableValue(
                        abbreviatedPath(snapshot.directoryURL.path),
                        copyValue: snapshot.directoryURL.path
                    )
                }
                InspectorRow("Item") {
                    CopyableValue(
                        abbreviatedPath(snapshot.expectedItemURL.path),
                        copyValue: snapshot.expectedItemURL.path
                    )
                }
                if let itemSize = snapshot.itemSize {
                    InspectorRow("On Disk", value: ByteFormatter.bytes(itemSize))
                }

                HStack(spacing: 8) {
                    Button {
                        TorrentFileLocation.revealInFinder(
                            torrent: torrent,
                            defaultDirectory: defaultDownloadDirectory
                        )
                    } label: {
                        Label("Reveal", systemImage: "magnifyingglass")
                    }
                    .disabled(!snapshot.itemExists && !snapshot.directoryExists)

                    Button {
                        TorrentFileLocation.copyExpectedPath(
                            torrent: torrent,
                            defaultDirectory: defaultDownloadDirectory
                        )
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                }
                .controlSize(.small)
            }

            if torrent.files.isEmpty {
                InspectorEmptyState("No files yet")
            } else {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(torrent.files) { file in
                        TorrentFileInspectorRow(
                            torrent: torrent,
                            file: file,
                            includedCount: includedCount
                        )
                        .environmentObject(store)
                    }
                }
            }
        }
    }
}

private struct TorrentFileInspectorRow: View {
    @EnvironmentObject private var store: TorrentStore

    let torrent: Torrent
    let file: TorrentFile
    let includedCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(
                "",
                isOn: Binding(
                    get: { file.included },
                    set: { store.setFile(file, included: $0, in: torrent) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!canDisable)
            .controlSize(.small)
            .help(file.included ? "Download file" : "Skip file")

            Image(systemName: file.isPadding ? "doc.badge.gearshape" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 18)

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
                    Text("\(TorrentDisplayFormat.percent(file.progress))")
                        .monospacedDigit()
                    Text("\(ByteFormatter.bytes(file.progressBytes)) downloaded")
                    Text(file.included ? file.priority.capitalized : "Skipped")
                        .foregroundStyle(file.included ? Color.secondary : Color.orange)
                    Spacer(minLength: 8)
                    Menu {
                        Button("Download") {
                            store.setFile(file, included: true, in: torrent)
                        }
                        Button("Skip") {
                            store.setFile(file, included: false, in: torrent)
                        }
                        .disabled(!canDisable)
                    } label: {
                        Label(
                            file.included ? "Download" : "Skip",
                            systemImage: file.included ? "checkmark.circle" : "slash.circle"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var canDisable: Bool {
        !file.included || includedCount > 1
    }
}
