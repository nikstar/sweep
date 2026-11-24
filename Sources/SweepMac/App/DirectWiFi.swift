import AppKit
import Observation
import ServiceManagement
import Security
import SweepCore
import SweepRQBitBridge

@MainActor
@Observable
final class MacNetworkSession {
    private static let preference = "directWiFi"
    private static let serviceName = "me.nikstar.sweep.wifi"
    private let service = SMAppService.daemon(plistName: serviceName + ".plist")

    private(set) var directRequested = UserDefaults.standard.bool(forKey: preference)
    private(set) var store: TorrentStore
    private(set) var message: String?
    private(set) var needsApproval = false
    private(set) var connecting = false
    private(set) var mustRelaunch = false
    @ObservationIgnored private var repairedRegistration = false
    let directAtLaunch: Bool

    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var engine: RqbitEngine?

    init() {
        directAtLaunch = UserDefaults.standard.bool(forKey: Self.preference)
        if directAtLaunch {
            store = TorrentStoreFactory.make(defaultDownloadDirectory: Self.downloads, makeEngine: nil)
        } else {
            store = TorrentStoreFactory.make(defaultDownloadDirectory: Self.downloads) { directory in
                try RqbitEngine(downloadDirectory: directory)
            }
        }
    }

    func selectDirect(_ enabled: Bool) {
        message = nil
        directRequested = enabled
        UserDefaults.standard.set(enabled, forKey: Self.preference)
        if enabled {
            if directAtLaunch && store.isWaitingForEngine && !mustRelaunch {
                start()
            } else {
                prepareHelper()
            }
        } else {
            needsApproval = false
        }
    }

    func prepareHelper() {
        do {
            switch service.status {
            case .enabled, .requiresApproval: break
            default: try service.register()
            }
            refreshApproval()
        } catch {
            refreshApproval()
            if !needsApproval { message = error.localizedDescription }
        }
    }

    func refreshApproval() {
        needsApproval = directRequested && service.status == .requiresApproval
    }

    func openApproval() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func start() {
        guard directAtLaunch, directRequested, !mustRelaunch, !connecting, store.isWaitingForEngine, connection == nil else { return }
        prepareHelper()
        guard service.status == .enabled else {
            if !needsApproval && message == nil {
                message = "macOS could not register the Wi-Fi helper. Run Sweep from Applications and retry."
            }
            return
        }
        connecting = true
        message = nil
        guard let requirement = Self.helperRequirement() else {
            connecting = false
            message = "The bundled Wi-Fi helper’s signature is unavailable."
            return
        }
        let client = NSXPCConnection(machServiceName: Self.serviceName, options: .privileged)
        client.setCodeSigningRequirement(requirement)
        client.remoteObjectInterface = NSXPCInterface(with: SweepWiFiService.self)
        client.invalidationHandler = { @Sendable [weak self, weak client] in
            Task { @MainActor in self?.linkClosed(client) }
        }
        client.interruptionHandler = { @Sendable [weak client] in client?.invalidate() }
        connection = client
        client.resume()
        let proxy = client.remoteObjectProxyWithErrorHandler { @Sendable [weak self, weak client] error in
            let nsError = error as NSError
            let staleHelper = nsError.domain == NSCocoaErrorDomain && nsError.code == NSXPCConnectionCodeSigningRequirementFailure
            Task { @MainActor in
                self?.connectionFailed(client, reason: error.localizedDescription, staleHelper: staleHelper)
            }
        } as? SweepWiFiService
        guard let proxy else {
            failed(client, reason: "Could not connect to the approved Wi-Fi helper.")
            return
        }
        proxy.openLink { @Sendable [weak self, weak client] name, error in
            Task { @MainActor in
                guard let self, let client, self.connection === client else { return }
                guard let name, if_nametoindex(name) != 0 else {
                    self.failed(client, reason: error ?? "The Wi-Fi interface is unavailable.")
                    return
                }
                do {
                    let directory = self.store.downloadDirectory
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    let engine = try RqbitEngine(downloadDirectory: directory, bindInterface: name)
                    self.engine = engine
                    self.store.startTransfers(with: engine)
                    self.connecting = false
                } catch {
                    self.failed(client, reason: error.localizedDescription)
                }
            }
        }
    }

    // An updated app can encounter a still-running copy of the previous daemon.
    // Compare its live signature to the embedded executable before giving it any transfers.
    private static func helperRequirement() -> String? {
        let path = Bundle.main.bundleURL.appending(path: "Contents/MacOS/SweepWiFiHelper")
        let hashes = ["arm64", "x86_64"].compactMap { architecture -> String? in
            var code: SecStaticCode?
            var info: CFDictionary?
            let attributes = [kSecCodeAttributeArchitecture: architecture] as CFDictionary
            guard SecStaticCodeCreateWithPathAndAttributes(path as CFURL, [], attributes, &code) == errSecSuccess,
                  let code,
                  SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let digest = (info as NSDictionary?)?[kSecCodeInfoUnique] as? Data, digest.count == 20
            else { return nil }
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return "cdhash H\"\(hex)\""
        }
        guard !hashes.isEmpty else { return nil }
        let requirement = "anchor apple generic and identifier \"me.nikstar.sweep.wifi\" and certificate leaf[subject.OU] = \"6RX8GEVB43\" and (\(hashes.joined(separator: " or ")))"
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else { return nil }
        return requirement
    }

    private func connectionFailed(_ client: NSXPCConnection?, reason: String, staleHelper: Bool) {
        guard let client, connection === client else { return }
        failed(client, reason: reason)
        guard staleHelper, !repairedRegistration, service.status == .enabled else { return }
        repairedRegistration = true
        connecting = true
        service.unregister { @Sendable [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.connecting = false
                if let error { self.message = error.localizedDescription; return }
                // smd can finish removing the old job just after unregister returns.
                for delay in [1, 2, 4] {
                    try? await Task.sleep(for: .seconds(delay))
                    guard self.directRequested, self.connection == nil else { return }
                    self.start()
                    if self.needsApproval || self.service.status == .enabled { return }
                }
            }
        }
    }

    private func failed(_ client: NSXPCConnection?, reason: String) {
        guard let client, connection === client else { return }
        connection = nil
        connecting = false
        message = reason
        client.invalidate()
    }

    private func linkClosed(_ client: NSXPCConnection?) {
        guard let client, connection === client else { return }
        guard let engine else {
            // An outstanding openLink request receives a more specific error, including
            // a code-signature mismatch after an update, on the proxy's error handler.
            return
        }
        connection = nil
        connecting = false
        engine.cancelNetwork()
        mustRelaunch = true
        message = "The direct Wi-Fi link closed. Relaunch Sweep to reconnect."
        store = TorrentStoreFactory.make(defaultDownloadDirectory: Self.downloads, makeEngine: nil)
        self.engine = nil
    }

    func relaunch() {
        // Wait for the old process to close its database and sockets before opening the new session.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; exec /usr/bin/open \"$2\"", "sweep", String(getpid()), Bundle.main.bundlePath]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch { message = error.localizedDescription }
    }

    private static var downloads: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appending(path: "Sweep", directoryHint: .isDirectory).path
    }
}
