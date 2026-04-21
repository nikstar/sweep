import Darwin
import Foundation
import SweepCore

final class RqbitBridge {
    private typealias CreateFn = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> OpaquePointer?
    private typealias DestroyFn = @convention(c) (OpaquePointer?) -> Void
    private typealias AddMagnetFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Bool
    private typealias ListFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Bool
    private typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let createFn: CreateFn
    private let destroyFn: DestroyFn
    private let addMagnetFn: AddMagnetFn
    private let listFn: ListFn
    private let freeFn: FreeFn
    private let decoder = JSONDecoder()

    static func loadDefault() -> RqbitBridge? {
        let bundleCandidates = [
            Bundle.main.privateFrameworksURL?.appending(path: "libsweep_rqbit.dylib"),
            Bundle.main.resourceURL?.appending(path: "libsweep_rqbit.dylib")
        ].compactMap { $0?.path }

        let candidates = [
            ProcessInfo.processInfo.environment["SWEEP_RQBIT_DYLIB_PATH"],
            bundleCandidates.first,
            bundleCandidates.dropFirst().first,
            "rust/target/debug/libsweep_rqbit.dylib",
            "rust/target/release/libsweep_rqbit.dylib",
            "target/debug/libsweep_rqbit.dylib",
            "target/release/libsweep_rqbit.dylib"
        ].compactMap(\.self)

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for candidate in candidates {
            let path = candidate.hasPrefix("/") ? candidate : root.appending(path: candidate).path
            if FileManager.default.fileExists(atPath: path), let bridge = try? RqbitBridge(path: path) {
                return bridge
            }
        }
        return nil
    }

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw BridgeError.load(String(cString: dlerror()))
        }
        self.handle = handle
        self.createFn = try Self.symbol(handle, "sweep_client_create")
        self.destroyFn = try Self.symbol(handle, "sweep_client_destroy")
        self.addMagnetFn = try Self.symbol(handle, "sweep_client_add_magnet")
        self.listFn = try Self.symbol(handle, "sweep_client_list")
        self.freeFn = try Self.symbol(handle, "sweep_string_free")
    }

    deinit {
        dlclose(handle)
    }

    func createClient(downloadDirectory: String) throws -> OpaquePointer {
        var error: UnsafeMutablePointer<CChar>?
        guard let client = downloadDirectory.withCString({ createFn($0, &error) }) else {
            throw BridgeError.operation(takeString(error))
        }
        return client
    }

    func destroyClient(_ client: OpaquePointer) {
        destroyFn(client)
    }

    func addMagnet(client: OpaquePointer, magnet: String) throws -> AddTorrentResponse {
        let json = try callWithJSON { out, error in
            magnet.withCString { addMagnetFn(client, $0, out, error) }
        }
        return try decoder.decode(AddTorrentResponse.self, from: Data(json.utf8))
    }

    func list(client: OpaquePointer) throws -> [Torrent] {
        let json = try callWithJSON { out, error in
            listFn(client, out, error)
        }
        return try decoder.decode([Torrent].self, from: Data(json.utf8))
    }

    private func callWithJSON(_ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Bool) throws -> String {
        var json: UnsafeMutablePointer<CChar>?
        var error: UnsafeMutablePointer<CChar>?
        guard body(&json, &error) else {
            throw BridgeError.operation(takeString(error))
        }
        return takeString(json)
    }

    private func takeString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "Unknown rqbit bridge error" }
        let value = String(cString: pointer)
        freeFn(pointer)
        return value
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
        guard let pointer = dlsym(handle, name) else {
            throw BridgeError.load("Missing symbol \(name)")
        }
        return unsafeBitCast(pointer, to: T.self)
    }
}

enum BridgeError: LocalizedError {
    case load(String)
    case operation(String)

    var errorDescription: String? {
        switch self {
        case .load(let message):
            "Could not load rqbit bridge: \(message)"
        case .operation(let message):
            message
        }
    }
}
