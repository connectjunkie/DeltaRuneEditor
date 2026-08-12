import Foundation
import Testing
@testable import DeltaruneCore

@Suite("Save editor pipeline", .enabled(if: Fixtures.arePresent))
struct SaveEditorTests {

    private func withEditor(
        gameRunning: Bool = false,
        _ body: (SaveEditor, SaveFolder) throws -> Void
    ) throws {
        try Fixtures.withTemporaryDirectory { root in
            let saveFolder = root.appendingPathComponent("com.tobyfox.deltarune")
            try FileManager.default.copyItem(at: Fixtures.directory, to: saveFolder)

            let folder = SaveFolder(url: saveFolder)
            let editor = SaveEditor(
                folder: folder,
                backups: BackupStore(
                    rootDirectory: root.appendingPathComponent("BackupRoot"),
                    saveFolder: saveFolder
                ),
                gameMonitor: StubGameMonitor(isRunning: gameRunning)
            )
            try body(editor, folder)
        }
    }

    /// Whichever save the person running the tests supplied.
    private var target: SaveFileName {
        get throws {
            let save = try #require(Fixtures.any)
            return try #require(SaveFileName(save.name))
        }
    }

    @Test("Committing an edit writes it and leaves the rest of the file alone")
    func commitWritesTheEdit() throws {
        try withEditor { editor, folder in
            let before = try Data(contentsOf: folder.url(for: try target))
            let roomBefore = try editor.load(try target).int(.room)

            var document = try editor.load(try target)
            try document.set(.money, to: 9_999)
            let report = try #require(try editor.commit(document, to: try target, note: "Changed money"))

            #expect(report.changedLineCount == 1)

            let after = try Data(contentsOf: folder.url(for: try target))
            #expect(after != before)
            #expect(after.count > 0)

            let reloaded = try editor.load(try target)
            #expect(reloaded.int(.money) == 9_999)
            #expect(reloaded.int(.room) == roomBefore)   // untouched
        }
    }

    @Test("Committing takes a backup first")
    func commitTakesBackup() throws {
        try withEditor { editor, _ in
            #expect(editor.backups.snapshots.isEmpty)

            var document = try editor.load(try target)
            try document.set(.money, to: 1_234)
            try editor.commit(document, to: try target, note: "Changed money")

            let snapshots = editor.backups.snapshots
            #expect(snapshots.count == 2)                       // first-run plus this edit
            #expect(snapshots.contains { $0.isFirstRun })
            #expect(snapshots.contains { $0.note == "Changed money" })
        }
    }

    @Test("The backup holds the file as it was before the edit")
    func backupHoldsPreEditState() throws {
        try withEditor { editor, folder in
            let before = try Data(contentsOf: folder.url(for: try target))

            var document = try editor.load(try target)
            try document.set(.money, to: 5_555)
            let report = try #require(try editor.commit(document, to: try target, note: "edit"))

            let backedUp = try Data(
                contentsOf: editor.backups.directory(for: report.backup.id)
                    .appendingPathComponent((try target).filename)
            )
            #expect(backedUp == before)
        }
    }

    @Test("An unchanged document commits nothing")
    func unchangedDocumentIsNoOp() throws {
        try withEditor { editor, folder in
            let before = try Data(contentsOf: folder.url(for: try target))
            let document = try editor.load(try target)

            #expect(try editor.commit(document, to: try target, note: "nothing") == nil)
            #expect(try Data(contentsOf: folder.url(for: try target)) == before)
            #expect(editor.backups.snapshots.isEmpty)
        }
    }

