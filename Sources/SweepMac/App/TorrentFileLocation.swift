import AppKit
import SweepCore

extension TorrentFileLocation {
    @MainActor
    static func revealInFinder(torrent: Torrent, defaultDirectory: String) {
        let snapshot = snapshot(for: torrent, defaultDirectory: defaultDirectory)
        NSWorkspace.shared.activateFileViewerSelecting([snapshot.revealURL])
    }

    @MainActor
    static func copyExpectedPath(torrent: Torrent, defaultDirectory: String) {
        let url = expectedItemURL(for: torrent, defaultDirectory: defaultDirectory)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}
