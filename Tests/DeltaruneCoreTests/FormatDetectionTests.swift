import Foundation
import Testing
@testable import DeltaruneCore

@Suite("Format detection")
struct FormatDetectionTests {

    @Test("Each fixture is detected as the format its chapter uses",
          .enabled(if: Fixtures.arePresent), arguments: Fixtures.saves)
    func detectsExpectedFormat(save: Fixtures.Save) throws {
        #expect(try save.document().format == save.expectedFormat)
    }

    @Test("Chapter number maps to the right layout")
    func formatForChapter() {
        #expect(SaveFormat.forChapter(1) == .v1)
        #expect(SaveFormat.forChapter(2) == .v2)
        #expect(SaveFormat.forChapter(5) == .v2)
        #expect(SaveFormat.forChapter(6) == nil)
    }

    @Test("Line counts just inside the accepted range are detected")
    func acceptsBoundaryLineCounts() {
        #expect(SaveFormat.detect(lineCount: 10_311) == .v1)
        #expect(SaveFormat.detect(lineCount: 10_328) == .v1)
        #expect(SaveFormat.detect(lineCount: 3_046) == .v2)
        #expect(SaveFormat.detect(lineCount: 3_065) == .v2)
    }

    @Test("Line counts just outside the accepted range fail closed")
    func rejectsOutOfRangeLineCounts() {
        #expect(SaveFormat.detect(lineCount: 10_310) == nil)
        #expect(SaveFormat.detect(lineCount: 10_329) == nil)
        #expect(SaveFormat.detect(lineCount: 3_045) == nil)
        #expect(SaveFormat.detect(lineCount: 3_066) == nil)
        #expect(SaveFormat.detect(lineCount: 0) == nil)
    }

    @Test("The two accepted ranges cannot overlap")
    func rangesAreDisjoint() {
        #expect(!SaveFormat.v1.acceptedLineCounts.overlaps(SaveFormat.v2.acceptedLineCounts))
    }
}
