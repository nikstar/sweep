import Foundation

enum IOSBackupExclusion {
    static func excludeItem(atPath path: String) {
        excludeItem(at: URL(filePath: path, directoryHint: .isDirectory))
    }

    static func excludeItem(at url: URL) {
        var url = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? url.setResourceValues(resourceValues)
    }
}
