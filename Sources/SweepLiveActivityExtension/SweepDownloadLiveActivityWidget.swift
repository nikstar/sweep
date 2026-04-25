import ActivityKit
import SwiftUI
import SweepActivities
import WidgetKit

struct SweepDownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SweepDownloadActivityAttributes.self) { context in
            SweepLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SweepLiveActivityTitle(state: context.state)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    SweepLiveActivityRates(state: context.state, isCompact: true)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    SweepLiveActivityProgress(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.isIndeterminate ? "--" : "\(context.state.percentComplete)%")
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            } minimal: {
                Image(systemName: "arrow.down")
                    .foregroundStyle(.blue)
            }
            .keylineTint(.blue)
        }
    }
}

private struct SweepLiveActivityLockScreenView: View {
    let context: ActivityViewContext<SweepDownloadActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SweepLiveActivityTitle(state: context.state)

                Spacer(minLength: 8)

                if !context.state.isIndeterminate {
                    Text("\(context.state.percentComplete)%")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            SweepLiveActivityProgress(state: context.state)

            HStack(spacing: 14) {
                SweepLiveActivityRates(state: context.state)

                Spacer(minLength: 8)

                if context.state.activeDownloadCount > 1 {
                    Label("\(context.state.activeDownloadCount)", systemImage: "arrow.down.square.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}

private struct SweepLiveActivityTitle: View {
    let state: SweepDownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.headline)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(state.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct SweepLiveActivityProgress: View {
    let state: SweepDownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if state.isIndeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }

            HStack {
                Text(ByteCountFormat.bytes(state.progressBytes))
                Spacer(minLength: 8)
                Text(state.totalBytes > 0 ? ByteCountFormat.bytes(state.totalBytes) : "Unknown")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

private struct SweepLiveActivityRates: View {
    let state: SweepDownloadActivityAttributes.ContentState
    var isCompact = false

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .trailing, spacing: 2) {
                    rateLabel(ByteCountFormat.rate(state.downloadBps), systemImage: "arrow.down")
                    rateLabel(ByteCountFormat.rate(state.uploadBps), systemImage: "arrow.up")
                }
            } else {
                HStack(spacing: 8) {
                    rateLabel(ByteCountFormat.rate(state.downloadBps), systemImage: "arrow.down")
                    rateLabel(ByteCountFormat.rate(state.uploadBps), systemImage: "arrow.up")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func rateLabel(_ value: String, systemImage: String) -> some View {
        Label(value, systemImage: systemImage)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private enum ByteCountFormat {
    private static func makeFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesActualByteCount = false
        return formatter
    }

    static func bytes(_ bytes: UInt64) -> String {
        let formatter = makeFormatter()
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        "\(bytes(UInt64(max(bytesPerSecond, 0))))/s"
    }
}
