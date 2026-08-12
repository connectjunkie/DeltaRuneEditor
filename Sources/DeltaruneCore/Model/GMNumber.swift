import Foundation

/// Reproduces how GameMaker (via JavaScript number semantics) writes numbers into a save.
///
/// The rule, confirmed against real save files: values below 1e6 are written plainly, and
/// values at or above 1e6 switch to exponential with a two-digit exponent —
/// `1304870` becomes `1.30487e+06`, not `1.30487e+6` and not `1304870`.
///
/// Getting this wrong silently corrupts large values such as playtime, so
/// `GMNumberTests` re-formats every numeric line of every real fixture and requires the
/// original string back.
public enum GMNumber {
    /// Threshold at which GameMaker switches to exponential notation.
    public static let exponentialThreshold = 1_000_000.0

    /// Format an integer the way the game would write it.
    public static func format(_ value: Int) -> String {
        if abs(value) < Int(exponentialThreshold) {
            return String(value)
        }
        return format(Double(value))
    }

    /// Format a double the way the game would write it.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "0" }

        if abs(value) >= exponentialThreshold {
            return exponential(value)
        }

        // Below the threshold, JS `String(n)` is the shortest representation that round
        // trips, with no ".0" suffix on integral values.
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return shortestDecimal(value)
    }

    /// Mirror of JavaScript's `Number.prototype.toExponential()` with no argument: one
    /// digit before the point, the fewest digits after it that still round trip, then the
    /// exponent padded to at least two digits.
    private static func exponential(_ value: Double) -> String {
        for precision in 0...17 {
            let candidate = String(format: "%.\(precision)e", value)
            if Double(candidate) == value {
                return normalizeExponent(candidate)
            }
        }
        return normalizeExponent(String(format: "%.17e", value))
    }

    /// `printf` gives `1.30487e+06` on macOS already, but pads to two digits and keeps
    /// trailing zeros in the mantissa. Strip the mantissa's trailing zeros and guarantee
    /// the exponent is at least two digits.
    private static func normalizeExponent(_ formatted: String) -> String {
        let parts = formatted.split(separator: "e", maxSplits: 1)
        guard parts.count == 2 else { return formatted }

        var mantissa = String(parts[0])
        if mantissa.contains(".") {
            while mantissa.hasSuffix("0") { mantissa.removeLast() }
            if mantissa.hasSuffix(".") { mantissa.removeLast() }
        }

        var exponent = String(parts[1])
        var sign = "+"
        if exponent.hasPrefix("-") || exponent.hasPrefix("+") {
            sign = String(exponent.removeFirst())
        }
        while exponent.count > 2, exponent.hasPrefix("0") { exponent.removeFirst() }
        while exponent.count < 2 { exponent = "0" + exponent }

        return "\(mantissa)e\(sign)\(exponent)"
    }

    /// Shortest decimal string that parses back to the same double.
    private static func shortestDecimal(_ value: Double) -> String {
        for precision in 1...17 {
            let candidate = String(format: "%.\(precision)g", value)
            if Double(candidate) == value {
                return candidate
            }
        }
        return String(value)
    }

    /// Parse a value as the game would read it. Blank, `null`, `undefined` and `nan` all
    /// mean zero in GameMaker's reader.
    public static func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty || trimmed == "null" || trimmed == "undefined" || trimmed == "nan" {
            return 0
        }
        return Double(trimmed)
    }
}
