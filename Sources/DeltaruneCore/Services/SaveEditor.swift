import Foundation

public enum EditorError: Error, Equatable, CustomStringConvertible {
    case gameIsRunning
    case saveFileMissing(String)

    public var description: String {
        switch self {
        case .gameIsRunning:
            "Deltarune is open! Please quit the game first, then try again."
        case .saveFileMissing(let name):
            "I couldn't find the save file \(name)."
        }
    }
}

/// The write pipeline: guard, back up, write atomically, keep `dr.ini` in step.
///
/// Everything that changes a file on disk goes through `commit`, so there's exactly one
/// place where the safety rules are enforced.
public struct SaveEditor: Sendable {
    public let folder: SaveFolder
    public let backups: BackupStore
    public let gameMonitor: any GameRunningChecking

    public init(
        folder: SaveFolder,
        backups: BackupStore,
        gameMonitor: any GameRunningChecking = GameRunningMonitor()
    ) {
        self.folder = folder
        self.backups = backups
        self.gameMonitor = gameMonitor
    }

    /// Read a save. Throws if the round-trip gate fails, so an unparseable file can never
    /// reach the UI in an editable state.
    public func load(_ save: SaveFileName) throws -> SaveDocument {
        let url = folder.url(for: save)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EditorError.saveFileMissing(save.filename)
        }
        return try SaveDocument(contentsOf: url)
    }

    /// The result of a successful commit, for showing the child what happened.
    public struct CommitReport: Sendable {
        public let backup: BackupManifest
        public let changedLineCount: Int
        public let syncedIni: Bool
    }

    /// Write an edited document back, taking a restorable snapshot first.
    ///
    /// Does nothing and returns `nil` if the document is unchanged, so a stray click never
    /// creates a pointless backup.
    @discardableResult
    public func commit(
        _ document: SaveDocument,
        to save: SaveFileName,
        note: String,
        syncIni: Bool = true
    ) throws -> CommitReport? {
        guard !gameMonitor.isGameRunning else { throw EditorError.gameIsRunning }
        guard document.isModified else { return nil }

        // Capture the pristine state before the app's first ever write.
        try backups.ensureFirstRunSnapshot()
        let backup = try backups.snapshot(note: note)

        try AtomicFile.write(document.serialized(), to: folder.url(for: save))

        var synced = false
        if syncIni, var ini = try folder.loadDrIni(), ini.hasSection(save.iniSectionName) {
            try ini.sync(with: document, for: save)
            if ini.isModified {
                try AtomicFile.write(ini.serialized(), to: folder.drIniURL)
                synced = true
            }
        }

        return CommitReport(
            backup: backup,
            changedLineCount: document.modifiedLineIndices.count,
            syncedIni: synced
        )
    }

    /// Roll the save folder back to a snapshot.
    @discardableResult
    public func restore(snapshot id: String) throws -> BackupManifest {
        guard !gameMonitor.isGameRunning else { throw EditorError.gameIsRunning }
        return try backups.restore(id: id)
    }

    @discardableResult
    public func restoreOriginal() throws -> BackupManifest {
        guard !gameMonitor.isGameRunning else { throw EditorError.gameIsRunning }
        return try backups.restoreFirstRun()
    }
}
