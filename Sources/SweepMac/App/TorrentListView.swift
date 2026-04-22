import AppKit
import SwiftUI
import SweepCore

struct TorrentListView: View {
    @EnvironmentObject private var store: TorrentStore
    @EnvironmentObject private var inspectorPanelPresenter: TorrentInspectorPanelPresenter

    var body: some View {
        VStack(spacing: 0) {
            Table(store.torrents, selection: $store.selection) {
                TableColumn("Name") { torrent in
                    TorrentNameCell(torrent: torrent)
                        .environmentObject(store)
                }
                .width(min: 320, ideal: 420)

                TableColumn("Progress") { torrent in
                    TorrentProgressCell(torrent: torrent)
                }
                .width(min: 140, ideal: 170)

                if store.isColumnVisible(.size) {
                    TableColumn("Size") { torrent in
                        Text(ByteFormatter.bytes(torrent.totalBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 100)
                }

                if store.isColumnVisible(.eta) {
                    TableColumn("ETA") { torrent in
                        Text(formatETA(torrent))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 70, ideal: 90)
                }

                if store.isColumnVisible(.progress) {
                    TableColumn("%") { torrent in
                        Text(formatPercent(torrent.progress))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 54, ideal: 64)
                }

                if store.isColumnVisible(.remaining) {
                    TableColumn("Remaining") { torrent in
                        Text(ByteFormatter.bytes(torrent.remainingBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 92, ideal: 112)
                }

                TableColumn("Speed") { torrent in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormatter.rate(torrent.downloadBps))
                        Text(ByteFormatter.rate(torrent.uploadBps))
                    }
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 92, ideal: 112)

                TableColumn("Peers") { torrent in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(torrent.peers.count)")
                        Text("\(torrent.trackers.count) trackers")
                            .font(.caption2)
                    }
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 86)
            }
            .contextMenu {
                Button("Resume") {
                    store.resumeSelectedTorrent()
                }
                .disabled(!store.canResumeSelectedTorrent)

                Button("Pause") {
                    store.pauseSelectedTorrent()
                }
                .disabled(!store.canPauseSelectedTorrent)

                Divider()

                Button("Reveal in Finder") {
                    revealSelectedTorrentInFinder()
                }
                .disabled(store.selectedTorrent == nil)

                Button("Show Inspector") {
                    inspectorPanelPresenter.show(store: store)
                }

                Divider()

                Button("Remove") {
                    store.removeSelectedTorrent()
                }
                .disabled(store.selectedTorrent == nil)

                Button("Remove and Delete Data") {
                    store.removeSelectedTorrent(deleteData: true)
                }
                .disabled(store.selectedTorrent == nil)
            }
            .onDeleteCommand {
                store.removeSelectedTorrent()
            }

            TransferStatusBar()
        }
    }

    private func revealSelectedTorrentInFinder() {
        guard let torrent = store.selectedTorrent else { return }
        TorrentFileLocation.revealInFinder(
            torrent: torrent,
            defaultDirectory: store.downloadDirectory
        )
    }
}

private struct TorrentNameCell: View {
    @EnvironmentObject private var store: TorrentStore

