import AppKit
import SwiftUI
import SweepCore

struct TorrentListView: View {
    @EnvironmentObject private var store: TorrentStore
    @EnvironmentObject private var inspectorPanelPresenter: TorrentInspectorPanelPresenter
    @Binding var confirmingRemoveData: Bool
    @SceneStorage("Sweep.TorrentList.columnCustomization")
    private var columnCustomization = TableColumnCustomization<Torrent>()
    @SceneStorage("Sweep.TorrentList.progressColumnMode")
    private var progressColumnModeRaw = ProgressColumnMode.detailed.rawValue

    init(confirmingRemoveData: Binding<Bool> = .constant(false)) {
        self._confirmingRemoveData = confirmingRemoveData
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(
                store.torrents,
                selection: $store.selection,
                columnCustomization: $columnCustomization
            ) {
                TableColumn("Name") { torrent in
                    TorrentNameCell(torrent: torrent)
                        .environmentObject(store)
                }
                .width(min: 320, ideal: 420)
                .customizationID("name")
                .disabledCustomizationBehavior(.visibility)

                TableColumn("Progress") { torrent in
                    TorrentProgressCell(
                        torrent: torrent,
                        mode: progressColumnMode,
                        onOptionClick: toggleProgressColumnMode
                    )
                }
                .width(min: 140, ideal: 170)
                .customizationID("progress")
                .disabledCustomizationBehavior(.visibility)

                TableColumn("Size") { torrent in
                    Text(ByteFormatter.bytes(torrent.totalBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)
                .customizationID("size")

                TableColumn("ETA") { torrent in
                    Text(formatETA(torrent))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 90)
                .customizationID("eta")
                .defaultVisibility(.hidden)

                TableColumn("%") { torrent in
                    Text(formatPercent(torrent.progress))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 54, ideal: 64)
                .customizationID("percent")

                TableColumn("Remaining") { torrent in
                    Text(ByteFormatter.bytes(torrent.remainingBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 92, ideal: 112)
                .customizationID("remaining")

                TableColumn("Speed") { torrent in
                    VStack(alignment: .leading, spacing: 2) {
                        TransferRateLine(systemImage: "arrow.down", value: torrent.downloadBps)
                        TransferRateLine(systemImage: "arrow.up", value: torrent.uploadBps)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 92, ideal: 112)
                .customizationID("speed")

                TableColumn("Peers") { torrent in
                    PeerColumnCell(torrent: torrent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .width(min: 86, ideal: 104)
                .customizationID("peers")
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
                .disabled(store.selectedTorrent == nil)

                Divider()

                Button("Remove") {
                    store.removeSelectedTorrent()
                }
                .disabled(store.selectedTorrent == nil)

                Button("Remove and Delete Data") {
                    confirmingRemoveData = true
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

    private var progressColumnMode: ProgressColumnMode {
        ProgressColumnMode(rawValue: progressColumnModeRaw) ?? .detailed
    }

    private func toggleProgressColumnMode() {
        progressColumnModeRaw = progressColumnMode == .detailed
            ? ProgressColumnMode.barOnly.rawValue
            : ProgressColumnMode.detailed.rawValue
    }
}

private enum ProgressColumnMode: String {
    case detailed
    case barOnly
}

private struct PeerColumnCell: View {
    let torrent: Torrent

    var body: some View {
        let summary = PeerColumnSummary(torrent: torrent)
        VStack(alignment: .leading, spacing: 2) {
            PeerCountLine(systemImage: "arrow.up", active: summary.activeSeeders, total: summary.totalSeeders)
            PeerCountLine(systemImage: "arrow.down", active: summary.activeLeechers, total: summary.totalLeechers)
        }
    }
}

private struct PeerCountLine: View {
    let systemImage: String
    let active: Int
    let total: UInt32?

    var body: some View {
        Label {
            Text(total.map { "\(active) (\($0))" } ?? "\(active) (-)")
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct PeerColumnSummary {
    let activeSeeders: Int
    let activeLeechers: Int
    let totalSeeders: UInt32?
    let totalLeechers: UInt32?

    init(torrent: Torrent) {
        self.activeSeeders = torrent.peers.filter { ($0.availability ?? 0) >= 1 }.count
        self.activeLeechers = torrent.peers.count - activeSeeders
        self.totalSeeders = torrent.trackers.compactMap(\.seeders).max()
        self.totalLeechers = torrent.trackers.compactMap(\.leechers).max()
    }
}

private struct TorrentNameCell: View {
    @EnvironmentObject private var store: TorrentStore
    @State private var isHovering = false

    let torrent: Torrent

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TorrentStatusIcon(torrent: torrent)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(torrent.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 7) {
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
                    .opacity(isHovering || store.selection == torrent.id ? 1 : 0.72)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(torrent.error == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 3)
        .onHover { isHovering = $0 }
    }

    private var statusText: String {
        if let error = torrent.error, !error.isEmpty {
            return error
        }

        var parts = [torrent.statusLabel]

        if torrent.totalBytes > 0 {
            parts.append("\(formatPercent(torrent.progress)) of \(ByteFormatter.bytes(torrent.totalBytes))")
        } else {
            parts.append("Waiting for metadata")
        }

        if torrent.remainingBytes > 0 {
            parts.append("\(ByteFormatter.bytes(torrent.remainingBytes)) remaining")
        }

        if let eta = torrent.etaSeconds {
            parts.append("\(formatDuration(eta)) left")
        }

        if torrent.downloadBps > 1 {
            parts.append("\(ByteFormatter.rate(torrent.downloadBps)) down")
        }

        if torrent.uploadBps > 1 {
            parts.append("\(ByteFormatter.rate(torrent.uploadBps)) up")
        }

        if !torrent.peers.isEmpty {
            let peerText = torrent.peers.count == 1 ? "1 peer" : "\(torrent.peers.count) peers"
            parts.append(peerText)
        }

        return parts.joined(separator: " - ")
    }
}

private struct TorrentStatusIcon: View {
    let torrent: Torrent

    var body: some View {
        Image(systemName: status.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status.color)
            .frame(width: 16, height: 30)
            .help(status.help)
    }

    private var status: (systemImage: String, color: Color, help: String) {
        if torrent.error != nil {
            return ("exclamationmark.circle.fill", .red, "Error")
        }
        if torrent.desiredState == .paused || torrent.isPausedInEngine {
            return ("circle.fill", .secondary, "Paused")
        }
        if torrent.progress >= 1 {
            if torrent.uploadBps > 1 {
                return ("arrow.up.circle.fill", .green, "Seeding")
            }
            return ("checkmark.circle.fill", .green, "Complete")
        }
        if torrent.downloadBps > 1 {
            return ("arrow.down.circle.fill", .blue, "Downloading")
        }
        return ("circle.dotted", .secondary, "Waiting")
    }
}

private struct TorrentProgressCell: View {
    let torrent: Torrent
    let mode: ProgressColumnMode
    let onOptionClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SegmentedProgressView(
                runs: torrent.pieceRuns,
                fallbackProgress: torrent.progress,
                state: torrent.statusLabel,
                height: mode == .barOnly ? 16 : 8
            )
            if mode == .detailed {
                HStack(spacing: 4) {
                    Text(formatPercent(torrent.progress))
                    if torrent.remainingBytes > 0 {
                        Text(ByteFormatter.bytes(torrent.remainingBytes))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) {
                onOptionClick()
            }
        }
    }
}

struct SegmentedProgressView: View {
    let runs: [TorrentPieceRun]
    let fallbackProgress: Double
    let state: String
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(trackColor)

                HStack(spacing: 0) {
                    ForEach(displayRuns) { run in
                        Rectangle()
                            .fill(color(for: run.state))
                            .frame(width: width(for: run, totalWidth: proxy.size.width))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))

                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 0.5)
            }
        }
        .frame(height: height)
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
            statusFillColor
        case .downloading:
            .cyan
        case .needed:
            Color.secondary.opacity(0.24)
        case .skipped:
            Color.secondary.opacity(0.10)
        case .unknown:
            Color.secondary.opacity(0.14)
        }
    }

    private var statusFillColor: Color {
        if state == "Complete" {
            return .green
        }
        if state == "Paused" || state == "Pausing" {
            return .secondary
        }
        if state == "Error" {
            return .red
        }
        return .blue
    }

    private var trackColor: Color {
        if state == "Error" {
            return Color.red.opacity(0.10)
        }
        return Color.secondary.opacity(0.14)
    }
}

private struct TransferRateLine: View {
    let systemImage: String
    let value: Double

    var body: some View {
        Label {
            Text(ByteFormatter.rate(value))
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2)
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(value > 1 ? .primary : .secondary)
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
