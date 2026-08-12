import Foundation

/// Writes that either land completely or not at all.
///
/// A save file half-written is a save file destroyed, so every write goes to a temporary
/// file in the same directory first and is then swapped into place by the filesystem.
public enum AtomicFile {

    /// Write `data` to `url`, replacing any existing file in a single atomic step.
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        // .atomic forces the data fully to the temporary file before we swap.
        try data.write(to: temporary, options: .atomic)

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Copy every regular file from one directory into another, replacing what's there.
    /// Used by snapshot and restore, which both move whole folders.
    @discardableResult
    public static func copyDirectoryContents(from source: URL, to destination: URL) throws -> [String] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let names = try fileManager.contentsOfDirectory(atPath: source.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()

        var copied: [String] = []
        for name in names {
            let from = source.appendingPathComponent(name)
            guard (try? from.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            try write(try Data(contentsOf: from), to: destination.appendingPathComponent(name))
            copied.append(name)
        }
        return copied
    }
}
