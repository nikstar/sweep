import AppKit
import SwiftUI
import SweepCore

struct TorrentInspectorWindowView: View {
    @EnvironmentObject private var store: TorrentStore
    @State private var selectedTab: InspectorTab = .info

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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if let torrent = store.selectedTorrent {
                selectedContent(for: torrent)
            } else {
                ContentUnavailableView("No Torrent Selected", systemImage: "info.circle")
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

        case .files:
            TorrentFilesInspector(torrent: torrent, defaultDownloadDirectory: store.downloadDirectory)

        case .options:
            TorrentOptionsInspector(torrent: torrent)
                .environmentObject(store)
        }
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case info
    case activity
    case files
    case options

    var id: Self { self }

    var title: String {
        switch self {
        case .info:
            "Info"
        case .activity:
            "Activity"
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
        case .files:
            "folder"
        case .options:
            "slider.horizontal.3"
        }
    }
}

private struct TorrentInfoInspector: View {
    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        InspectorForm {
            Section("Torrent") {
                LabeledContent("Name") {
                    CopyableValue(torrent.name)
                }
                LabeledContent("Status", value: torrent.statusLabel)
                LabeledContent("Progress", value: InspectorFormat.percent(torrent.progress))
                LabeledContent("Size", value: InspectorFormat.bytesOrUnknown(torrent.totalBytes))
                LabeledContent("Engine ID", value: torrent.engineID.map(String.init) ?? "None")
            }

            Section("Identity") {
                LabeledContent("Info Hash") {
                    CopyableValue(torrent.infoHash, monospaced: true)
                }

                if let magnet = torrent.magnet {
                    LabeledContent("Magnet") {
                        CopyableValue(magnet, lineLimit: 3)
                    }
                }

                if let torrentFileName = torrent.torrentFileName {
                    LabeledContent("Torrent File", value: torrentFileName)
                }
            }

            Section("Location") {
                let directory = TorrentFileLocation.directoryURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )
                let item = TorrentFileLocation.expectedItemURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )

                LabeledContent("Save To") {
                    CopyableValue(abbreviatedPath(directory.path), copyValue: directory.path)
                }
                LabeledContent("Expected Item") {
                    CopyableValue(abbreviatedPath(item.path), copyValue: item.path)
                }
            }

            Section("Dates") {
                LabeledContent("Added", value: InspectorFormat.date(torrent.addedAt))
                LabeledContent("Updated", value: InspectorFormat.date(torrent.updatedAt))
            }

            if let error = torrent.error, !error.isEmpty {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct TorrentActivityInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorForm {
            Section("Progress") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: torrent.progress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(InspectorFormat.percent(torrent.progress))
                        Spacer()
                        Text(torrent.statusLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                LabeledContent("Downloaded", value: ByteFormatter.bytes(torrent.progressBytes))
                LabeledContent("Remaining", value: InspectorFormat.remainingBytes(torrent))
                LabeledContent("Total Size", value: InspectorFormat.bytesOrUnknown(torrent.totalBytes))
            }

            Section("Transfer") {
                LabeledContent("Download Speed", value: ByteFormatter.rate(torrent.downloadBps))
                LabeledContent("Upload Speed", value: ByteFormatter.rate(torrent.uploadBps))
                LabeledContent("Uploaded", value: ByteFormatter.bytes(torrent.uploadedBytes))
                LabeledContent("Ratio", value: InspectorFormat.ratio(torrent))
            }

            Section("State") {
                LabeledContent("Engine State", value: torrent.state)
                LabeledContent("Desired State", value: torrent.desiredState.rawValue.capitalized)
                LabeledContent("Last Update", value: InspectorFormat.date(torrent.updatedAt))
            }
        }
    }
}

private struct TorrentFilesInspector: View {
    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        let snapshot = TorrentFileLocation.snapshot(
            for: torrent,
            defaultDirectory: defaultDownloadDirectory
        )

