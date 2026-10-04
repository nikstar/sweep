import SwiftUI
import SweepCore

struct IOSTorrentPrimaryActions: View {
    @Environment(TorrentStore.self) private var store
    let torrent: Torrent
    let showFiles: () -> Void
    let play: (TorrentFile) -> Void

    var body: some View {
        let media = TorrentMedia(files: torrent.files)
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions(media) }
                VStack(spacing: 8) { actions(media) }
            }
            if let file = media.primaryVideo {
                if TorrentFileLocation.openableFileURL(for: file, in: torrent, defaultDirectory: store.downloadDirectory) == nil {
                    Text("Play is available once the download creates the file.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if file.progressBytes < file.length {
                    Text("You can play while downloading. Playback may pause until more of the video is available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder private func actions(_ media: TorrentMedia) -> some View {
        if let file = media.primaryVideo {
            Button { play(file) } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
            .disabled(TorrentFileLocation.openableFileURL(for: file, in: torrent, defaultDirectory: store.downloadDirectory) == nil)
            .accessibilityIdentifier("torrent.play")
        } else if !media.videos.isEmpty {
            Button(action: showFiles) {
                Label(media.isSeries ? "Episodes (\(media.videos.count))" : "Videos (\(media.videos.count))",
                      systemImage: "play.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
        }
        Button { store.togglePause(torrent) } label: {
            Label(torrent.transferActionTitle, systemImage: torrent.transferActionSymbol)
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.bordered)
        .disabled(store.engineError != nil)
        .accessibilityIdentifier("torrent.transfer")
    }
}
