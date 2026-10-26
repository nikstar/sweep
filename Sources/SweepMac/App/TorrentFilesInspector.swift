import AppKit
import SwiftUI
import SweepCore
import SweepUI

struct TorrentFilesInspector: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        let snapshot = TorrentFileLocation.snapshot(
            for: torrent,
            defaultDirectory: defaultDownloadDirectory
        )
        let files = torrent.files.filter { !$0.isPadding }
        let media = TorrentMedia(files: files)
        let videoIDs = Set(media.videos.map(\.id))
        let includedCount = files.filter(\.included).count

        InspectorPane {
            if files.isEmpty {
                InspectorEmptyState("Files appear once torrent metadata is available.")
            } else {
                HStack {
                    Text("\(includedCount) of \(files.count) selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu("Select", systemImage: "checklist") {
                        Button("Download All") {
                            store.setFiles(includedFileIDs: files.map(\.id), in: torrent)
                        }
                        if !media.videos.isEmpty {
                            Button("Download Videos Only") {
                                store.setFiles(includedFileIDs: media.videos.map(\.id), in: torrent)
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(store.changingFileSelection.contains(torrent.id))
                }
                .font(.callout)
                .controlSize(.small)

                if includedCount == 1 {
                    Text("Keep at least one file selected. Pause the torrent to stop all downloads.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !media.videos.isEmpty {
                    fileSection(media.isSeries ? "Episodes" : "Videos", files: media.videos, includedCount: includedCount)
                }
                let others = files.filter { !videoIDs.contains($0.id) }
                if !others.isEmpty {
                    fileSection(media.videos.isEmpty ? "Files" : "Other Files", files: others, includedCount: includedCount)
                }
            }

            InspectorGroup("Download") {
                InspectorRow("Kind", value: snapshot.displayKind)
                InspectorRow("Files", value: String(files.count))
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

        }
    }

    private func fileSection(_ title: String, files: [TorrentFile], includedCount: Int) -> some View {
        InspectorGroup(title) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(files) { file in
                    TorrentFileInspectorRow(torrent: torrent, file: file, includedCount: includedCount)
                }
            }
        }
    }
}

private struct TorrentFileInspectorRow: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let file: TorrentFile
    let includedCount: Int

    var body: some View {
        let url = TorrentFileLocation.openableFileURL(
            for: file, in: torrent, defaultDirectory: store.downloadDirectory
        )
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
            .disabled(selectionChanging || !canDisable)
            .controlSize(.small)
            .help(file.included ? "Don't download this file" : "Download this file")
            .accessibilityLabel("Download \(file.name)")
            .accessibilityIdentifier("file.\(file.id).download")

            Image(systemName: file.isVideo ? "film" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(file.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.path)
                    Spacer(minLength: 8)
                    Text(ByteFormatter.bytes(file.length))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                SegmentedProgressView(
                    runs: file.progressRuns,
                    fallbackProgress: file.progress,
                    state: file.progress >= 1 ? "Complete" : (file.included ? torrent.statusLabel : "Paused"),
                    height: 7
                )

                HStack(spacing: 8) {
                    Text("\(TorrentDisplayFormat.percent(file.progress))")
                        .monospacedDigit()
                    Text(file.included ? file.priority.capitalized : "Skipped")
                        .foregroundStyle(file.included ? Color.secondary : Color.orange)
                    Spacer(minLength: 8)
                    Button(file.isVideo ? "Play" : "Open", systemImage: file.isVideo ? "play.fill" : "arrow.up.forward.square") {
                        TorrentActions.open(file, in: torrent, store: store)
                    }
                    .disabled(url == nil)
                    .controlSize(.small)
                    .help("Open the original file in its default app. Incomplete files may need more data before they can be read.")
                    .accessibilityLabel("\(file.isVideo ? "Play" : "Open") \(file.name)")
                    .accessibilityIdentifier("file.\(file.id).open")

                    Menu {
                        Button("Download Only This File") {
                            store.setFiles(includedFileIDs: [file.id], in: torrent)
                        }
                        .disabled(selectionChanging)
                        Divider()
                        Button("Reveal in Finder") {
                            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        .disabled(url == nil)
                        Button("Copy File Path") {
                            guard let path = TorrentFileLocation.fileURL(
                                for: file, in: torrent, defaultDirectory: store.downloadDirectory
                            )?.path else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .controlSize(.small)
                    .fixedSize()
                    .help("More actions for \(file.name)")
                    .accessibilityLabel("More actions for \(file.name)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var canDisable: Bool {
        !file.included || includedCount > 1
    }

    private var selectionChanging: Bool {
        store.changingFileSelection.contains(torrent.id)
    }
}
