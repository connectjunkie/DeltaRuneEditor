import Foundation
import Testing
@testable import DeltaruneCore

@Suite("GameMaker number formatting")
struct GMNumberTests {

    @Test(
        "Formats integers the way the game writes them",
        arguments: [
            (0, "0"),
            (1, "1"),
            (26, "26"),
            (-72, "-72"),
            (757, "757"),
            (999_999, "999999"),
            (1_000_000, "1e+06"),
            (1_304_870, "1.30487e+06"),
            (1_699_880, "1.69988e+06"),
            (20_072, "20072"),
            (571_260, "571260"),
        ]
    )
    func formatsIntegers(value: Int, expected: String) {
        #expect(GMNumber.format(value) == expected)
    }

    @Test("Values below one million stay plain, at or above switch to exponential")
    func thresholdBehaviour() {
        #expect(GMNumber.format(999_999) == "999999")
        #expect(GMNumber.format(1_000_000) == "1e+06")
        #expect(!GMNumber.format(999_999).contains("e"))
        #expect(GMNumber.format(1_000_001).contains("e+06"))
    }

    @Test("Exponents are padded to two digits")
    func exponentPadding() {
        // The bug this guards against is emitting "1.30487e+6" instead of "1.30487e+06".
        for value in [1_000_000, 1_304_870, 12_345_678, 999_999_999] {
            let formatted = GMNumber.format(value)
            let exponent = formatted.split(separator: "e").last.map(String.init) ?? ""
            #expect(exponent.count >= 3, "\(formatted) should have a signed two-digit exponent")
            #expect(exponent.hasPrefix("+") || exponent.hasPrefix("-"))
        }
    }

    @Test("Blank and non-numeric placeholders parse as zero")
    func parsesPlaceholdersAsZero() {
        #expect(GMNumber.parse("") == 0)
        #expect(GMNumber.parse("   ") == 0)
        #expect(GMNumber.parse("nan") == 0)
        #expect(GMNumber.parse("NaN") == 0)
        #expect(GMNumber.parse("null") == 0)
        #expect(GMNumber.parse("undefined") == 0)
    }

    @Test("Parses the values that actually appear in saves")
    func parsesRealValues() {
        #expect(GMNumber.parse("26 ") == 26)
        #expect(GMNumber.parse("-72 ") == -72)
        #expect(GMNumber.parse("1.30487e+06 ") == 1_304_870)
    }

    /// The decisive test. Take every numeric line out of every real save, parse it, format
    /// it again, and require the original string back. That is roughly 110,000 real values
    /// covering both formats — far better evidence than any hand-written table.
    @Test("Every numeric line in every fixture re-formats to itself",
          .enabled(if: Fixtures.arePresent), arguments: Fixtures.saves)
    func reformatsEveryNumericLineIdentically(save: Fixtures.Save) throws {
        let document = try save.document()
        var checked = 0
        var mismatches: [String] = []

        for (index, line) in document.lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let value = Double(trimmed) else { continue }

            let reformatted = GMNumber.format(value)
            checked += 1
            if reformatted != trimmed, mismatches.count < 5 {
                mismatches.append("line \(index): \(trimmed) → \(reformatted)")
            }
        }

        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(checked > 3_000, "expected to check thousands of values, only saw \(checked)")
    }
}