    let torrent: Torrent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon.systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusIcon.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(torrent.name)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        store.selection = torrent.id
                        if torrent.desiredState == .paused {
                            store.resumeSelectedTorrent()
                        } else {
                            store.pauseSelectedTorrent()
                        }
                    } label: {
                        Image(systemName: torrent.desiredState == .paused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(torrent.desiredState == .paused ? "Resume" : "Pause")

                    Button {
                        TorrentFileLocation.revealInFinder(
                            torrent: torrent,
                            defaultDirectory: store.downloadDirectory
                        )
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Reveal in Finder")
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(torrent.error == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if let error = torrent.error, !error.isEmpty {
            return error
        }

        let progress = "\(ByteFormatter.bytes(torrent.progressBytes)) of \(ByteFormatter.bytes(torrent.totalBytes))"
        if torrent.remainingBytes > 0 {
            return "\(torrent.statusLabel) - \(progress) - \(ByteFormatter.bytes(torrent.remainingBytes)) left"
        }
        return "\(torrent.statusLabel) - \(progress)"
    }

    private var statusIcon: (systemName: String, color: Color) {
        if torrent.error != nil {
            return ("exclamationmark.circle.fill", .red)
        }
        if torrent.desiredState == .paused || torrent.isPausedInEngine {
            return ("circle", .secondary)
        }
        if torrent.progress >= 1 {
            return ("arrow.up.circle.fill", .green)
        }
        if torrent.downloadBps > 0 {
            return ("arrow.down.circle.fill", .blue)
        }
        return ("circle.dotted", .secondary)
    }
}

private struct TorrentProgressCell: View {
    let torrent: Torrent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SegmentedProgressView(
                runs: torrent.pieceRuns,
                fallbackProgress: torrent.progress,
                state: torrent.statusLabel
            )
            Text(formatPercent(torrent.progress))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct SegmentedProgressView: View {
    let runs: [TorrentPieceRun]
    let fallbackProgress: Double
    let state: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.18))

                HStack(spacing: 0) {
                    ForEach(displayRuns) { run in
                        Rectangle()
                            .fill(color(for: run.state))
                            .frame(width: width(for: run, totalWidth: proxy.size.width))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .frame(height: 7)
        .accessibilityLabel("Progress")
        .accessibilityValue(formatPercent(fallbackProgress))
    }

    private var displayRuns: [TorrentPieceRun] {
        if !runs.isEmpty {
            return runs
        }

        let downloaded = UInt64((fallbackProgress.clamped(to: 0...1) * 10_000).rounded())
        let remaining = 10_000 - downloaded
        return [
            TorrentPieceRun(id: 0, state: .downloaded, pieceCount: 1, byteCount: downloaded),
            TorrentPieceRun(id: 1, state: .needed, pieceCount: 1, byteCount: remaining)
        ].filter { $0.byteCount > 0 }
    }

    private var totalBytes: UInt64 {
        displayRuns.reduce(0) { $0 + $1.byteCount }
    }

    private func width(for run: TorrentPieceRun, totalWidth: CGFloat) -> CGFloat {
        guard totalBytes > 0 else { return 0 }
        return totalWidth * CGFloat(Double(run.byteCount) / Double(totalBytes))
    }

    private func color(for state: TorrentPieceState) -> Color {
        switch state {
        case .downloaded:
            self.state == "Complete" ? .green : .blue
        case .downloading:
            .accentColor
        case .needed:
            Color.secondary.opacity(0.22)
        case .skipped:
            Color.secondary.opacity(0.10)
        case .unknown:
            Color.secondary.opacity(0.14)
        }
    }
}

private struct TransferStatusBar: View {
    @EnvironmentObject private var store: TorrentStore

    var body: some View {
        HStack(spacing: 16) {
            Label(ByteFormatter.rate(store.sessionStats.downloadBps), systemImage: "arrow.down")
            Label(ByteFormatter.rate(store.sessionStats.uploadBps), systemImage: "arrow.up")
            Label("\(store.sessionStats.livePeers) peers", systemImage: "person.2")

            if store.sessionStats.connectingPeers > 0 {
                Text("\(store.sessionStats.connectingPeers) connecting")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = store.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let torrent = store.selectedTorrent {
                Text(torrent.statusLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }
}

extension TorrentListColumn {
    var title: String {
        switch self {
        case .size:
            "Size"
        case .eta:
            "ETA"
        case .progress:
            "Progress %"
        case .remaining:
            "Remaining"
        }
    }
}

private func formatPercent(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = value < 1 ? 1 : 0
    return formatter.string(from: NSNumber(value: value)) ?? "0%"
}

private func formatETA(_ torrent: Torrent) -> String {
    if torrent.progress >= 1 {
        return "Done"
    }
    if torrent.desiredState == .paused {
        return "Paused"
    }
    guard let seconds = torrent.etaSeconds else {
        return "Unknown"
    }
    return formatDuration(seconds)
}

private func formatDuration(_ seconds: UInt64) -> String {
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
