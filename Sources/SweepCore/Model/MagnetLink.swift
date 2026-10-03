import Foundation

public struct MagnetLink: Sendable {
    public let value: String
    public let infoHash: String
    public let name: String
    public let trackers: [TorrentTracker]

    public init(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              components.scheme?.lowercased() == "magnet" else {
            throw InvalidMagnet()
        }
        let hashes = (components.queryItems ?? []).compactMap { item -> String? in
            guard item.name == "xt", let value = item.value,
                  value.lowercased().hasPrefix("urn:btih:") else { return nil }
            return Self.decodeHash(String(value.dropFirst(9)))
        }
        guard let hash = hashes.first, Set(hashes).count == 1 else { throw InvalidMagnet() }
        // Use the same canonical v1 identity on both sides of the FFI boundary.
        components.scheme = "magnet"
        components.queryItems = components.queryItems?.map { item in
            if item.name == "xt", item.value?.lowercased().hasPrefix("urn:btih:") == true {
                return URLQueryItem(name: "xt", value: "urn:btih:\(hash)")
            }
            return item
        }
        self.value = components.string ?? value
        self.infoHash = hash
        self.name = components.queryItems?.first { $0.name == "dn" }?.value ?? hash
        var seen = Set<String>()
        self.trackers = (components.queryItems ?? []).compactMap { item -> String? in
            guard item.name == "tr", let url = item.value, seen.insert(url).inserted else { return nil }
            return url
        }.enumerated().map { index, url in
            TorrentTracker(id: index, url: url, kind: URL(string: url)?.scheme?.uppercased() ?? "Unknown")
        }
    }

    private static func decodeHash(_ value: String) -> String? {
        let bytes = Array(value.uppercased().utf8)
        if bytes.count == 40, bytes.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) {
            return value.lowercased()
        }
        guard bytes.count == 32 else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var buffer: UInt32 = 0
        var bits = 0
        var decoded: [UInt8] = []
        for byte in bytes {
            guard let digit = alphabet.firstIndex(of: byte) else { return nil }
            buffer = (buffer << 5) | UInt32(digit)
            bits += 5
            if bits >= 8 {
                bits -= 8
                decoded.append(UInt8(truncatingIfNeeded: buffer >> bits))
            }
        }
        return decoded.map { String(format: "%02x", $0) }.joined()
    }
}

private struct InvalidMagnet: LocalizedError {
    var errorDescription: String? { "Enter a magnet link containing a valid BitTorrent v1 info hash." }
}
