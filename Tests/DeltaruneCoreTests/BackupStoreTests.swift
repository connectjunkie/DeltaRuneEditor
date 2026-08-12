import Foundation
import Testing
@testable import DeltaruneCore

@Suite("Backups", .enabled(if: Fixtures.arePresent))
struct BackupStoreTests {

    /// Runs `body` against a throwaway copy of the real save folder plus an empty backup
    /// root, with a clock that advances a second per snapshot so ordering is deterministic.
    private func withStore(
        _ body: (BackupStore, URL) throws -> Void
    ) throws {
        try Fixtures.withTemporaryDirectory { root in
            let saveFolder = root.appendingPathComponent("com.tobyfox.deltarune")
            try FileManager.default.copyItem(at: Fixtures.directory, to: saveFolder)

            let tick = Ticker()
            let store = BackupStore(
                rootDirectory: root.appendingPathComponent("BackupRoot"),
                saveFolder: saveFolder,
                appVersion: "test",
                clock: { tick.next() }
            )
            try body(store, saveFolder)
        }
    }

    /// Deterministic clock: one second later on every read.
    private final class Ticker: @unchecked Sendable {
        private var seconds = 0.0
        private let lock = NSLock()
        func next() -> Date {
            lock.lock(); defer { lock.unlock() }
            seconds += 1
            return Date(timeIntervalSince1970: 1_770_000_000 + seconds)
        }
    }

    @Test("A snapshot captures every file in the save folder")
    func snapshotCapturesEveryFile() throws {
        try withStore { store, saveFolder in
            let manifest = try store.snapshot(note: "test")
            let onDisk = try FileManager.default.contentsOfDirectory(atPath: saveFolder.path)
                .filter { !$0.hasPrefix(".") }

            #expect(manifest.files.count == onDisk.count)
            #expect(manifest.note == "test")
            #expect(manifest.files.contains { $0.name == "filech2_0" })
            #expect(manifest.files.contains { $0.name == "dr.ini" })
        }
    }

    @Test("The manifest records a checksum and size per file")
    func manifestRecordsChecksums() throws {
        try withStore { store, saveFolder in
            let manifest = try store.snapshot(note: "test")
            let record = try #require(manifest.files.first { $0.name == "filech2_0" })
            let actual = try Data(contentsOf: saveFolder.appendingPathComponent("filech2_0"))

            #expect(record.sha256 == BackupStore.digest(actual))
            #expect(record.size == actual.count)
            #expect(record.sha256.count == 64)
            #expect(try store.verify(id: manifest.id) == true)
        }
    }

    /// The headline guarantee: whatever was there comes back exactly.
    @Test("Restoring reproduces the save folder byte for byte")
    func restoreProducesByteIdenticalFolder() throws {
        try withStore { store, saveFolder in
            let before = try Self.fingerprint(of: saveFolder)
            let manifest = try store.snapshot(note: "before edits")

            // Scribble over several files, including one we never model.
            for name in ["filech2_0", "filech1_0", "dr.ini"] {
                try Data("ruined".utf8).write(to: saveFolder.appendingPathComponent(name))
            }
            #expect(try Self.fingerprint(of: saveFolder) != before)

            try store.restore(id: manifest.id)
            #expect(try Self.fingerprint(of: saveFolder) == before)
        }
    }

    @Test("Restoring takes its own snapshot first, so it can be undone")
    func restoreIsItselfUndoable() throws {
        try withStore { store, saveFolder in
            let original = try Self.fingerprint(of: saveFolder)
            let first = try store.snapshot(note: "clean")

            try Data("edited".utf8).write(to: saveFolder.appendingPathComponent("filech2_0"))
            let edited = try Self.fingerprint(of: saveFolder)

            try store.restore(id: first.id)
            #expect(try Self.fingerprint(of: saveFolder) == original)

            // The state we restored away from was itself captured.
            let undo = try #require(store.snapshots.first { $0.note.hasPrefix("Before going back") })
            try store.restore(id: undo.id)
            #expect(try Self.fingerprint(of: saveFolder) == edited)
        }
    }

    @Test("The first-run snapshot is taken once and never replaced")
    func firstRunSnapshotIsStable() throws {
        try withStore { store, saveFolder in
            let first = try store.ensureFirstRunSnapshot()
            #expect(first.isFirstRun)

            try Data("later".utf8).write(to: saveFolder.appendingPathComponent("filech2_0"))
            let second = try store.ensureFirstRunSnapshot()

            #expect(second.id == first.id)
            #expect(second.createdAt == first.createdAt)
            // Still holds the original bytes, not the scribble.
            #expect(try store.verify(id: first.id) == true)
        }
    }

    @Test("Restoring the original undoes everything")
    func restoreOriginal() throws {
        try withStore { store, saveFolder in
            let original = try Self.fingerprint(of: saveFolder)
            try store.ensureFirstRunSnapshot()

            for _ in 0..<3 {
                try Data(UUID().uuidString.utf8).write(to: saveFolder.appendingPathComponent("filech2_0"))
                try store.snapshot(note: "an edit")
            }

            try store.restoreFirstRun()
            #expect(try Self.fingerprint(of: saveFolder) == original)
        }
    }

    @Test("Snapshots are listed newest first")
    func snapshotsAreOrderedNewestFirst() throws {
        try withStore { store, _ in
            try store.ensureFirstRunSnapshot()
            for index in 0..<4 { try store.snapshot(note: "edit \(index)") }

            let all = store.snapshots
            #expect(all.count == 5)
            #expect(all.first?.note == "edit 3")
            #expect(all.last?.isFirstRun == true)
            #expect(all == all.sorted { $0.createdAt > $1.createdAt })
        }
    }

    @Test("Two snapshots in the same second don't collide")
    func identifiersAreUnique() throws {
        try Fixtures.withTemporarySaveFolder { saveFolder in
            let frozen = Date(timeIntervalSince1970: 1_770_000_000)
            let store = BackupStore(
                rootDirectory: saveFolder.deletingLastPathComponent().appendingPathComponent("BackupRoot"),
                saveFolder: saveFolder,
                clock: { frozen }
            )

            let ids = try (0..<3).map { try store.snapshot(note: "same second \($0)").id }
            #expect(Set(ids).count == 3)
            #expect(store.snapshots.count == 3)
        }
    }

    @Test("Restoring a snapshot that doesn't exist throws")
    func missingSnapshotThrows() throws {
        try withStore { store, _ in
            #expect(throws: (any Error).self) { try store.restore(id: "nope") }
            #expect(throws: (any Error).self) { try store.restoreFirstRun() }
        }
    }

    @Test("Verification notices a corrupted snapshot")
    func verifyDetectsCorruption() throws {
        try withStore { store, _ in
            let manifest = try store.snapshot(note: "test")
            #expect(try store.verify(id: manifest.id) == true)

            let file = store.directory(for: manifest.id).appendingPathComponent("filech2_0")
            try Data("tampered".utf8).write(to: file)

            #expect(try store.verify(id: manifest.id) == false)
        }
    }

    /// name → sha256 for every file, so a whole folder can be compared in one value.
    private static func fingerprint(of folder: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
        where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            result[name] = BackupStore.digest(try Data(contentsOf: url))
        }
        return result
    }
}
