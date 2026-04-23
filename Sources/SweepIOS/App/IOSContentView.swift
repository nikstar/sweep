import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SweepCore

struct IOSContentView: View {
    @Environment(TorrentStore.self) private var store

    @State private var isImportingTorrent = false
    @State private var confirmingRemoveData = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Group {
                if store.torrents.isEmpty {
                    ContentUnavailableView {
                        Label("No Torrents", systemImage: "tray")
                    } actions: {
                        Button {
                            isImportingTorrent = true
                        } label: {
                            Label("Add File", systemImage: "doc.badge.plus")
                        }

                        Button {
                            store.beginAddingMagnet("")
                        } label: {
                            Label("Add URL", systemImage: "link.badge.plus")
                        }
                    }
                } else {
                    List {
                        ForEach(store.torrents) { torrent in
                            NavigationLink {
                                IOSTorrentInspectorView(torrentID: torrent.id)
                                    .environment(store)
                            } label: {
                                IOSTorrentRow(torrent: torrent)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                store.selection = torrent.id
                            })
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    togglePause(torrent)
                                } label: {
                                    Label(
                                        torrent.desiredState == .paused ? "Resume" : "Pause",
                                        systemImage: torrent.desiredState == .paused ? "play.fill" : "pause.fill"
                                    )
                                }
                                .tint(torrent.desiredState == .paused ? .green : .orange)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    store.removeSelectedTorrent()
                                } label: {
                                    Label("Remove", systemImage: "xmark")
                                }

                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    confirmingRemoveData = true
                                } label: {
                                    Label("Delete Data", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    togglePause(torrent)
                                } label: {
                                    Label(
                                        torrent.desiredState == .paused ? "Resume" : "Pause",
                                        systemImage: torrent.desiredState == .paused ? "play.fill" : "pause.fill"
                                    )
                                }

                                Button {
                                    store.selection = torrent.id
                                    store.refresh()
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    store.removeSelectedTorrent()
                                } label: {
                                    Label("Remove", systemImage: "xmark")
                                }

                                Button(role: .destructive) {
                                    store.selection = torrent.id
                                    confirmingRemoveData = true
                                } label: {
                                    Label("Delete Data", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await store.refreshNow()
                    }
                }
            }
            .navigationTitle("Sweep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isImportingTorrent = true
                        } label: {
                            Label("Add File", systemImage: "doc.badge.plus")
                        }

                        Button {
                            store.beginAddingMagnet("")
                        } label: {
                            Label("Add URL", systemImage: "link.badge.plus")
                        }

                        Button {
                            addFromClipboard()
                        } label: {
                            Label("Add from Clipboard", systemImage: "doc.on.clipboard")
                        }

                        Divider()

                        Button {
                            store.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                IOSSessionStatusBar()
                    .environment(store)
            }
            .fileImporter(
                isPresented: $isImportingTorrent,
                allowedContentTypes: [torrentContentType],
                allowsMultipleSelection: false,
                onCompletion: importTorrentFile
            )
            .sheet(isPresented: $store.showingAddSheet) {
                IOSAddTorrentSheet(
                    source: store.pendingAddSource,
                    downloadDirectory: store.downloadDirectory
                )
                .environment(store)
            }
            .removeTorrentDataConfirmation(isPresented: $confirmingRemoveData, store: store)
            .task {
                store.startPolling()
            }
        }
    }

    private var torrentContentType: UTType {
        UTType(filenameExtension: "torrent") ?? .data
    }

    private func importTorrentFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            store.beginAddingTorrentFile(try TorrentFileSource(contentsOf: url))
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func addFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.lowercased().hasPrefix("magnet:")
        else {
            store.lastError = "Clipboard does not contain a magnet link."
            return
        }
        store.beginAddingMagnet(text)
    }

    private func togglePause(_ torrent: Torrent) {
        store.selection = torrent.id
        if torrent.desiredState == .paused {
            store.resumeSelectedTorrent()
        } else {
            store.pauseSelectedTorrent()
        }
    }
}

private struct IOSTorrentRow: View {
    let torrent: Torrent

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            IOSTorrentStatusIcon(torrent: torrent)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(torrent.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Text(IOSDisplayFormat.percent(torrent.progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                IOSSegmentedProgressView(
                    runs: torrent.pieceRuns,
                    fallbackProgress: torrent.progress,
                    state: torrent.statusLabel,
                    height: 8
                )

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(torrent.error == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 12) {
                    TransferMetric(systemImage: "arrow.down", value: ByteFormatter.rate(torrent.downloadBps), isActive: torrent.downloadBps > 1)
                    TransferMetric(systemImage: "arrow.up", value: ByteFormatter.rate(torrent.uploadBps), isActive: torrent.uploadBps > 1)
                    PeerMetric(torrent: torrent)
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 5)
    }

    private var statusText: String {
        if let error = torrent.error, !error.isEmpty {
            return error
        }

        var parts = [torrent.statusLabel]
        if torrent.totalBytes > 0 {
            parts.append("\(IOSDisplayFormat.percent(torrent.progress)) of \(ByteFormatter.bytes(torrent.totalBytes))")
        } else {
            parts.append("Waiting for metadata")
        }

        if torrent.remainingBytes > 0 {
            parts.append("\(ByteFormatter.bytes(torrent.remainingBytes)) remaining")
        }
        if let eta = torrent.etaSeconds {
            parts.append("\(IOSDisplayFormat.duration(eta)) left")
        }
        return parts.joined(separator: " - ")
    }
}

private struct IOSTorrentStatusIcon: View {
    let torrent: Torrent

    var body: some View {
        Image(systemName: status.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(status.color)
            .frame(width: 20, height: 40)
            .accessibilityLabel(status.label)
    }

    private var status: (systemImage: String, color: Color, label: String) {
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

private struct TransferMetric: View {
    let systemImage: String
    let value: String
    let isActive: Bool

    var body: some View {
        Label {
            Text(value)
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(isActive ? .primary : .secondary)
    }
}

private struct PeerMetric: View {
    let torrent: Torrent

    var body: some View {
        let livePeers = torrent.peers.filter(\.isLiveConnection)
        Label {
            Text("\(livePeers.count)")
                .monospacedDigit()
        } icon: {
            Image(systemName: "person.2")
        }
        .foregroundStyle(livePeers.isEmpty ? .secondary : .primary)
    }
}

private struct IOSSessionStatusBar: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Label(ByteFormatter.rate(store.sessionStats.downloadBps), systemImage: "arrow.down")
            Label(ByteFormatter.rate(store.sessionStats.uploadBps), systemImage: "arrow.up")
            Label("\(store.sessionStats.livePeers)", systemImage: "person.2")

            Spacer(minLength: 8)

            if let error = store.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let torrent = store.selectedTorrent {
                Text(torrent.statusLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(.bar)
    }
}

extension View {
    func removeTorrentDataConfirmation(
        isPresented: Binding<Bool>,
        store: TorrentStore
    ) -> some View {
        confirmationDialog(
            removeTorrentDataConfirmationTitle(for: store.selectedTorrent),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Torrent and Files", role: .destructive) {
                store.removeSelectedTorrent(deleteData: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded files for this torrent will be deleted from this device.")
        }
    }

    private func removeTorrentDataConfirmationTitle(for torrent: Torrent?) -> String {
        guard let name = torrent?.name else {
            return "Delete the selected torrent and its downloaded files?"
        }
        return "Delete \"\(name)\" and its downloaded files?"
    }
}
