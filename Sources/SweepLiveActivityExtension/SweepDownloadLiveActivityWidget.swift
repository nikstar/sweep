import ActivityKit
import SwiftUI
import SweepActivities
import WidgetKit

struct SweepDownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SweepDownloadActivityAttributes.self) { context in
            SweepActivityCard(state: context.state, isStale: context.isStale)
            // Keep the system background: it adapts to the Lock Screen, Dark Mode, and StandBy.
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Sweep", systemImage: context.state.displayPhase.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activityTint(context.state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityPercent(state: context.state)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.headline)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1).truncationMode(.middle)
                        ActivityProgress(state: context.state)
                        HStack {
                            Text(context.isStale ? "Open Sweep to update" : context.state.detail)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if !context.isStale, context.state.displayPhase.isActive {
                                Label(ActivityBytes.rate(context.state.downloadBps), systemImage: "arrow.down")
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "clock" : context.state.displayPhase.symbol)
                    .foregroundStyle(activityTint(context.state))
            } compactTrailing: {
                ActivityPercent(state: context.state)
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: context.isStale ? "clock" : context.state.displayPhase.symbol)
                    .foregroundStyle(activityTint(context.state))
            }
            .keylineTint(activityTint(context.state))
        }
    }
}

private struct SweepActivityCard: View {
    let state: SweepDownloadActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isStale ? "clock" : state.displayPhase.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(activityTint(state))
                    .frame(width: 34, height: 34)
                    .background(activityTint(state).opacity(0.12), in: .rect(cornerRadius: 9))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sweep")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(state.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                ActivityPercent(state: state)
                    .font(.title3.weight(.semibold))
                    .layoutPriority(1)
            }

            ActivityProgress(state: state)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isStale ? "Open Sweep to update" : state.detail)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(byteSummary)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).monospacedDigit()
                }
                Spacer(minLength: 0)
                if !isStale, state.displayPhase.isActive {
                    VStack(alignment: .trailing, spacing: 3) {
                        Label(ActivityBytes.rate(state.downloadBps), systemImage: "arrow.down")
                        Label(ActivityBytes.rate(state.uploadBps), systemImage: "arrow.up")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    .monospacedDigit().fixedSize()
                }
            }
        }
        // Apple's Lock Screen Live Activity margin is 14 pt; the system owns the outer shape.
        .padding(14)
        .foregroundStyle(.primary)
    }

    private var byteSummary: String {
        if state.totalBytes == 0 { return "Size not yet known" }
        return "\(ActivityBytes.bytes(state.progressBytes)) of \(ActivityBytes.bytes(state.totalBytes))"
    }
}

private struct ActivityPercent: View {
    let state: SweepDownloadActivityAttributes.ContentState
    var body: some View {
        Text(state.isIndeterminate ? "…" : "\(state.percentComplete)%")
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityLabel(state.isIndeterminate ? "Size not yet known" : "\(state.percentComplete) percent downloaded")
    }
}

private struct ActivityProgress: View {
    let state: SweepDownloadActivityAttributes.ContentState
    var body: some View {
        if state.isIndeterminate {
            Capsule().fill(.secondary.opacity(0.18)).frame(height: 4)
                .accessibilityLabel("Waiting for torrent metadata")
        } else {
            ProgressView(value: state.progress)
                .progressViewStyle(.linear)
                .tint(activityTint(state))
                .accessibilityLabel("Downloaded")
        }
    }
}

private func activityTint(_ state: SweepDownloadActivityAttributes.ContentState) -> Color {
    switch state.displayPhase {
    case .completed: .green
    case .paused: .orange
    case .failed: .red
    case .stopped: .secondary
    default: .blue
    }
}

private enum ActivityBytes {
    static func bytes(_ bytes: UInt64) -> String {
        bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
    static func rate(_ bytesPerSecond: Double) -> String {
        let finite = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        return "\(bytes(UInt64(min(finite, Double(Int64.max)))))/s"
    }
}

#Preview("Downloading", as: .content, using: SweepDownloadActivityAttributes(activityID: "preview", title: "Sweep")) {
    SweepDownloadLiveActivityWidget()
} contentStates: {
    SweepDownloadActivityAttributes.ContentState(
        headline: "Ubuntu Desktop.iso", detail: "Downloading", activeDownloadCount: 1,
        progress: 0.42, progressBytes: 420_000_000, totalBytes: 1_000_000_000,
        downloadBps: 2_400_000, uploadBps: 160_000, isIndeterminate: false,
        updatedAt: .now, phase: .downloading, torrentIDs: ["preview"]
    )
}