    @Test("Nothing is written while Deltarune is running")
    func refusesToWriteWhileGameRunning() throws {
        try withEditor(gameRunning: true) { editor, folder in
            let before = try Data(contentsOf: folder.url(for: try target))

            var document = try editor.load(try target)
            try document.set(.money, to: 9_999)

            #expect(throws: EditorError.gameIsRunning) {
                try editor.commit(document, to: try target, note: "edit")
            }
            #expect(try Data(contentsOf: folder.url(for: try target)) == before)
            #expect(editor.backups.snapshots.isEmpty)
        }
    }

    @Test("Restoring is also blocked while the game is running")
    func refusesToRestoreWhileGameRunning() throws {
        try withEditor(gameRunning: true) { editor, _ in
            #expect(throws: EditorError.gameIsRunning) { try editor.restoreOriginal() }
        }
    }

    @Test("Changing the level updates the file-select metadata too")
    func commitSyncsDrIni() throws {
        try withEditor { editor, folder in
            let slot = try target
            let section = slot.iniSectionName
            let iniBefore = try #require(try folder.loadDrIni())
            try #require(iniBefore.hasSection(section), "the chosen save has no dr.ini section")

            let roomBefore = iniBefore.number(section: section, key: DrIni.Key.room)
            let otherSections = iniBefore.sectionOrder.filter { $0 != section }
                .compactMap { name -> (String, Double)? in
                    iniBefore.number(section: name, key: DrIni.Key.level).map { (name, $0) }
                }

            var document = try editor.load(slot)
            try document.set(.lv, to: 9)
            let report = try #require(try editor.commit(document, to: slot, note: "level"))
            #expect(report.syncedIni)

            let ini = try #require(try folder.loadDrIni())
            #expect(ini.number(section: section, key: DrIni.Key.level) == 9)
            #expect(ini.number(section: section, key: DrIni.Key.room) == roomBefore)
            for (name, level) in otherSections {
                #expect(ini.number(section: name, key: DrIni.Key.level) == level,
                        "section \(name) should be untouched")
            }
        }
    }

    @Test("Editing money doesn't disturb dr.ini")
    func moneyEditLeavesIniAlone() throws {
        try withEditor { editor, folder in
            let before = try Data(contentsOf: folder.drIniURL)

            var document = try editor.load(try target)
            try document.set(.money, to: 4_321)
            let report = try #require(try editor.commit(document, to: try target, note: "money"))

            #expect(report.syncedIni == false)
            #expect(try Data(contentsOf: folder.drIniURL) == before)
        }
    }

    @Test("A full edit-then-restore cycle returns every byte")
    func editThenRestoreRoundTrip() throws {
        try withEditor { editor, folder in
            let before = try Data(contentsOf: folder.url(for: try target))
            let iniBefore = try Data(contentsOf: folder.drIniURL)

            var document = try editor.load(try target)
            try document.set(.money, to: 99_999)
            try document.set(.lv, to: 20)
            try document.setString(.playerName, to: "SAM")
            try editor.commit(document, to: try target, note: "big edit")

            try editor.restoreOriginal()

            #expect(try Data(contentsOf: folder.url(for: try target)) == before)
            #expect(try Data(contentsOf: folder.drIniURL) == iniBefore)
        }
    }

    @Test("Loading a save that isn't there throws")
    func missingSaveThrows() throws {
        try withEditor { editor, _ in
            // A slot the fixtures cannot contain, whatever was supplied.
            let absent = try #require(SaveFileName("filech5_2"))
            #expect(throws: EditorError.saveFileMissing("filech5_2")) {
                try editor.load(absent)
            }
        }
    }
}

@Suite("Save folder", .enabled(if: Fixtures.arePresent))
struct SaveFolderTests {

