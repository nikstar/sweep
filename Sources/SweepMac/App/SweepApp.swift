import SwiftUI
import SweepCore
import SweepRQBitBridge

@main
struct SweepApp: App {
    @StateObject private var store = TorrentStore(engine: AppEnvironment.makeTorrentEngine())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 500)
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView(engineName: store.engineName)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Magnet Link...") {
                    store.showingAddSheet = true
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("Transfers") {
                Button("Refresh") {
                    store.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            SidebarCommands()
        }
    }
}

private enum AppEnvironment {
    static func makeTorrentEngine() -> TorrentEngine {
        RqbitEngine.makeDefault() ?? DemoTorrentEngine()
    }
}
