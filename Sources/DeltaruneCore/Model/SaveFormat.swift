import Foundation

/// DELTARUNE ships two save layouts, distinguished only by total line count.
///
/// Both are flat, positional lists of text lines with no keys or delimiters — a cursor
/// walks them from the top. V2 arrived with Chapter 2 and is used by Chapters 2 onward.
public enum SaveFormat: Int, Sendable, CaseIterable {
    /// Chapter 1. 10,318 lines, 4 characters, inventory interleaved 4-wide.
    case v1 = 1
    /// Chapters 2–5. 3,055 lines, 5 characters, separate weapon/armor and storage blocks.
    case v2 = 2

    /// Number of character stat blocks stored in the file, including the unused one.
    public var characterCount: Int {
        switch self {
        case .v1: 4
        case .v2: 5
        }
    }

    /// Blocks holding an actual character.
    ///
    /// Stat blocks are indexed by **character id**, not by party position:
    /// `0 = EMPTY, 1 = Kris, 2 = Susie, 3 = Ralsei, 4 = Noelle`. Block 0 is a placeholder
    /// for the empty character and holds junk — `maxHealth` of 0 in every real save — so
    /// anything showing characters to the player must start at 1. Chapter 1 stores four
    /// blocks because Noelle isn't in it yet; Chapters 2+ store five.
    ///
    /// Getting this wrong labels the empty slot "Kris" and shifts every real character
    /// down one, which is exactly what shipped in the first build.
    public var characterSlots: Range<Int> {
        1..<characterCount
    }

    /// Fields per weapon-stat entry. V2 appends `element` and `elementAmount`.
    public var weaponStatFieldCount: Int {
        switch self {
        case .v1: 8
        case .v2: 10
        }
    }

    /// Canonical line count. Real files vary slightly, hence the accepted range below.
    public var expectedTotalLines: Int {
        switch self {
        case .v1: 10_318
        case .v2: 3_055
        }
    }

    /// Accepted total line counts. Widened from the canonical value because demo-era and
    /// patch-era files differ by a handful of trailing lines.
    public var acceptedLineCounts: ClosedRange<Int> {
        switch self {
        case .v1: 10_311...10_328
        case .v2: 3_046...3_065
        }
    }

    /// Lower bound on the flag array size, used to sanity-check the parse.
    public var minimumFlagCount: Int {
        switch self {
        case .v1: 9_999
        case .v2: 2_500
        }
    }

    // MARK: - Inventory slots
    //
    // The 13-entry arrays only hold 12 usable items. The final slot is an end-of-list
    // terminator the game writes as 999 — confirmed as 999 in every real save file, for
    // consumables in both formats and for weapons and armour in V1. Writing an item there
    // would corrupt the inventory, so those slots are parsed but never editable.

    /// Entries actually stored per 13-wide array, terminator included.
    public static let storedShortInventorySlots = 13
    /// Value the game writes in the terminator slot.
    public static let terminatorValue = 999

    public var usableConsumableSlots: Int { 12 }
    public var usableKeyItemSlots: Int { 12 }

    public var usableWeaponSlots: Int {
        switch self {
        case .v1: 12          // 13 stored, last is the terminator
        case .v2: 48          // separate wider block, no terminator observed
        }
    }

    public var usableArmorSlots: Int { usableWeaponSlots }

    public var usableStorageSlots: Int {
        switch self {
        case .v1: 0
        case .v2: 72
        }
    }

    /// Chapters that use this layout.
    public var chapters: ClosedRange<Int> {
        switch self {
        case .v1: 1...1
        case .v2: 2...5
        }
    }

    /// Identify the layout purely from the number of lines. Returns `nil` — rather than
    /// guessing — when the count matches neither, so unknown files fail closed.
    public static func detect(lineCount: Int) -> SaveFormat? {
        allCases.first { $0.acceptedLineCounts.contains(lineCount) }
    }

    /// Layout used by a given chapter number.
    public static func forChapter(_ chapter: Int) -> SaveFormat? {
        allCases.first { $0.chapters.contains(chapter) }
    }
}
