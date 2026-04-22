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
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 7)

            if let torrent = store.selectedTorrent {
                ScrollView {
                    selectedContent(for: torrent)
                        .padding(.horizontal, 12)
                        .padding(.top, 3)
                        .padding(.bottom, 12)
                }
            } else {
                ContentUnavailableView("No Torrent Selected", systemImage: "info")
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
        InspectorPane {
            InspectorGroup("Torrent") {
                InspectorRow("Name") {
                    CopyableValue(torrent.name)
                }
                InspectorRow("Status", value: torrent.statusLabel)
                InspectorRow("Progress", value: InspectorFormat.percent(torrent.progress))
                InspectorRow("Size", value: InspectorFormat.bytesOrUnknown(torrent.totalBytes))
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
                InspectorRow("Added", value: InspectorFormat.date(torrent.addedAt))
                InspectorRow("Updated", value: InspectorFormat.date(torrent.updatedAt))
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

private struct TorrentActivityInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorPane {
            InspectorGroup("Progress") {
                VStack(alignment: .leading, spacing: 5) {
                    SegmentedProgressView(
                        runs: torrent.pieceRuns,
                        fallbackProgress: torrent.progress,
                        state: torrent.statusLabel,
                        height: 9
                    )
                    HStack {
                        Text(InspectorFormat.percent(torrent.progress))
                        Spacer()
                        Text(torrent.statusLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }

                InspectorRow("Downloaded", value: ByteFormatter.bytes(torrent.progressBytes))
                InspectorRow("Remaining", value: InspectorFormat.remainingBytes(torrent))
                InspectorRow("Total Size", value: InspectorFormat.bytesOrUnknown(torrent.totalBytes))
            }

            InspectorGroup("Transfer") {
                InspectorRow("Download", value: ByteFormatter.rate(torrent.downloadBps))
                InspectorRow("Upload", value: ByteFormatter.rate(torrent.uploadBps))
                InspectorRow("Uploaded", value: ByteFormatter.bytes(torrent.uploadedBytes))
                InspectorRow("Ratio", value: InspectorFormat.ratio(torrent))
                InspectorRow("ETA", value: torrent.etaSeconds.map(InspectorFormat.duration) ?? "Unknown")
            }

            InspectorGroup("State") {
                InspectorRow("Engine", value: torrent.state)
                InspectorRow("Desired", value: torrent.desiredState.rawValue.capitalized)
                InspectorRow("Last Update", value: InspectorFormat.date(torrent.updatedAt))
            }
        }
    }
}

private struct TorrentTrackersInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorPane {
            InspectorGroup("Summary") {
                InspectorMetricLine {
                    InspectorMetric("Total", String(torrent.trackers.count))
                    InspectorMetric("Working", String(torrent.trackers.filter { $0.status == "Working" }.count))
                    InspectorMetric("Seeds", InspectorFormat.optionalCount(torrent.trackers.compactMap(\.seeders).max()))
                    InspectorMetric("Leechers", InspectorFormat.optionalCount(torrent.trackers.compactMap(\.leechers).max()))
                }
            }

            if torrent.trackers.isEmpty {
                InspectorEmptyState("No trackers")
            } else {
                LazyVStack(alignment: .leading, spacing: 9) {
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CopyableValue(tracker.url)
                    Spacer(minLength: 8)
                    Text(tracker.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                InspectorTextLine {
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

                InspectorTextLine {
                    if let lastAnnounceAt = tracker.lastAnnounceAt {
                        Text("Last \(InspectorFormat.date(lastAnnounceAt))")
                    }
                    if let nextAnnounceAt = tracker.nextAnnounceAt {
                        Text("Next \(InspectorFormat.date(nextAnnounceAt))")
                    }
                }

                if let scrapeURL = tracker.scrapeURL {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
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
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var statusImage: String {
        tracker.status == "Working" ? "circle.fill" : "circle"
    }

    private var statusColor: Color {
        tracker.status == "Working" ? .green : .secondary
    }
}

private struct TorrentPeersInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorPane {
            InspectorGroup("Summary") {
                let livePeers = torrent.peers.filter(\.isLiveConnection)
                InspectorMetricLine {
                    InspectorMetric("Live", String(livePeers.count))
                    InspectorMetric("Downloading", String(livePeers.filter { ($0.downloadBps ?? 0) > 1 }.count))
                    InspectorMetric("Uploading", String(livePeers.filter { ($0.uploadBps ?? 0) > 1 }.count))
                }
            }

            if torrent.peers.isEmpty {
                InspectorEmptyState("No connected peers")
            } else {
                LazyVStack(alignment: .leading, spacing: 9) {
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: peer.isLiveConnection ? "circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(peer.isLiveConnection ? .green : .secondary)
                .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(peer.address)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Text(InspectorFormat.peerConnection(peer))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                InspectorTextLine {
                    Text(peer.client ?? peer.state.capitalized)
                    if let countryCode = peer.countryCode {
                        Text(countryCode)
                    }
                    if let availability = peer.availability {
                        Text("\(InspectorFormat.percent(availability)) available")
                    }
                    if let availablePieces = peer.availablePieces {
                        Text("\(availablePieces) pieces")
                    }
                }

                if let availability = peer.availability {
                    ProgressView(value: availability.clamped(to: 0...1))
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                }

                InspectorTextLine {
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

                if !peer.featureFlags.isEmpty {
                    Text(peer.featureFlags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

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
    }
}

private struct TorrentFilesInspector: View {
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
                    Text("\(InspectorFormat.percent(file.progress))")
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

private struct TorrentOptionsInspector: View {
    @EnvironmentObject private var store: TorrentStore

    let torrent: Torrent

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
                InspectorRow("Type", value: InspectorFormat.sourceType(torrent))
                InspectorRow("Restorable", value: torrent.addSource == nil ? "No" : "Yes")
            }

            InspectorGroup("File") {
                Button {
                    TorrentFileLocation.revealInFinder(
                        torrent: torrent,
                        defaultDirectory: store.downloadDirectory
                    )
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
            }

            InspectorGroup("Remove") {
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        store.removeSelectedTorrent()
                    } label: {
                        Label("Remove", systemImage: "xmark")
                    }

                    Button(role: .destructive) {
                        store.removeSelectedTorrent(deleteData: true)
                    } label: {
                        Label("Remove Data", systemImage: "trash")
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

private struct InspectorPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct InspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 3) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init(_ title: String, value: String) where Content == Text {
        self.title = title
        self.content = Text(value)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

private struct InspectorMetricLine<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            content
        }
        .font(.callout)
    }
}

private struct InspectorMetric: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
    }
}

private struct InspectorTextLine<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct InspectorEmptyState: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
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
        HStack(spacing: 4) {
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
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
            .controlSize(.small)
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

    static func optionalCount<T: BinaryInteger>(_ value: T?) -> String {
        value.map { String($0) } ?? "-"
    }

    static func duration(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

private extension TorrentPeer {
    var isLiveConnection: Bool {
        state == "live" || connections > 0
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
