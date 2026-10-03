import Foundation

public extension Torrent {
    var canResume: Bool { desiredState == .paused || error != nil }
    var transferActionTitle: String { error != nil ? "Retry" : (canResume ? "Resume" : "Pause") }
    var transferActionSymbol: String { error != nil ? "arrow.clockwise" : (canResume ? "play.fill" : "pause.fill") }
}
