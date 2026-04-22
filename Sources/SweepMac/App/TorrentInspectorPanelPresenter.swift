import AppKit
import Observation
import SwiftUI
import SweepCore

@MainActor
@Observable
final class TorrentInspectorPanelPresenter {
    private(set) var isPresented = false

    @ObservationIgnored
    private var controller: TorrentInspectorWindowController?

    func show(store: TorrentStore) {
        let controller = controller ?? TorrentInspectorWindowController(
            store: store,
            onClose: { [weak self] in
                self?.isPresented = false
            }
        )
        self.controller = controller
        isPresented = true
        controller.show()
    }
}

@MainActor
private final class TorrentInspectorWindowController: NSWindowController, NSWindowDelegate {
    private static let frameAutosaveName = "TorrentInspectorWindow"
    private let onClose: () -> Void

    init(store: TorrentStore, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let hostingController = NSHostingController(
            rootView: TorrentInspectorWindowView()
                .environment(store)
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = "Torrent Inspector"
        panel.contentViewController = hostingController
        panel.contentMinSize = NSSize(width: 430, height: 500)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.tabbingMode = .disallowed
        panel.animationBehavior = .utilityWindow
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            panel.center()
        }
        panel.standardWindowButton(.zoomButton)?.isEnabled = false

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
