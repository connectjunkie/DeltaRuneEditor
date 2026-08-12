import Foundation

/// `dr.ini`, the small file next to the saves that drives the file-select screen.
///
/// It holds one section per slot (`[G0]` for Chapter 1, `[G_2_0]` for Chapter 2 onward)
/// with the name, level and playtime the game shows before loading, plus unrelated
/// sections such as `[VHS]` and `[URA]`.
///
/// Same discipline as `SaveDocument`: the original lines are kept verbatim, edits patch
/// individual lines, and loading is gated on being able to reproduce the file byte for
/// byte. Sections we know nothing about therefore survive untouched.
public struct DrIni: Sendable {
    public let originalBytes: Data
    public let lineEnding: String
    public let hadTrailingNewline: Bool
    public let encoding: String.Encoding

    public private(set) var lines: [String]
    private let pristineLines: [String]

    /// Section name in file order.
    public let sectionOrder: [String]
    /// Section name → key → line index.
    public let sections: [String: [String: Int]]

    // MARK: - Loading

    public init(bytes: Data) throws {
        guard let text = String(data: bytes, encoding: .utf8)
                ?? String(data: bytes, encoding: .isoLatin1) else {
            throw SaveDocumentError.unreadableEncoding
        }
        self.originalBytes = bytes
        self.encoding = String(data: bytes, encoding: .utf8) != nil ? .utf8 : .isoLatin1

        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        self.lineEnding = lineEnding

        var split = text.components(separatedBy: lineEnding)
        let trailing = split.count > 1 && split.last == ""
        if trailing { split.removeLast() }
        self.hadTrailingNewline = trailing
        self.lines = split
        self.pristineLines = split

        var order: [String] = []
        var parsed: [String: [String: Int]] = [:]
        var current: String?

        for (index, line) in split.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                let name = String(trimmed.dropFirst().dropLast())
                current = name
                if parsed[name] == nil {
                    parsed[name] = [:]
                    order.append(name)
                }
            } else if let section = current,
                      let separator = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<separator])
                    .trimmingCharacters(in: .whitespaces)
                parsed[section]?[key] = index
            }
        }

        self.sectionOrder = order
        self.sections = parsed

        let rebuilt = Self.assemble(
            lines: split,
            lineEnding: lineEnding,
            hadTrailingNewline: trailing,
            encoding: encoding
        )
        guard rebuilt == bytes else {
            throw SaveDocumentError.roundTripMismatch(firstDifferingByte: 0)
        }
    }

    public init(contentsOf url: URL) throws {
        try self.init(bytes: try Data(contentsOf: url))
    }

    // MARK: - Reading

    /// Raw value with surrounding quotes removed.
    public func value(section: String, key: String) -> String? {
        guard let index = sections[section]?[key],
              let separator = lines[index].firstIndex(of: "=") else { return nil }

        var raw = String(lines[index][lines[index].index(after: separator)...])
            .trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
            raw = String(raw.dropFirst().dropLast())
        }
        return raw
    }

    public func number(section: String, key: String) -> Double? {
        value(section: section, key: key).flatMap(Double.init)
    }

    public func value(for save: SaveFileName, key: String) -> String? {
        value(section: save.iniSectionName, key: key)
    }

    public func number(for save: SaveFileName, key: String) -> Double? {
        number(section: save.iniSectionName, key: key)
    }

    public func hasSection(_ name: String) -> Bool { sections[name] != nil }

    // MARK: - Writing

    /// Replace one key's value, keeping the line's original key spelling and spacing.
    /// Only an existing key can be set — this never adds lines, so it can never shift the
    /// file's structure.
    public mutating func set(section: String, key: String, toRaw value: String) throws {
        guard let index = sections[section]?[key] else {
            throw SaveDocumentError.unknownField("\(section).\(key)")
        }
        let line = lines[index]
        guard let separator = line.firstIndex(of: "=") else {
            throw SaveDocumentError.unknownField("\(section).\(key)")
        }
        let prefix = String(line[line.startIndex...separator])
        lines[index] = prefix + "\"" + value + "\""
    }

    /// Numbers in `dr.ini` are written as quoted six-decimal reals.
    public mutating func set(section: String, key: String, to value: Double) throws {
        try set(section: section, key: key, toRaw: String(format: "%.6f", value))
    }

    public mutating func setString(section: String, key: String, to value: String) throws {
        let sanitized = value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "")
        try set(section: section, key: key, toRaw: sanitized)
    }

    public mutating func revertAll() { lines = pristineLines }

    public var isModified: Bool { lines != pristineLines }

    public var modifiedLineIndices: Set<Int> {
        var changed: Set<Int> = []
        for index in lines.indices where lines[index] != pristineLines[index] {
            changed.insert(index)
        }
        return changed
    }

    // MARK: - Serializing

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
}

extension DrIni {
    /// Keys the file-select screen reads.
    public enum Key {
        public static let name = "Name"
        public static let level = "Level"
        public static let love = "Love"
        public static let time = "Time"
        public static let date = "Date"
        public static let room = "Room"
    }

    /// GameMaker counts days from 1899-12-30, the same origin spreadsheets use.
    static let gameMakerEpochOffsetDays = 25_569.0

    /// When this slot was last saved, as the game recorded it.
    ///
    /// This is the same value the file-select screen shows, and unlike a file's
    /// modification time it survives copying the folder between Macs, AirDrop and Steam
    /// Cloud sync — all of which rewrite timestamps.
    public func lastPlayed(for save: SaveFileName) -> Date? {
        guard let raw = number(for: save, key: Key.date), raw > 0 else { return nil }

        // GameMaker writes local time, so convert as local rather than UTC.
        let naive = (raw - Self.gameMakerEpochOffsetDays) * 86_400
        let offset = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: naive))
        return Date(timeIntervalSince1970: naive - Double(offset))
    }

    /// Bring the slot metadata back in line with an edited save, so the file-select screen
    /// doesn't show stale values. Only keys already present are touched.
    public mutating func sync(with document: SaveDocument, for save: SaveFileName) throws {
        let section = save.iniSectionName
        guard hasSection(section) else { return }

        if let name = document.string(.playerName), sections[section]?[Key.name] != nil {
            try setString(section: section, key: Key.name, to: name)
        }
        if let level = document.double(.lv), sections[section]?[Key.level] != nil {
            try set(section: section, key: Key.level, to: level)
        }
        if let love = document.double(.lightLevel), sections[section]?[Key.love] != nil {
            try set(section: section, key: Key.love, to: love)
        }
    }
}
