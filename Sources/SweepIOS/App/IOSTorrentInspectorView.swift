import SwiftUI
import UIKit
import SweepCore

struct IOSTorrentInspectorView: View {
    @Environment(TorrentStore.self) private var store

    let torrentID: Torrent.ID

    @State private var selectedTab: IOSInspectorTab = .info
    @State private var confirmingRemoveData = false

    var body: some View {
        Group {
            if let torrent {
                VStack(spacing: 0) {
                    Picker("Inspector Section", selection: $selectedTab) {
                        ForEach(IOSInspectorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    ScrollView {
                        selectedContent(for: torrent)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    }
                }
                .navigationTitle(torrent.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            togglePause(torrent)
                        } label: {
                            Label(
                                torrent.desiredState == .paused ? "Resume" : "Pause",
                                systemImage: torrent.desiredState == .paused ? "play.fill" : "pause.fill"
                            )
                        }

                        Menu {
                            Button {
                                store.refresh()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }

                            if let shareURL = shareURL(for: torrent) {
                                ShareLink(item: shareURL) {
                                    Label("Share Download", systemImage: "square.and.arrow.up")
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                store.removeSelectedTorrent()
                            } label: {
                                Label("Remove", systemImage: "xmark")
                            }

                            Button(role: .destructive) {
                                confirmingRemoveData = true
                            } label: {
                                Label("Delete Data", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Torrent Removed", systemImage: "xmark.circle")
            }
        }
        .removeTorrentDataConfirmation(isPresented: $confirmingRemoveData, store: store)
        .task {
            store.selection = torrentID
            store.startPolling()
        }
        .onAppear {
            store.selection = torrentID
        }
    }

    private var torrent: Torrent? {
        store.torrents.first { $0.id == torrentID }
    }

    @ViewBuilder
    private func selectedContent(for torrent: Torrent) -> some View {
        switch selectedTab {
        case .info:
            IOSTorrentInfoInspector(torrent: torrent, defaultDownloadDirectory: store.downloadDirectory)

        case .activity:
            IOSTorrentActivityInspector(torrent: torrent)

        case .trackers:
            IOSTorrentTrackersInspector(torrent: torrent)

        case .peers:
            IOSTorrentPeersInspector(torrent: torrent)

        case .files:
            IOSTorrentFilesInspector(torrent: torrent, defaultDownloadDirectory: store.downloadDirectory)

        case .options:
            IOSTorrentOptionsInspector(
                torrent: torrent,
                defaultDownloadDirectory: store.downloadDirectory,
                confirmRemoveData: { confirmingRemoveData = true }
            )
        }
    }

    private func togglePause(_ torrent: Torrent) {
        store.selection = torrent.id
        if torrent.desiredState == .paused {
            store.resumeSelectedTorrent()
        } else {
            store.pauseSelectedTorrent()
        }
    }

    private func shareURL(for torrent: Torrent) -> URL? {
        let snapshot = IOSTorrentFileLocation.snapshot(
            for: torrent,
            defaultDirectory: store.downloadDirectory
        )
        guard snapshot.itemExists || snapshot.directoryExists else { return nil }
        return snapshot.shareURL
    }
}

private enum IOSInspectorTab: String, CaseIterable, Identifiable {
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
}

private struct IOSTorrentInfoInspector: View {
    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        IOSInspectorPane {
            IOSInspectorGroup("Torrent") {
                IOSInspectorRow("Name") {
                    IOSCopyableValue(torrent.name)
                }
                IOSInspectorRow("Status", value: torrent.statusLabel)
                IOSInspectorRow("Progress", value: IOSDisplayFormat.percent(torrent.progress))
                IOSInspectorRow("Size", value: IOSDisplayFormat.bytesOrUnknown(torrent.totalBytes))
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
                let directory = IOSTorrentFileLocation.directoryURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )
                let item = IOSTorrentFileLocation.expectedItemURL(
                    for: torrent,
                    defaultDirectory: defaultDownloadDirectory
                )

                IOSInspectorRow("Save To") {
                    IOSCopyableValue(
                        IOSDisplayFormat.abbreviatedPath(directory.path),
                        copyValue: directory.path
                    )
                }
                IOSInspectorRow("Item") {
                    IOSCopyableValue(
                        IOSDisplayFormat.abbreviatedPath(item.path),
                        copyValue: item.path
                    )
                }
            }

            IOSInspectorGroup("Dates") {
                IOSInspectorRow("Added", value: IOSDisplayFormat.date(torrent.addedAt))
                IOSInspectorRow("Updated", value: IOSDisplayFormat.date(torrent.updatedAt))
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

private struct IOSTorrentActivityInspector: View {
    let torrent: Torrent

    var body: some View {
        IOSInspectorPane {
            IOSInspectorGroup("Progress") {
                VStack(alignment: .leading, spacing: 5) {
                    IOSSegmentedProgressView(
                        runs: torrent.pieceRuns,
                        fallbackProgress: torrent.progress,
                        state: torrent.statusLabel,
                        height: 10
                    )
                    HStack {
                        Text(IOSDisplayFormat.percent(torrent.progress))
                        Spacer()
                        Text(torrent.statusLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }

                IOSInspectorRow("Downloaded", value: ByteFormatter.bytes(torrent.progressBytes))
                IOSInspectorRow("Remaining", value: IOSDisplayFormat.remainingBytes(torrent))
                IOSInspectorRow("Total Size", value: IOSDisplayFormat.bytesOrUnknown(torrent.totalBytes))
            }

            IOSInspectorGroup("Transfer") {
                IOSInspectorRow("Download", value: ByteFormatter.rate(torrent.downloadBps))
                IOSInspectorRow("Upload", value: ByteFormatter.rate(torrent.uploadBps))
                IOSInspectorRow("Uploaded", value: ByteFormatter.bytes(torrent.uploadedBytes))
                IOSInspectorRow("Ratio", value: IOSDisplayFormat.ratio(torrent))
                IOSInspectorRow("ETA", value: torrent.etaSeconds.map(IOSDisplayFormat.duration) ?? "Unknown")
            }

            IOSInspectorGroup("State") {
                IOSInspectorRow("Engine", value: torrent.state)
                IOSInspectorRow("Desired", value: torrent.desiredState.rawValue.capitalized)
                IOSInspectorRow("Last Update", value: IOSDisplayFormat.date(torrent.updatedAt))
            }
        }
    }
}

private struct IOSTorrentTrackersInspector: View {
    let torrent: Torrent

    var body: some View {
        IOSInspectorPane {
            IOSInspectorGroup("Summary") {
                IOSInspectorMetricLine {
                    IOSInspectorMetric("Total", String(torrent.trackers.count))
                    IOSInspectorMetric("Working", String(torrent.trackers.filter { $0.status == "Working" }.count))
                    IOSInspectorMetric("Seeds", IOSDisplayFormat.optionalCount(torrent.trackers.compactMap(\.seeders).max()))
                    IOSInspectorMetric("Leechers", IOSDisplayFormat.optionalCount(torrent.trackers.compactMap(\.leechers).max()))
                }
            }

            if torrent.trackers.isEmpty {
                IOSInspectorEmptyState("No trackers")
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(torrent.trackers) { tracker in
                        IOSTorrentTrackerRow(tracker: tracker)
                    }
                }
            }
        }
    }
}

private struct IOSTorrentTrackerRow: View {
    let tracker: TorrentTracker

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tracker.status == "Working" ? "circle.fill" : "circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tracker.status == "Working" ? .green : .secondary)
                .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    IOSCopyableValue(tracker.url)
                    Spacer(minLength: 8)
                    Text(tracker.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                IOSInspectorTextLine {
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

                IOSInspectorTextLine {
                    if let lastAnnounceAt = tracker.lastAnnounceAt {
                        Text("Last \(IOSDisplayFormat.date(lastAnnounceAt))")
                    }
                    if let nextAnnounceAt = tracker.nextAnnounceAt {
                        Text("Next \(IOSDisplayFormat.date(nextAnnounceAt))")
                    }
                }

                if let scrapeURL = tracker.scrapeURL {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Scrape")
                            .foregroundStyle(.secondary)
                        IOSCopyableValue(scrapeURL)
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
}

private struct IOSTorrentPeersInspector: View {
    let torrent: Torrent

    var body: some View {
        IOSInspectorPane {
            IOSInspectorGroup("Summary") {
                let livePeers = torrent.peers.filter(\.isLiveConnection)
                IOSInspectorMetricLine {
                    IOSInspectorMetric("Live", String(livePeers.count))
                    IOSInspectorMetric("Downloading", String(livePeers.filter { ($0.downloadBps ?? 0) > 1 }.count))
                    IOSInspectorMetric("Uploading", String(livePeers.filter { ($0.uploadBps ?? 0) > 1 }.count))
                }
            }

            if torrent.peers.isEmpty {
                IOSInspectorEmptyState("No connected peers")
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(torrent.peers) { peer in
                        IOSTorrentPeerRow(peer: peer)
                    }
                }
            }
        }
    }
}

private struct IOSTorrentPeerRow: View {
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
                    Text(IOSDisplayFormat.peerConnection(peer))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                IOSInspectorTextLine {
                    Text(peer.client ?? peer.state.capitalized)
                    if let countryCode = peer.countryCode {
                        Text(countryCode)
                    }
                    if let availability = peer.availability {
                        Text("\(IOSDisplayFormat.percent(availability)) available")
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

                IOSInspectorTextLine {
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

private struct IOSTorrentFilesInspector: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let defaultDownloadDirectory: String

    var body: some View {
        let snapshot = IOSTorrentFileLocation.snapshot(
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
                        IOSDisplayFormat.abbreviatedPath(snapshot.directoryURL.path),
                        copyValue: snapshot.directoryURL.path
                    )
                }
                IOSInspectorRow("Item") {
                    IOSCopyableValue(
                        IOSDisplayFormat.abbreviatedPath(snapshot.expectedItemURL.path),
                        copyValue: snapshot.expectedItemURL.path
                    )
                }
                if let itemSize = snapshot.itemSize {
                    IOSInspectorRow("On Disk", value: ByteFormatter.bytes(itemSize))
                }
                if snapshot.itemExists || snapshot.directoryExists {
                    ShareLink(item: snapshot.shareURL) {
                        Label("Share Download", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

                IOSSegmentedProgressView(
                    runs: file.progressRuns,
                    fallbackProgress: file.progress,
                    state: file.included ? "Downloading" : "Paused",
                    height: 7
                )

                HStack(spacing: 8) {
                    Text(IOSDisplayFormat.percent(file.progress))
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
                        .disabled(file.included && includedCount <= 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct IOSTorrentOptionsInspector: View {
    @Environment(TorrentStore.self) private var store

    let torrent: Torrent
    let defaultDownloadDirectory: String
    let confirmRemoveData: () -> Void

    var body: some View {
        let snapshot = IOSTorrentFileLocation.snapshot(
            for: torrent,
            defaultDirectory: defaultDownloadDirectory
        )

        IOSInspectorPane {
            IOSInspectorGroup("Transfer") {
                IOSInspectorRow("Desired", value: torrent.desiredState.rawValue.capitalized)
                IOSInspectorRow("Current", value: torrent.statusLabel)

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
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            IOSInspectorGroup("Source") {
                IOSInspectorRow("Type", value: IOSDisplayFormat.sourceType(torrent))
                IOSInspectorRow("Restorable", value: torrent.addSource == nil ? "No" : "Yes")
            }

            IOSInspectorGroup("Files") {
                if snapshot.itemExists || snapshot.directoryExists {
                    ShareLink(item: snapshot.shareURL) {
                        Label("Share Download", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
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

private struct IOSInspectorPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct IOSInspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IOSInspectorRow<Content: View>: View {
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
                .frame(width: 88, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

private struct IOSInspectorMetricLine<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            content
        }
        .font(.callout)
    }
}

private struct IOSInspectorMetric: View {
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

private struct IOSInspectorTextLine<Content: View>: View {
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

private struct IOSInspectorEmptyState: View {
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

private struct IOSCopyableValue: View {
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
                UIPasteboard.general.string = copyValue
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Copy")
        }
    }
}
