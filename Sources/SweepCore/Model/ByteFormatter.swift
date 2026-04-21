import Foundation

public enum ByteFormatter {
    private static func makeFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter
    }

    public static func bytes(_ value: UInt64) -> String {
        makeFormatter().string(fromByteCount: Int64(value))
    }

    public static func rate(_ value: Double) -> String {
        "\(makeFormatter().string(fromByteCount: Int64(value)))/s"
    }
}
