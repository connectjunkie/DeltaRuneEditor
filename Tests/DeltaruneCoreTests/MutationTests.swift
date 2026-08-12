import Foundation
import Testing
@testable import DeltaruneCore

/// Proves the central safety claim: editing a field rewrites exactly one line and leaves
/// every other byte of the file alone.
@Suite("Mutation", .enabled(if: Fixtures.arePresent))
struct MutationTests {

    @Test("Changing money rewrites exactly one line")
    func editingMoneyChangesExactlyOneLine() throws {
        var document = try #require(Fixtures.any).document()
        try document.set(.money, to: 9_999)

        #expect(document.modifiedLineIndices.count == 1)
        #expect(document.modifiedLineIndices.first == document.fieldMap[.money])
        #expect(document.int(.money) == 9_999)
    }

    @Test("An edited line keeps its trailing space")
    func editedLineKeepsTrailingSpace() throws {
        var document = try #require(Fixtures.any).document()
        let before = try #require(document.rawLine(.money))
        let suffix = String(before.reversed().prefix { $0 == " " })

        try document.set(.money, to: 9_999)

        #expect(document.rawLine(.money) == "9999" + suffix)
        #expect(!suffix.isEmpty, "numeric lines carry a trailing space")
    }

    @Test("Editing never changes the number of lines", arguments: Fixtures.saves)
    func lineCountUnchangedAfterEdit(save: Fixtures.Save) throws {
        var document = try save.document()
        let before = document.lines.count

        try document.set(.money, to: 12_345)
        try document.set(.lv, to: 20)
        try document.setString(.playerName, to: "SAM")

        #expect(document.lines.count == before)
        #expect(document.serialized().count > 0)
    }

    @Test("Several edits change only those lines")
    func severalEditsChangeOnlyThoseLines() throws {
        var document = try #require(Fixtures.any).document()
        let targets: [FieldID] = [.money, .lv, .charMaxHealth(1), .charAttack(1), .invConsumable(0)]

        for field in targets { try document.set(field, to: 42) }

        let expected = Set(targets.compactMap { document.fieldMap[$0] })
        #expect(document.modifiedLineIndices == expected)
        #expect(document.modifiedFields == Set(targets))
    }

    @Test("Reverting an edit restores the original bytes exactly", arguments: Fixtures.saves)
    func revertRestoresOriginalBytes(save: Fixtures.Save) throws {
        let original = try save.bytes
        var document = try SaveDocument(bytes: original)

        try document.set(.money, to: 999_999)
        #expect(document.serialized() != original)

        try document.revert(.money)
        #expect(document.serialized() == original)
        #expect(document.isModified == false)
    }

    @Test("revertAll restores the original bytes exactly")
    func revertAllRestoresOriginalBytes() throws {
        let save = try #require(Fixtures.any)
        let original = try save.bytes
        var document = try SaveDocument(bytes: original)

        try document.set(.money, to: 1)
        try document.set(.lv, to: 2)
        try document.setString(.vesselName, to: "ZZZ")
        document.revertAll()

        #expect(document.serialized() == original)
    }

    /// The flag array is thousands of lines the simple UI deliberately doesn't model.
    /// Editing gameplay fields must not disturb a single one of them.
    @Test("Editing leaves the flag array untouched", arguments: Fixtures.saves)
    func flagArrayIsUntouched(save: Fixtures.Save) throws {
        var document = try save.document()
        let flagIndices = document.fieldMap.compactMap { field, index -> Int? in
            if case .flag = field { return index } else { return nil }
        }
        let before = flagIndices.map { document.lines[$0] }

        try document.set(.money, to: 500)
        try document.set(.charMaxHealth(1), to: 200)

        #expect(flagIndices.map { document.lines[$0] } == before)
        #expect(flagIndices.count == document.flagCount)
    }

    @Test("Writing to a field the format doesn't have throws")
    func unknownFieldThrows() throws {
        // Chapter 1 has no storage block.
        var document = try #require(Fixtures.anyV1).document()

        #expect(throws: (any Error).self) {
            try document.set(.invStorage(0), to: 1)
        }
        #expect(document.isModified == false)
    }

    @Test("A name containing a line break cannot shift the file")
    func nameWithNewlineIsSanitized() throws {
        var document = try #require(Fixtures.any).document()
        let before = document.lines.count

        try document.setString(.playerName, to: "AB\r\nCD")

        #expect(document.lines.count == before)
        #expect(document.string(.playerName) == "ABCD")
        #expect(document.modifiedLineIndices.count == 1)
    }

    @Test("Raw line editing changes one line and keeps its trailing space")
    func rawLineEditing() throws {
        var document = try #require(Fixtures.any).document()
        let index = try #require(document.fieldMap[.money])
        let suffix = String(document.lines[index].reversed().prefix { $0 == " " })

        try document.setRawLine(index, to: "1234")

        #expect(document.lines[index] == "1234" + suffix)
        #expect(document.modifiedLineIndices == [index])
        #expect(document.int(.money) == 1_234)
    }

    @Test("Raw line editing cannot change the file's shape")
    func rawLineCannotAddLines() throws {
        var document = try #require(Fixtures.any).document()
        let before = document.lines.count

        try document.setRawLine(20, to: "1\r\n2\n3")

        #expect(document.lines.count == before)
        #expect(!document.lines[20].contains("\n"))
        #expect(try SaveDocument(bytes: document.serialized()).lines.count == before)
    }

    @Test("Raw line editing rejects an index outside the file")
    func rawLineOutOfRange() throws {
        var document = try #require(Fixtures.any).document()

        #expect(throws: (any Error).self) { try document.setRawLine(-1, to: "x") }
        #expect(throws: (any Error).self) { try document.setRawLine(999_999, to: "x") }
        #expect(document.isModified == false)
    }

    /// The Advanced tab bypasses the field map, but must not bypass the round-trip
    /// guarantee — a file edited that way still has to reload cleanly.
    @Test("A raw-edited file still reloads and round trips")
    func rawEditedFileStillRoundTrips() throws {
        let save = try #require(Fixtures.any)
        var document = try save.document()
        try document.setRawLine(500, to: "7")

        let reloaded = try SaveDocument(bytes: document.serialized())
        #expect(reloaded.serialized() == document.serialized())
        #expect(reloaded.format == document.format)
    }

    @Test("Round trip still holds after an edit is written and reloaded")
    func editedFileReloadsCleanly() throws {
        var document = try #require(Fixtures.any).document()
        try document.set(.money, to: 4_242)

        let reloaded = try SaveDocument(bytes: document.serialized())
        #expect(reloaded.int(.money) == 4_242)
        #expect(reloaded.serialized() == document.serialized())
        #expect(reloaded.format == document.format)
        #expect(reloaded.flagCount == document.flagCount)
    }
}
