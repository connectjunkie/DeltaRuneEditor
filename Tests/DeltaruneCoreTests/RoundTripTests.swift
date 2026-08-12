import Foundation
import Testing
@testable import DeltaruneCore

/// The load-bearing suite. If these fail, nothing else in the app is trustworthy and it
/// must refuse to write.
@Suite("Round trip", .enabled(if: Fixtures.arePresent))
struct RoundTripTests {

    @Test("Parsing then rebuilding reproduces the file byte for byte", arguments: Fixtures.saves)
    func roundTripIsByteIdentical(save: Fixtures.Save) throws {
        let original = try save.bytes
        let document = try SaveDocument(bytes: original)
        #expect(document.serialized() == original)
    }

    @Test("Line endings are detected and preserved", arguments: Fixtures.saves)
    func detectsLineEnding(save: Fixtures.Save) throws {
        let document = try save.document()
        #expect(document.lineEnding == "\r\n" || document.lineEnding == "\n")
        // Whatever it is, it survives the round trip — proven above.
        #expect(try save.bytes.count > 0)
    }

    /// The quirk that breaks naive editors: the name/vessel header and the five blank
    /// lines after it carry no trailing space, but every line from there on does.
    @Test("First seven lines have no trailing space, the rest do", arguments: Fixtures.saves)
    func trailingSpaceRule(save: Fixtures.Save) throws {
        let document = try save.document()

        for index in 0..<7 {
            #expect(!document.lines[index].hasSuffix(" "), "line \(index) should have no trailing space")
        }

        // Sample rather than assert on all 10,318 — enough to catch a systematic break.
        for index in stride(from: 7, to: document.lines.count, by: 97) {
            #expect(document.lines[index].hasSuffix(" "), "line \(index) should have a trailing space")
        }
    }

    @Test("A truncated save is rejected rather than partially parsed")
    func rejectsTruncatedFile() throws {
        let document = try #require(Fixtures.any).document()
        let truncated = document.lines.dropLast(200).joined(separator: "\r\n")

        #expect(throws: (any Error).self) {
            try SaveDocument(bytes: Data(truncated.utf8))
        }
    }

    /// Proves the gate is a real check and not incidentally true: a file that cannot be
    /// reassembled exactly must be refused. Mixed line endings do exactly that, because
    /// splitting on CRLF and rejoining cannot restore a bare CR.
    @Test("A file that cannot be reassembled exactly is refused")
    func roundTripGateRejectsUnreproducibleFile() throws {
        let document = try #require(Fixtures.any).document()
        guard document.lineEnding == "\r\n" else { return }

        var text = document.lines.joined(separator: "\r\n")
        text = text.replacingOccurrences(
            of: "\r\n", with: "\r", options: [], range: text.range(of: "\r\n")
        )

        #expect(throws: (any Error).self) {
            try SaveDocument(bytes: Data(text.utf8))
        }
    }

    @Test("Every field index is unique and inside the file", arguments: Fixtures.saves)
    func fieldMapIndicesAreUniqueAndInBounds(save: Fixtures.Save) throws {
        let document = try save.document()
        let indices = document.fieldMap.values

        #expect(Set(indices).count == indices.count, "a line is mapped to two different fields")
        #expect(indices.allSatisfy { $0 >= 0 && $0 < document.lines.count })
    }
}

/// Rejection cases that need no save files.
@Suite("Round trip rejections")
struct RoundTripRejectionTests {

    @Test("A file whose line count matches nothing is rejected")
    func rejectsUnrecognizedLineCount() throws {
        let text = Array(repeating: "0 ", count: 500).joined(separator: "\r\n")
        #expect(throws: SaveDocumentError.unrecognizedFormat(lineCount: 500)) {
            try SaveDocument(bytes: Data(text.utf8))
        }
    }

    @Test("Empty and garbage input are rejected")
    func rejectsGarbage() throws {
        #expect(throws: (any Error).self) { try SaveDocument(bytes: Data()) }
        #expect(throws: (any Error).self) { try SaveDocument(bytes: Data("hello".utf8)) }
    }
}
