import SwiftUI
import SweepCore

struct SegmentedProgressView: View {
    let runs: [TorrentPieceRun]
    let fallbackProgress: Double
    let state: String
    var isSelected = false
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
        .accessibilityValue(TorrentDisplayFormat.percent(fallbackProgress))
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
            isSelected ? .secondary : .cyan
        case .needed:
            Color.secondary.opacity(0.24)
        case .skipped:
            Color.secondary.opacity(0.10)
        case .unknown:
            Color.secondary.opacity(0.14)
        }
    }

    private var statusFillColor: Color {
        if isSelected, state != "Paused", state != "Pausing", state != "Error" {
            return .primary
        }
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
