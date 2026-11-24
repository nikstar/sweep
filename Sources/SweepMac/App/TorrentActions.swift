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

    static func open(_ file: TorrentFile, in torrent: Torrent, store: TorrentStore) {
        guard let url = TorrentFileLocation.openableFileURL(
            for: file, in: torrent, defaultDirectory: store.downloadDirectory
        ) else {
            store.lastError = "The file \(file.name) is not available on disk yet."
            return
        }
        // Pass the original payload to the default app, including growing files.
        store.lastError = NSWorkspace.shared.open(url)
            ? nil : "Could not open \(file.name). Choose a compatible app in Finder."
    }

    static func togglePause(_ torrent: Torrent, in store: TorrentStore) {
        store.togglePause(torrent)
    }

    static func remove(_ torrent: Torrent?, in store: TorrentStore, deleteData: Bool = false) {
        guard let torrent, let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.sheetParent == nil, window.attachedSheet == nil else { return }
        let undoManager = window.undoManager

        func performRemoval() {
            Task {
                guard let removal = await store.removeTorrent(id: torrent.id, deleteData: deleteData) else { return }
                undoManager?.registerUndo(withTarget: store) { target in
                    Task { await target.restoreRemovedTorrent(removal) }
                }
                undoManager?.setActionName("Remove Torrent")
            }
        }

        guard deleteData || !torrent.isDownloadFinished else {
            performRemoval()
            return
        }

        let alert = NSAlert()
        alert.messageText = deleteData
            ? "Delete “\(torrent.name)” and its downloaded files?"
            : "Remove unfinished torrent “\(torrent.name)”?"
        alert.informativeText = deleteData
            ? "Downloaded files will be deleted from disk. This cannot be undone."
            : "Removing this transfer keeps its downloaded files on disk."
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let remove = alert.addButton(withTitle: deleteData ? "Delete Torrent and Files" : "Remove Torrent")
        remove.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { performRemoval() }
        }
    }
}