    @Test("Lists the save files and ignores everything else")
    func listsSaveFiles() throws {
        try Fixtures.withTemporarySaveFolder { url in
            let folder = SaveFolder(url: url)
            let names = folder.saveFiles.map(\.filename)

            #expect(names == Fixtures.saves.map(\.name).sorted())
            // Ordered by chapter, then slot.
            #expect(folder.saveFiles == folder.saveFiles.sorted {
                ($0.chapter, $0.rawSlot) < ($1.chapter, $1.rawSlot)
            })
            // Nothing that isn't a save file.
            #expect(!names.contains { !$0.hasPrefix("filech") })
        }
    }

    @Test("Playable saves exclude autosaves and completion files")
    func playableSaves() throws {
        try Fixtures.withTemporarySaveFolder { url in
            let playable = SaveFolder(url: url).playableSaves
            #expect(playable.allSatisfy { $0.kind == .save })
            #expect(playable.allSatisfy { (0...2).contains($0.rawSlot) })
            #expect(playable.count <= Fixtures.saves.count)
        }
    }

    @Test("Reports a missing folder rather than crashing")
    func missingFolder() {
        let folder = SaveFolder(url: URL(fileURLWithPath: "/nope/not/here"))
        #expect(folder.exists == false)
        #expect(folder.saveFiles.isEmpty)
        #expect(throws: Never.self) { _ = try folder.loadDrIni() }
    }

    @Test("The default path is where DELTARUNE actually saves on macOS")
    func defaultPath() {
        #expect(SaveFolder.defaultURL.path.hasSuffix(
            "Library/Application Support/com.tobyfox.deltarune"
        ))
    }
}

@Suite("Atomic writes")
struct AtomicWriteTests {

    @Test("Writing replaces the file completely")
    func writeReplacesFile() throws {
        try Fixtures.withTemporaryDirectory { root in
            let target = root.appendingPathComponent("file.txt")
            try AtomicFile.write(Data("first".utf8), to: target)
            try AtomicFile.write(Data("second".utf8), to: target)

            #expect(try String(contentsOf: target, encoding: .utf8) == "second")
        }
    }

    @Test("No temporary files are left behind")
    func leavesNoTemporaryFiles() throws {
        try Fixtures.withTemporaryDirectory { root in
            let target = root.appendingPathComponent("file.txt")
            for index in 0..<5 { try AtomicFile.write(Data("\(index)".utf8), to: target) }

            let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".tmp") }
            #expect(leftovers.isEmpty)
        }
    }

    @Test("A failed write leaves the original untouched")
    func failedWriteLeavesOriginalIntact() throws {
        try Fixtures.withTemporaryDirectory { root in
            let target = root.appendingPathComponent("file.txt")
            try AtomicFile.write(Data("original".utf8), to: target)

            // A directory where the temporary file would go cannot be written to.
            let unwritable = root.appendingPathComponent("locked", isDirectory: true)
            try FileManager.default.createDirectory(at: unwritable, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: unwritable.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unwritable.path) }

            #expect(throws: (any Error).self) {
                try AtomicFile.write(Data("new".utf8), to: unwritable.appendingPathComponent("f.txt"))
            }
            #expect(try String(contentsOf: target, encoding: .utf8) == "original")
        }
    }

    @Test("Copying a directory brings every regular file")
    func copiesDirectoryContents() throws {
        try Fixtures.withTemporaryDirectory { root in
            // Self-contained: this exercises the copy helper, not the save format.
            let source = root.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

            let contents = ["alpha": "one", "beta": "two", "gamma.ini": "three"]
            for (name, body) in contents {
                try Data(body.utf8).write(to: source.appendingPathComponent(name))
            }
            // Hidden files and subdirectories are skipped.
            try Data("hidden".utf8).write(to: source.appendingPathComponent(".hidden"))
            try FileManager.default.createDirectory(
                at: source.appendingPathComponent("nested"), withIntermediateDirectories: true
            )

            let destination = root.appendingPathComponent("copy")
            let names = try AtomicFile.copyDirectoryContents(from: source, to: destination)

            #expect(names.sorted() == contents.keys.sorted())
            for (name, body) in contents {
                #expect(try String(contentsOf: destination.appendingPathComponent(name),
                                   encoding: .utf8) == body)
            }
            #expect(!FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(".hidden").path))
        }
    }
}
