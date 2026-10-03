import SwiftUI
import SweepCore

public struct TorrentStatusIcon: View {
    let torrent: Torrent
    let isSelected: Bool

    let fontSize: CGFloat

    public init(torrent: Torrent, isSelected: Bool = false, fontSize: CGFloat = 11) {
        self.torrent = torrent
        self.isSelected = isSelected
        self.fontSize = fontSize
    }

    public var body: some View {
        Image(systemName: status.systemImage)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(statusColor)
            .help(status.help)
            .accessibilityLabel(status.help)
    }

    private var statusColor: Color {
        if isSelected, status.usesSelectionColor {
            return .primary
        }
        return status.color
    }

    private var status: (systemImage: String, color: Color, help: String, usesSelectionColor: Bool) {
        if torrent.error != nil {
            return ("exclamationmark.circle.fill", .red, "Error", false)
        }
        if torrent.desiredState == .paused || torrent.isPausedInEngine {
            return ("circle.fill", .secondary, "Paused", false)
        }
        if torrent.state == "initializing" || torrent.state == "restoring" {
            return ("arrow.trianglehead.2.clockwise", .secondary, torrent.statusLabel, false)
        }
        if torrent.progress >= 1 {
            if torrent.uploadBps > 1 {
                return ("arrow.up.circle.fill", .green, "Seeding", true)
            }
            return ("checkmark.circle.fill", .green, "Complete", true)
        }
        if torrent.downloadBps > 1 {
            return ("arrow.down.circle.fill", .blue, "Downloading", true)
        }
        return ("circle.dotted", .secondary, "Waiting", false)
    }
}
