import AVKit
import Observation
import SwiftUI

struct IOSMediaFile: Identifiable {
    let url: URL
    let name: String
    var id: URL { url }
}

struct IOSMediaPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let file: IOSMediaFile
    @State private var playback = IOSMediaPlayback()

    var body: some View {
        NavigationStack {
            Group {
                if let message = playback.failure {
                    ContentUnavailableView {
                        Label("Open in Another Player", systemImage: "play.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Open in Another App…", systemImage: "square.and.arrow.up") {
                            if !IOSOpenInPresenter.shared.present(url: file.url) {
                                playback.failure = "The sharing menu could not be opened. Close the player and try again."
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else if let player = playback.player {
                    IOSNativePlayer(player: player)
                } else {
                    ProgressView("Opening video…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: file.url) { Label("Open in Another App", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: file.id) { await playback.open(file.url) }
        .onDisappear { playback.stop() }
    }
}

@MainActor @Observable
private final class IOSMediaPlayback {
    private(set) var player: AVPlayer?
    var failure: String?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    func open(_ url: URL) async {
        do {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable) else {
                failure = "This video's format isn't supported by the built-in player. Open it in a compatible app installed on your iPhone."
                return
            }
            try Task.checkCancellation()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: .mixWithOthers)
            try session.setActive(true)
            let item = AVPlayerItem(asset: asset)
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let message = item.error?.localizedDescription ?? "This video could not be played. Try another player."
                Task { @MainActor [weak self] in self?.failure = message }
            }
            let player = AVPlayer(playerItem: item)
            // Playback is foreground-only; background transfer audio owns its own lifecycle.
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            self.player = player
            player.play()
        } catch is CancellationError {
        } catch {
            failure = "This video could not be opened. \(error.localizedDescription)"
        }
    }

    func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        if UIApplication.shared.applicationState == .active {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

private struct IOSNativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
