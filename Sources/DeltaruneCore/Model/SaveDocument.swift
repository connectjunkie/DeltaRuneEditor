import Foundation

public enum SaveDocumentError: Error, Equatable, CustomStringConvertible {
    case unreadableEncoding
    case unrecognizedFormat(lineCount: Int)
    case truncated(atLine: Int)
    case tooFewFlags(found: Int, expected: Int)
    case roundTripMismatch(firstDifferingByte: Int)
    case unknownField(String)
    case notEditable(String)

    public var description: String {
        switch self {
        case .unreadableEncoding:
            "This file isn't text I can read."
        case .unrecognizedFormat(let lineCount):
            "Unrecognized save format (\(lineCount) lines)."
        case .truncated(let line):
            "The file ends unexpectedly at line \(line)."
        case .tooFewFlags(let found, let expected):
            "Only \(found) flags, expected at least \(expected)."
        case .roundTripMismatch(let byte):
            "I couldn't reproduce this file exactly (first difference at byte \(byte)), so I won't change it."
        case .unknownField(let name):
            "This save has no field called \(name)."
        case .notEditable(let reason):
            reason
        }
    }
}

/// A save file held as its exact original lines, plus a map from named fields to line
/// indices.
///
/// The design rule: **we never re-serialize a save from a model.** Editing replaces
/// individual entries in `lines` and nothing else, so every byte we don't understand —
/// including the thousands of flag lines — is preserved by construction, and a mistake in
/// the field mapping can only ever affect the one field it belongs to.
///
/// Loading enforces a round-trip gate: rebuilding the untouched lines must reproduce the
/// original bytes exactly, or the document refuses to exist. Nothing can be written
/// unless we have already proven we can reproduce it.
public struct SaveDocument: Sendable {
    /// Bytes exactly as read from disk.
    public let originalBytes: Data
    /// Line separator detected in the file. Real DELTARUNE saves use CRLF.
    public let lineEnding: String
    /// Whether the file ended with a separator. Real saves do not.
    public let hadTrailingNewline: Bool
    /// Text encoding used to decode, and which will be used to re-encode.
    public let encoding: String.Encoding
    /// Which layout this file uses.
    public let format: SaveFormat
    /// Field name to line index. The only sanctioned way to address a line.
    public let fieldMap: [FieldID: Int]
    /// Number of flag entries found in this particular file.
    public let flagCount: Int

    /// Current line contents, verbatim including any trailing spaces.
    public private(set) var lines: [String]
    /// Line contents as loaded, for change detection and revert.
    private let pristineLines: [String]

    // MARK: - Loading

    public init(bytes: Data) throws {
        let (text, encoding) = try Self.decode(bytes)
        self.originalBytes = bytes
        self.encoding = encoding

        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        self.lineEnding = lineEnding

        var split = text.components(separatedBy: lineEnding)
        let trailing = split.count > 1 && split.last == ""
        if trailing { split.removeLast() }
        self.hadTrailingNewline = trailing
        self.lines = split
        self.pristineLines = split

        guard let format = SaveFormat.detect(lineCount: split.count) else {
            throw SaveDocumentError.unrecognizedFormat(lineCount: split.count)
        }
        self.format = format

        let mapping = try SaveParser.map(lineCount: split.count, format: format)
        self.fieldMap = mapping.fields
        self.flagCount = mapping.flagCount

        // The gate. Everything downstream depends on this having passed.
        let rebuilt = Self.assemble(
            lines: split,
            lineEnding: lineEnding,
            hadTrailingNewline: trailing,
            encoding: encoding
        )
        if rebuilt != bytes {
            throw SaveDocumentError.roundTripMismatch(
                firstDifferingByte: Self.firstDifference(rebuilt, bytes)
            )
        }
    }

    public init(contentsOf url: URL) throws {
        try self.init(bytes: try Data(contentsOf: url))
    }

    /// Decode as UTF-8 where possible. ISO Latin-1 is the fallback because it maps every
    /// byte 1:1 in both directions, so an unusual byte can never break the round trip.
    private static func decode(_ bytes: Data) throws -> (String, String.Encoding) {
        if let utf8 = String(data: bytes, encoding: .utf8) {
            return (utf8, .utf8)
        }
        if let latin1 = String(data: bytes, encoding: .isoLatin1) {
            return (latin1, .isoLatin1)
        }
        throw SaveDocumentError.unreadableEncoding
    }

    // MARK: - Reading

    /// The raw line backing a field, trailing space and all.
    public func rawLine(_ field: FieldID) -> String? {
        fieldMap[field].map { lines[$0] }
    }

    /// A field's value with surrounding whitespace removed.
    public func string(_ field: FieldID) -> String? {
        rawLine(field)?.trimmingCharacters(in: .whitespaces)
    }

    public func double(_ field: FieldID) -> Double? {
        rawLine(field).flatMap { GMNumber.parse($0) }
    }

