import Foundation
import CryptoKit

/// A point-in-time copy of the whole save folder.
public struct BackupManifest: Codable, Sendable, Identifiable, Equatable {
    public struct FileRecord: Codable, Sendable, Equatable {
        public let name: String
        public let size: Int
        public let sha256: String
    }

    /// Sortable timestamp id, also the folder name.
    public let id: String
    public let createdAt: Date
    /// Plain-language reason, shown in the History list.
    public let note: String
    public let appVersion: String
    public let files: [FileRecord]
    /// True for the untouched snapshot taken the very first time the app ran.
    public var isFirstRun: Bool = false

    public var fileCount: Int { files.count }
}

public enum BackupError: Error, CustomStringConvertible {
    case snapshotNotFound(String)
    case saveFolderMissing(URL)
    case noFirstRunSnapshot

    public var description: String {
        switch self {
        case .snapshotNotFound(let id): "I couldn't find the backup \(id)."
        case .saveFolderMissing(let url): "There's no Deltarune save folder at \(url.path)."
        case .noFirstRunSnapshot: "There's no original backup to go back to yet."
        }
    }
}

/// Keeps every version of the save folder the app has ever replaced.
///
/// Snapshots live outside the game's own folder, so the game never sees stray files and a
/// Steam "verify integrity" can't wipe the history. The whole folder is copied each time
/// rather than individual files — it's around 130 KB, which makes restore trivially
/// correct for the cost of nothing.
public struct BackupStore: Sendable {
    /// Where snapshots are kept.
    public let rootDirectory: URL
    /// The game's save folder being protected.
    public let saveFolder: URL

    private let clock: @Sendable () -> Date
    private let appVersion: String

    public init(
        rootDirectory: URL,
        saveFolder: URL,
        appVersion: String = "1.0",
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootDirectory = rootDirectory
        self.saveFolder = saveFolder
        self.appVersion = appVersion
        self.clock = clock
    }

    private var backupsDirectory: URL { rootDirectory.appendingPathComponent("Backups") }
    private var firstRunDirectory: URL { rootDirectory.appendingPathComponent("FirstRun") }

    private static let manifestName = "manifest.json"

    // MARK: - Taking snapshots

    /// Copy the current save folder into a new timestamped snapshot.
    @discardableResult
    public func snapshot(note: String) throws -> BackupManifest {
        try snapshot(note: note, into: backupsDirectory.appendingPathComponent(makeIdentifier()))
    }

    /// Capture the pristine state the first time the app runs. Does nothing afterwards, so
    /// the original save is always recoverable no matter how much has been changed since.
    @discardableResult
    public func ensureFirstRunSnapshot() throws -> BackupManifest {
        if let existing = try? readManifest(at: firstRunDirectory) {
            return existing
        }
        var manifest = try snapshot(
            note: "How everything was before you used this app",
            into: firstRunDirectory
        )
        manifest.isFirstRun = true
        try writeManifest(manifest, to: firstRunDirectory)
        return manifest
    }

    private func snapshot(note: String, into directory: URL) throws -> BackupManifest {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: saveFolder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw BackupError.saveFolderMissing(saveFolder)
        }

        let names = try AtomicFile.copyDirectoryContents(from: saveFolder, to: directory)

        let records = try names.map { name -> BackupManifest.FileRecord in
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            return BackupManifest.FileRecord(
                name: name,
                size: data.count,
                sha256: Self.digest(data)
            )
        }

        let manifest = BackupManifest(
            id: directory.lastPathComponent,
            createdAt: clock(),
            note: note,
            appVersion: appVersion,
            files: records
        )
        try writeManifest(manifest, to: directory)
        return manifest
    }

    // MARK: - Listing

    /// Every snapshot, newest first. The first-run snapshot is included and flagged.
    public var snapshots: [BackupManifest] {
        var found: [BackupManifest] = []

        if let first = try? readManifest(at: firstRunDirectory) {
            var flagged = first
            flagged.isFirstRun = true
            found.append(flagged)
        }

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path)) ?? []
        for name in contents where !name.hasPrefix(".") {
            if let manifest = try? readManifest(at: backupsDirectory.appendingPathComponent(name)) {
                found.append(manifest)
            }
        }

        return found.sorted { $0.createdAt > $1.createdAt }
    }

    public func directory(for id: String) -> URL {
        id == firstRunDirectory.lastPathComponent
            ? firstRunDirectory
            : backupsDirectory.appendingPathComponent(id)
    }

    // MARK: - Restoring

    /// Put a snapshot back into the save folder.
    ///
    /// A snapshot of the current state is taken first, so restoring is itself undoable —
    /// a child who restores the wrong thing has lost nothing.
    @discardableResult
    public func restore(id: String) throws -> BackupManifest {
        let source = directory(for: id)
        guard let manifest = try? readManifest(at: source) else {
            throw BackupError.snapshotNotFound(id)
        }

        try snapshot(note: "Before going back to \(Self.friendlyDate(manifest.createdAt))")

        for record in manifest.files {
            let data = try Data(contentsOf: source.appendingPathComponent(record.name))
            try AtomicFile.write(data, to: saveFolder.appendingPathComponent(record.name))
        }
        return manifest
    }

    /// Return everything to how it was before the app was ever used.
    @discardableResult
    public func restoreFirstRun() throws -> BackupManifest {
        guard (try? readManifest(at: firstRunDirectory)) != nil else {
            throw BackupError.noFirstRunSnapshot
        }
        return try restore(id: firstRunDirectory.lastPathComponent)
    }

    /// Confirm a snapshot's files still match the checksums recorded when it was taken.
    public func verify(id: String) throws -> Bool {
        let source = directory(for: id)
        guard let manifest = try? readManifest(at: source) else {
            throw BackupError.snapshotNotFound(id)
        }
        for record in manifest.files {
            let url = source.appendingPathComponent(record.name)
            guard let data = try? Data(contentsOf: url), Self.digest(data) == record.sha256 else {
                return false
            }
        }
        return true
    }

    // MARK: - Manifests

    private func readManifest(at directory: URL) throws -> BackupManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent(Self.manifestName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupManifest.self, from: data)
    }

    private func writeManifest(_ manifest: BackupManifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(
            try encoder.encode(manifest),
            to: directory.appendingPathComponent(Self.manifestName)
        )
    }

    // MARK: - Helpers

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Sortable, filesystem-safe timestamp. Colons are illegal in paths, so use dashes.
    private func makeIdentifier() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let base = formatter.string(from: clock()) + "Z"
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(
            atPath: backupsDirectory.appendingPathComponent(candidate).path
        ) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    static func friendlyDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
