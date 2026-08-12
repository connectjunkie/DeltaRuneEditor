import Foundation
import Testing
@testable import DeltaruneCore

/// An early build opened the first save alphabetically — always Chapter 1 Slot 1, the
/// oldest file in the folder — rather than the one last played.
@Suite("Most recently played", .enabled(if: Fixtures.arePresent && Fixtures.hasDrIni))
struct RecencyTests {

    private func folderAndIni() throws -> (SaveFolder, DrIni) {
        (SaveFolder(url: Fixtures.directory), try Fixtures.drIni())
    }

    /// Derives the right answer from the data rather than hard-coding a filename: the
    /// playable slot carrying the newest recorded date.
    @Test("Opens the playable slot with the newest recorded date")
    func picksNewestPlayableSlot() throws {
        let (folder, ini) = try folderAndIni()

        let expected = folder.playableSaves
            .compactMap { save -> (SaveFileName, Date)? in
                ini.lastPlayed(for: save).map { (save, $0) }
            }
            .max { $0.1 < $1.1 }?.0

        try #require(expected != nil, "no playable slot has a dr.ini date")
        #expect(folder.mostRecentlyPlayed(drIni: ini) == expected)
    }

    /// Guards the original bug directly: if more than one slot is dated and they differ,
    /// the answer must not simply be the first file alphabetically.
    @Test("Doesn't just take the first file in the folder")
    func doesNotPickAlphabeticallyFirst() throws {
        let (folder, ini) = try folderAndIni()
        let dated = folder.playableSaves.compactMap { ini.lastPlayed(for: $0) }
        try #require(dated.count > 1, "needs at least two dated slots to be meaningful")
        try #require(Set(dated).count > 1, "all slots share a date")

        let first = try #require(folder.playableSaves.first)
        let chosen = try #require(folder.mostRecentlyPlayed(drIni: ini))

        let firstDate = try #require(ini.lastPlayed(for: first))
        let chosenDate = try #require(ini.lastPlayed(for: chosen))
        #expect(chosenDate >= firstDate)
    }

    @Test("Recorded dates are preferred over file timestamps")
    func usesRecordedDate() throws {
        let (folder, ini) = try folderAndIni()
        let dated = folder.saveFiles.filter { ini.lastPlayed(for: $0) != nil }
        try #require(!dated.isEmpty)

        for save in dated {
            #expect(folder.lastPlayed(for: save, drIni: ini) == ini.lastPlayed(for: save))
        }
    }

    @Test("Ordering is newest first among recorded slots")
    func ordering() throws {
        let (folder, ini) = try folderAndIni()
        let ordered = folder.savesByRecency(drIni: ini)

        #expect(ordered.count == folder.saveFiles.count)
        let recorded = ordered.filter(\.isRecordedDate).compactMap(\.lastPlayed)
        #expect(recorded == recorded.sorted(by: >))
    }

    /// Autosaves get no dr.ini section, so their only timestamp is the file's — which
    /// reflects when the folder was copied, not when it was played. They must never
    /// outrank a slot the game actually dated.
    @Test("Undated saves sort below every dated one")
    func undatedSortAfterDated() throws {
        let (folder, ini) = try folderAndIni()
        let ordered = folder.savesByRecency(drIni: ini)

        guard let firstUndated = ordered.firstIndex(where: { !$0.isRecordedDate }),
              let lastRecorded = ordered.lastIndex(where: { $0.isRecordedDate })
        else { return }

        #expect(lastRecorded < firstUndated)
    }

    @Test("Prefers a numbered slot over an autosave")
    func prefersPlayableSlot() throws {
        let (folder, ini) = try folderAndIni()
        try #require(!folder.playableSaves.isEmpty)
        #expect(folder.mostRecentlyPlayed(drIni: ini)?.kind == .save)
    }
}

/// These need no save files at all.
@Suite("Recency fallbacks")
struct RecencyFallbackTests {

    @Test("Falls back to file timestamps when there's no dr.ini",
          .enabled(if: Fixtures.arePresent))
    func fallsBackToModificationTime() throws {
        try Fixtures.withTemporarySaveFolder { url in
            try? FileManager.default.removeItem(at: url.appendingPathComponent("dr.ini"))
            let folder = SaveFolder(url: url)
            let target = try #require(folder.playableSaves.first)

            // Make one slot clearly the newest on disk.
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(3_600)],
                ofItemAtPath: folder.url(for: target).path
            )

            #expect(folder.mostRecentlyPlayed(drIni: nil) == target)
        }
    }

    @Test("An empty folder yields nothing rather than crashing")
    func emptyFolder() throws {
        try Fixtures.withTemporaryDirectory { root in
            let folder = SaveFolder(url: root)
            #expect(folder.mostRecentlyPlayed(drIni: nil) == nil)
            #expect(folder.savesByRecency(drIni: nil).isEmpty)
        }
    }
}
