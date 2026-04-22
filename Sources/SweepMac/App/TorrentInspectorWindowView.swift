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

        case .trackers:
            TorrentTrackersInspector(torrent: torrent)

        case .peers:
            TorrentPeersInspector(torrent: torrent)

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
                    SegmentedProgressView(
                        runs: torrent.pieceRuns,
                        fallbackProgress: torrent.progress,
                        state: torrent.statusLabel
                    )
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

private struct TorrentTrackersInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorForm {
            Section("Trackers") {
                LabeledContent("Count", value: String(torrent.trackers.count))

                if torrent.trackers.isEmpty {
                    Text("No trackers")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(torrent.trackers) { tracker in
                        TorrentTrackerInspectorRow(tracker: tracker)
                    }
                }
            }
        }
    }
}

private struct TorrentTrackerInspectorRow: View {
    let tracker: TorrentTracker

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    CopyableValue(tracker.url)
                    Spacer()
                    Text(tracker.kind)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text(tracker.status)
                    if let lastPeerCount = tracker.lastPeerCount {
                        Text("\(lastPeerCount) peers")
                    }
                    if let seeders = tracker.seeders {
                        Text("\(seeders) seeds")
                    }
                    if let leechers = tracker.leechers {
                        Text("\(leechers) leechers")
                    }
                    if let downloads = tracker.downloads {
                        Text("\(downloads) downloads")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if tracker.lastAnnounceAt != nil || tracker.nextAnnounceAt != nil {
                    HStack(spacing: 12) {
                        if let lastAnnounceAt = tracker.lastAnnounceAt {
                            Text("Last \(InspectorFormat.date(lastAnnounceAt))")
                        }
                        if let nextAnnounceAt = tracker.nextAnnounceAt {
                            Text("Next \(InspectorFormat.date(nextAnnounceAt))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let scrapeURL = tracker.scrapeURL {
                    HStack(spacing: 5) {
                        Text("Scrape")
                            .foregroundStyle(.secondary)
                        CopyableValue(scrapeURL)
                    }
                    .font(.caption)
                }

                if let lastError = tracker.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TorrentPeersInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorForm {
            Section("Peers") {
                LabeledContent("Connected", value: String(torrent.peers.count))

                if torrent.peers.isEmpty {
                    Text("No connected peers")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(torrent.peers) { peer in
                        TorrentPeerInspectorRow(peer: peer)
                    }
                }
            }
        }
    }
}

private struct TorrentPeerInspectorRow: View {
    let peer: TorrentPeer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: peer.state == "live" ? "circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(peer.state == "live" ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(peer.address)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(InspectorFormat.peerConnection(peer))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text(peer.countryCode ?? peer.state.capitalized)
                    Text(peer.client ?? InspectorFormat.peerConnection(peer))
                    if !peer.featureFlags.isEmpty {
                        Text(peer.featureFlags.joined(separator: ", "))
                    }
                    if let availability = peer.availability {
                        Text("\(InspectorFormat.percent(availability)) available")
                    }
                    if let availablePieces = peer.availablePieces {
                        Text("\(availablePieces) pieces")
                    }
                    Text("\(ByteFormatter.bytes(peer.downloadedBytes)) down")
                    Text("\(ByteFormatter.bytes(peer.uploadedBytes)) up")
                    if let downloadBps = peer.downloadBps {
                        Text("\(ByteFormatter.rate(downloadBps)) down")
                    }
                    if let uploadBps = peer.uploadBps {
                        Text("\(ByteFormatter.rate(uploadBps)) up")
                    }
                    if peer.errors > 0 {
                        Text("\(peer.errors) errors")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let peerID = peer.peerID {
                    Text(peerID)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
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

                SegmentedProgressView(
                    runs: file.progressRuns,
                    fallbackProgress: file.progress,
                    state: file.included ? "Downloading" : "Paused"
                )

                HStack {
                    Text("\(ByteFormatter.bytes(file.progressBytes)) downloaded")
                    Spacer()
                    Text(file.included ? file.priority.capitalized : "Skipped")
                        .foregroundStyle(.secondary)
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

    static func peerConnection(_ peer: TorrentPeer) -> String {
        if let connectionKind = peer.connectionKind, !connectionKind.isEmpty {
            return connectionKind
        }
        if peer.connectionAttempts > 0 {
            return "\(peer.connectionAttempts) attempts"
        }
        return "Queued"
    }
}
