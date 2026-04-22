import AppKit
import SwiftUI
import SweepCore

@MainActor
enum TorrentActions {
    static func openTorrent(in store: TorrentStore) {
        guard let url = chooseTorrentFileURL() else { return }
        store.beginAdding(url: url)
    }

    static func addLocationFromPasteboard(in store: TorrentStore) {
        store.beginAddingMagnet(magnetFromPasteboard() ?? "")
    }

    static func addFromClipboard(in store: TorrentStore) {
        if let magnet = magnetFromPasteboard() {
            store.beginAddingMagnet(magnet)
        } else if let url = torrentFileURLFromPasteboard() {
            store.beginAdding(url: url)
        }
    }

    static var canAddFromClipboard: Bool {
        magnetFromPasteboard() != nil || torrentFileURLFromPasteboard() != nil
    }

    static func revealSelectedTorrent(in store: TorrentStore) {
        guard let torrent = store.selectedTorrent else { return }
        reveal(torrent, in: store)
    }

    static func reveal(_ torrent: Torrent, in store: TorrentStore) {
        TorrentFileLocation.revealInFinder(
            torrent: torrent,
            defaultDirectory: store.downloadDirectory
        )
    }

    static func togglePause(_ torrent: Torrent, in store: TorrentStore) {
        store.selection = torrent.id
        if torrent.desiredState == .paused {
            store.resumeSelectedTorrent()
        } else {
            store.pauseSelectedTorrent()
        }
    }

    static func remove(_ torrent: Torrent, in store: TorrentStore) {
        store.selection = torrent.id
        store.removeSelectedTorrent()
    }

    static func requestRemoveData(_ torrent: Torrent, in store: TorrentStore, confirm: () -> Void) {
        store.selection = torrent.id
        confirm()
    }

    static func confirmRemoveSelectedTorrentData(in store: TorrentStore) {
        store.removeSelectedTorrent(deleteData: true)
    }

    static func removeDataConfirmationTitle(for torrent: Torrent?) -> String {
        guard let name = torrent?.name else {
            return "Delete the selected torrent and its downloaded files?"
        }
        return "Delete \"\(name)\" and its downloaded files?"
    }
}

extension View {
    func removeTorrentDataConfirmation(
        isPresented: Binding<Bool>,
        store: TorrentStore
    ) -> some View {
        confirmationDialog(
            TorrentActions.removeDataConfirmationTitle(for: store.selectedTorrent),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Torrent and Files", role: .destructive) {
                TorrentActions.confirmRemoveSelectedTorrentData(in: store)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded files for this torrent will be deleted from disk.")
        }
    }
}
