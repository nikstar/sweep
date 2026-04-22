import SwiftUI
import SweepCore

struct TorrentTrackersInspector: View {
    let torrent: Torrent

    var body: some View {
        InspectorPane {
            InspectorGroup("Summary") {
                InspectorMetricLine {
                    InspectorMetric("Total", String(torrent.trackers.count))
                    InspectorMetric("Working", String(torrent.trackers.filter { $0.status == "Working" }.count))
                    InspectorMetric("Seeds", TorrentDisplayFormat.optionalCount(torrent.trackers.compactMap(\.seeders).max()))
                    InspectorMetric("Leechers", TorrentDisplayFormat.optionalCount(torrent.trackers.compactMap(\.leechers).max()))
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
                        Text("Last \(TorrentDisplayFormat.date(lastAnnounceAt))")
                    }
                    if let nextAnnounceAt = tracker.nextAnnounceAt {
                        Text("Next \(TorrentDisplayFormat.date(nextAnnounceAt))")
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
