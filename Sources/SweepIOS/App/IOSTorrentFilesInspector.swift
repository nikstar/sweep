import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentFilesInspector: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let torrent: Torrent
    let defaultDownloadDirectory: String
    let play: (TorrentFile) -> Void

    var body: some View {
        let files = torrent.files.filter { !$0.isPadding }
        let media = TorrentMedia(files: files)
        let videoIDs = Set(media.videos.map(\.id))
        let includedCount = files.filter(\.included).count

        IOSInspectorPane {
            if files.isEmpty {
                IOSInspectorEmptyState("Files appear once torrent metadata is available.")
            } else {
                let selectionLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())
                selectionLayout {
                    Text("\(includedCount) of \(files.count) selected")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Menu {
                        Button("Download All", systemImage: "arrow.down.circle") {
                            store.setFiles(includedFileIDs: files.map(\.id), in: torrent)
                        }
                        if !media.videos.isEmpty {
                            Button("Download Videos Only", systemImage: "film") {
                                store.setFiles(includedFileIDs: media.videos.map(\.id), in: torrent)
                            }
                        }
                    } label: {
                        Label("Select", systemImage: "checklist")
                            .frame(minHeight: 44)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .disabled(store.changingFileSelection.contains(torrent.id))
                }
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
                // File actions come first; the full location remains available below.
                IOSInspectorGroup("Location") {
                    Text(TorrentDisplayFormat.abbreviatedPath(torrent.downloadDirectory ?? defaultDownloadDirectory))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private func fileSection(_ title: String, files: [TorrentFile], includedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 8)
            LazyVStack(spacing: 0) {
                ForEach(files) { file in
                    IOSTorrentFileRow(torrent: torrent, file: file, includedCount: includedCount, play: play)
                        .padding(.vertical, 12)
                    if file.id != files.last?.id { Divider() }
                }
            }
        }
    }
}

private struct IOSTorrentFileRow: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let torrent: Torrent
    let file: TorrentFile
    let includedCount: Int
    let play: (TorrentFile) -> Void

    var body: some View {
        let url = TorrentFileLocation.openableFileURL(for: file, in: torrent, defaultDirectory: store.downloadDirectory)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: file.isVideo ? "film" : "doc")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary).frame(width: 22, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name).font(.body)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3).truncationMode(.middle)
                    let folder = (file.path as NSString).deletingLastPathComponent
                    if !folder.isEmpty {
                        Text(folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Text("\(ByteFormatter.bytes(file.length)) · \(file.included ? TorrentDisplayFormat.percent(file.progress) : "Not downloading")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    if let url {
                        Button("Open in Another App…", systemImage: "square.and.arrow.up") { open(url) }
                        Divider()
                    }
                    Button("Download Only This File", systemImage: "arrow.down.circle") {
                        store.setFiles(includedFileIDs: [file.id], in: torrent)
                    }
                    .disabled(store.changingFileSelection.contains(torrent.id))
                    Button("Copy File Path", systemImage: "doc.on.doc") { UIPasteboard.general.string = file.path }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions for \(file.name)")
                .accessibilityIdentifier("file.\(file.id).menu")
            }
            SegmentedProgressView(runs: file.progressRuns, fallbackProgress: file.progress,
                                  state: file.progress >= 1 ? "Complete" : (file.included ? torrent.statusLabel : "Paused"), height: 6)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { fileActions(url) }
                VStack(alignment: .leading, spacing: 8) { fileActions(url) }
            }
        }
    }

    @ViewBuilder private func fileActions(_ url: URL?) -> some View {
        Button {
            if file.isVideo { play(file) } else if let url { open(url) }
        } label: {
            Label(file.isVideo ? "Play" : "Open", systemImage: file.isVideo ? "play.fill" : "square.and.arrow.up")
                .frame(minWidth: 58, minHeight: 28)
        }
        .buttonStyle(.bordered)
        .disabled(url == nil)
        .accessibilityLabel("\(file.isVideo ? "Play" : "Open") \(file.name)")
        .accessibilityIdentifier("file.\(file.id).open")
        Toggle("Download", isOn: Binding(
            get: { file.included },
            set: { store.setFile(file, included: $0, in: torrent) }
        ))
        .font(.subheadline)
        .frame(minHeight: 44)
        .disabled(store.changingFileSelection.contains(torrent.id) || (file.included && includedCount <= 1))
        .accessibilityLabel("Download \(file.name)")
        .accessibilityIdentifier("file.\(file.id).download")
    }

    private func open(_ url: URL) {
        store.lastError = IOSOpenInPresenter.shared.present(url: url)
            ? nil : "The sharing menu could not be opened for \(url.lastPathComponent)."
    }
}