        InspectorForm {
            Section("Download") {
                LabeledContent("Kind", value: snapshot.displayKind)
                LabeledContent("Files", value: String(torrent.files.count))
                LabeledContent("Save To") {
                    CopyableValue(
                        abbreviatedPath(snapshot.directoryURL.path),
                        copyValue: snapshot.directoryURL.path
                    )
                }
                LabeledContent("Expected Item") {
                    CopyableValue(
                        abbreviatedPath(snapshot.expectedItemURL.path),
                        copyValue: snapshot.expectedItemURL.path
                    )
                }

                if let itemSize = snapshot.itemSize {
                    LabeledContent("File Size", value: ByteFormatter.bytes(itemSize))
                }
            }

            if !torrent.files.isEmpty {
                Section("Files") {
                    ForEach(torrent.files) { file in
                        TorrentFileInspectorRow(file: file)
                    }
                }
            }

            Section("Actions") {
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
            }
        }
    }
}

private struct TorrentFileInspectorRow: View {
    let file: TorrentFile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isPadding ? "doc.badge.gearshape" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(file.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(ByteFormatter.bytes(file.length))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: file.progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(ByteFormatter.bytes(file.progressBytes)) downloaded")
                    Spacer()
                    if !file.included {
                        Text("Skipped")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TorrentOptionsInspector: View {
    @EnvironmentObject private var store: TorrentStore

    let torrent: Torrent

    var body: some View {
        InspectorForm {
            Section("Transfer") {
                LabeledContent("Desired State", value: torrent.desiredState.rawValue.capitalized)
                LabeledContent("Current State", value: torrent.statusLabel)

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
            }

            Section("Source") {
                LabeledContent("Type", value: InspectorFormat.sourceType(torrent))
                LabeledContent("Restorable", value: torrent.addSource == nil ? "No" : "Yes")
            }

            Section("File") {
                Button {
                    TorrentFileLocation.revealInFinder(
                        torrent: torrent,
                        defaultDirectory: store.downloadDirectory
                    )
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
            }

            Section("Remove") {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        store.removeSelectedTorrent()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        store.removeSelectedTorrent(deleteData: true)
                    } label: {
                        Label("Remove Data", systemImage: "trash.slash")
                    }
                }
            }
        }
    }
}

private struct InspectorForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CopyableValue: View {
    let value: String
    let copyValue: String
    let monospaced: Bool
    let lineLimit: Int

    init(
        _ value: String,
        copyValue: String? = nil,
        monospaced: Bool = false,
        lineLimit: Int = 1
    ) {
        self.value = value
        self.copyValue = copyValue ?? value
        self.monospaced = monospaced
        self.lineLimit = lineLimit
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyValue, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
    }
}

private enum InspectorFormat {
    static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = value < 1 ? 1 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    static func date(_ value: Date) -> String {
        value.formatted(date: .abbreviated, time: .shortened)
    }

    static func bytesOrUnknown(_ value: UInt64) -> String {
        value == 0 ? "Unknown" : ByteFormatter.bytes(value)
    }

    static func remainingBytes(_ torrent: Torrent) -> String {
        guard torrent.totalBytes > 0 else { return "Unknown" }
        let remaining = torrent.totalBytes > torrent.progressBytes
            ? torrent.totalBytes - torrent.progressBytes
            : 0
        return ByteFormatter.bytes(remaining)
    }

    static func ratio(_ torrent: Torrent) -> String {
        guard torrent.progressBytes > 0 else { return "0.00" }
        return String(format: "%.2f", Double(torrent.uploadedBytes) / Double(torrent.progressBytes))
    }

    static func sourceType(_ torrent: Torrent) -> String {
        if torrent.magnet != nil {
            return "Magnet"
        }
        if torrent.torrentFileBytes != nil {
            return "Torrent File"
        }
        return "Unknown"
    }
}
