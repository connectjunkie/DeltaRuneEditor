import Foundation

/// A save file in the game folder, identified by its filename.
///
/// Names look like `filech2_0`, `filech1_3`, `filech3_9`, or `filech5_3_b` for Chapter 5's
/// alternate route.
public struct SaveFileName: Hashable, Sendable, CustomStringConvertible {
    public let chapter: Int
    /// Raw slot as it appears in the filename: 0–2 saves, 3–5 completion files, 9 autosave.
    public let rawSlot: Int
    /// Chapter 5 Weird Route variant (`_b` suffix).
    public let isAlternateRoute: Bool

    public init(chapter: Int, rawSlot: Int, isAlternateRoute: Bool = false) {
        self.chapter = chapter
        self.rawSlot = rawSlot
        self.isAlternateRoute = isAlternateRoute
    }

    public init?(_ filename: String) {
        let name = filename.lowercased()
        guard name.hasPrefix("filech") else { return nil }

        var body = String(name.dropFirst("filech".count))
        var alternate = false
        if body.hasSuffix("_b") {
            body = String(body.dropLast(2))
            alternate = true
        }

        let parts = body.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let chapter = Int(parts[0]), (1...5).contains(chapter),
              let rawSlot = Int(parts[1]), (0...9).contains(rawSlot),
              rawSlot <= 5 || rawSlot == 9
        else { return nil }

        self.init(chapter: chapter, rawSlot: rawSlot, isAlternateRoute: alternate)
    }

    public var filename: String {
        "filech\(chapter)_\(rawSlot)\(isAlternateRoute ? "_b" : "")"
    }

    public var description: String { filename }

    /// The layout this file uses.
    public var format: SaveFormat? { SaveFormat.forChapter(chapter) }

    public enum Kind: Sendable {
        case save           // slots 0–2
        case completion     // slots 3–5
        case autosave       // slot 9
    }

    public var kind: Kind {
        switch rawSlot {
        case 0...2: .save
        case 3...5: .completion
        default: .autosave
        }
    }

    /// Slot number as the player sees it on the file-select screen: 1, 2 or 3.
    public var displaySlot: Int {
        switch kind {
        case .save: rawSlot + 1
        case .completion: rawSlot - 2
        case .autosave: 1
        }
    }

    /// Wording a nine-year-old can act on.
    public var friendlyName: String {
        switch kind {
        case .save: "Chapter \(chapter) — Save \(displaySlot)"
        case .completion: "Chapter \(chapter) — Finished file \(displaySlot)"
        case .autosave: "Chapter \(chapter) — Autosave"
        }
    }

    /// Matching section name in `dr.ini`. Chapter 1 uses the short form.
    public var iniSectionName: String {
        chapter == 1 ? "G\(rawSlot)" : "G_\(chapter)_\(rawSlot)"
    }
}
