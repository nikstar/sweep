import SwiftUI
import UIKit
import SweepCore
import SweepUI

struct IOSTorrentTrackersInspector: View {
    let torrent: Torrent

    var body: some View {
        IOSInspectorPane {
            IOSInspectorGroup("Summary") {
                IOSInspectorMetricLine {
                    IOSInspectorMetric("Total", String(torrent.trackers.count))
                    IOSInspectorMetric("Working", String(torrent.trackers.filter { $0.status == "Working" }.count))
                    IOSInspectorMetric("Seeds", TorrentDisplayFormat.optionalCount(torrent.trackers.compactMap(\.seeders).max()))
                    IOSInspectorMetric("Leechers", TorrentDisplayFormat.optionalCount(torrent.trackers.compactMap(\.leechers).max()))
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