    public func int(_ field: FieldID) -> Int? {
        guard let value = double(field), value.isFinite,
              value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    public func bool(_ field: FieldID) -> Bool? {
        double(field).map { $0 != 0 }
    }

    // MARK: - Writing

    /// Replace a field's value, preserving the line's original trailing whitespace.
    ///
    /// The suffix is copied from the line as it currently stands rather than derived from
    /// a rule, so whatever quirk the file has is carried through untouched.
    public mutating func set(_ field: FieldID, toRaw value: String) throws {
        guard let index = fieldMap[field] else {
            throw SaveDocumentError.unknownField(String(describing: field))
        }
        if let reason = reservedReason(for: field) {
            throw SaveDocumentError.notEditable(reason)
        }
        let original = lines[index]
        let suffix = original.suffix(while: { $0 == " " })
        lines[index] = value + suffix
    }

    public mutating func set(_ field: FieldID, to value: Int) throws {
        try set(field, toRaw: GMNumber.format(value))
    }

    public mutating func set(_ field: FieldID, to value: Double) throws {
        try set(field, toRaw: GMNumber.format(value))
    }

    public mutating func set(_ field: FieldID, to value: Bool) throws {
        try set(field, toRaw: value ? "1" : "0")
    }

    public mutating func setString(_ field: FieldID, to value: String) throws {
        // Names must not contain a line break or they would shift every later line.
        let sanitized = value.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        try set(field, toRaw: sanitized)
    }

    /// Write a line directly by index, bypassing the field map entirely.
    ///
    /// The Advanced tab's escape hatch, for lines this app doesn't model. It still can't
    /// change the file's shape: the trailing whitespace is preserved and line breaks are
    /// stripped, so the line count stays fixed and the round trip stays valid.
    public mutating func setRawLine(_ index: Int, to value: String) throws {
        guard lines.indices.contains(index) else {
            throw SaveDocumentError.unknownField("line \(index + 1)")
        }
        let suffix = lines[index].suffix(while: { $0 == " " })
        let sanitized = value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        lines[index] = sanitized + suffix
    }

    /// Why a field can't be written, or `nil` if it can.
    ///
    /// The inventory arrays store one more entry than the player can use; the last is an
    /// end-of-list marker. Overwriting it corrupts the inventory, so it is refused here
    /// rather than left to each screen to remember.
    public func reservedReason(for field: FieldID) -> String? {
        func check(_ slot: Int, _ usable: Int, _ what: String) -> String? {
            slot >= usable ? "\(what) slot \(slot) is an end-of-list marker, not an item." : nil
        }

        switch field {
        case .invConsumable(let slot): return check(slot, format.usableConsumableSlots, "Item")
        case .invKeyItem(let slot): return check(slot, format.usableKeyItemSlots, "Key item")
        case .invWeapon(let slot): return check(slot, format.usableWeaponSlots, "Weapon")
        case .invArmor(let slot): return check(slot, format.usableArmorSlots, "Armour")
        case .invStorage(let slot): return check(slot, format.usableStorageSlots, "Storage")
        default: return nil
        }
    }

    public func isEditable(_ field: FieldID) -> Bool {
        fieldMap[field] != nil && reservedReason(for: field) == nil
    }

    /// Slot indices a screen may offer for a given inventory category.
    public func usableSlots(for category: ItemCategory) -> Range<Int> {
        switch category {
        case .consumables: 0..<format.usableConsumableSlots
        case .keyItems: 0..<format.usableKeyItemSlots
        case .weapons: 0..<format.usableWeaponSlots
        case .armors: 0..<format.usableArmorSlots
        default: 0..<0
        }
    }

    /// Restore a single field to how it was loaded.
    public mutating func revert(_ field: FieldID) throws {
        guard let index = fieldMap[field] else {
            throw SaveDocumentError.unknownField(String(describing: field))
        }
        lines[index] = pristineLines[index]
    }

    /// Restore every field to how it was loaded.
    public mutating func revertAll() {
        lines = pristineLines
    }

    // MARK: - Change tracking

    public var isModified: Bool { lines != pristineLines }

    /// Indices whose content differs from the loaded file. Used by the tests to prove that
    /// editing one field touches exactly one line.
    public var modifiedLineIndices: Set<Int> {
        var changed: Set<Int> = []
        for index in lines.indices where lines[index] != pristineLines[index] {
            changed.insert(index)
        }
        return changed
    }

    /// Fields whose value differs from the loaded file.
    public var modifiedFields: Set<FieldID> {
        let changed = modifiedLineIndices
        return Set(fieldMap.filter { changed.contains($0.value) }.keys)
    }

    // MARK: - Serializing

    /// Rebuild the file bytes. Structurally identical to what `init` verified, so the only
    /// possible differences are the lines that were deliberately edited.
    public func serialized() -> Data {
        Self.assemble(
            lines: lines,
            lineEnding: lineEnding,
            hadTrailingNewline: hadTrailingNewline,
            encoding: encoding
        )
    }

    private static func assemble(
        lines: [String],
        lineEnding: String,
        hadTrailingNewline: Bool,
        encoding: String.Encoding
    ) -> Data {
        var text = lines.joined(separator: lineEnding)
        if hadTrailingNewline { text += lineEnding }
        return text.data(using: encoding) ?? Data()
    }

    private static func firstDifference(_ lhs: Data, _ rhs: Data) -> Int {
        let limit = min(lhs.count, rhs.count)
        var index = 0
        while index < limit, lhs[lhs.startIndex + index] == rhs[rhs.startIndex + index] {
            index += 1
        }
        return index
    }
}

extension StringProtocol {
    /// Trailing run of characters satisfying `predicate`, in original order.
    func suffix(while predicate: (Character) -> Bool) -> String {
        String(reversed().prefix(while: predicate).reversed())
    }
}
