import Foundation

/// File locations for recordings and downloaded speech models.
enum MediaStore {
    static var recordingsDirectory: URL {
        directory(named: "Recordings", excludeFromBackup: false)
    }

    /// Where Whisper models are downloaded. Excluded from iCloud backup (they can be re-downloaded).
    static var modelsDirectory: URL {
        directory(named: "Models", excludeFromBackup: true)
    }

    static func url(for fileName: String) -> URL {
        recordingsDirectory.appendingPathComponent(fileName)
    }

    /// Moves a freshly recorded temp file into permanent storage. Returns the stored file name.
    static func importRecording(from tempURL: URL) throws -> String {
        let fileName = "\(UUID().uuidString).\(tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension)"
        let destination = url(for: fileName)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return fileName
    }

    static func deleteRecording(named fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    static func deleteAllRecordings() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? fm.removeItem(at: file) }
    }

    /// Total bytes used by kept recordings.
    static func recordingsSize() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// A unique temp file URL for a new recording.
    static func newTemporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    }

    private static func directory(named name: String, excludeFromBackup: Bool) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if excludeFromBackup {
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
            }
        }
        return url
    }
}
