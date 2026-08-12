import Foundation

/// One item, weapon, armour, spell or character the game knows about.
public struct GameItem: Codable, Sendable, Identifiable, Hashable {
    /// The number stored in the save file.
    public let id: Int
    /// Internal name, e.g. `DARK_CANDY`. Useful for debugging, never shown.
    public let key: String
    /// Name as the game shows it, e.g. `Dark Candy`.
    public let name: String
    /// Chapters where the name differs, keyed by chapter number as a string.
    public let namesByChapter: [String: String]?

    /// The name this item goes by in a given chapter. Dark Candy is "Darker Candy" from
    /// Chapter 4 onward, and showing the wrong one is confusing for a child comparing the
    /// app against the screen.
    public func name(inChapter chapter: Int) -> String {
        namesByChapter?[String(chapter)] ?? name
    }

    /// True for the id that means "nothing in this slot".
    public var isEmpty: Bool { id == 0 }
}

/// The categories of thing a save file can refer to by number.
public enum ItemCategory: String, Sendable, CaseIterable {
    case consumables
    case keyItems
    case weapons
    case armors
    case spells
    case characters
    case lightWorldItems

    /// Heading shown above the picker.
    public var friendlyName: String {
        switch self {
        case .consumables: "Items"
        case .keyItems: "Key Items"
        case .weapons: "Weapons"
        case .armors: "Armour"
        case .spells: "Spells"
        case .characters: "Characters"
        case .lightWorldItems: "Light World Items"
        }
    }
}

/// A place in the game, so the app can say "Cold Place" instead of "room 30108".
public struct RoomEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let key: String
    public let name: String
}

/// A named story milestone within a chapter.
///
/// `value` is a Double, not an Int: the game uses fractional plot numbers to slot extra
/// beats between existing ones — Chapter 4 alone has 238.1, 238.2, 238.5, 238.61, 238.65.
/// Modelling it as an integer makes `JSONDecoder` reject the whole table.
public struct PlotPoint: Codable, Sendable, Hashable {
    public let value: Double
    public let name: String
    public var unused: Bool?
}

/// Name tables generated from tenna-editor by `Tools/export-game-data.mjs`.
///
/// This is what turns `26` into "Dark Candy" in the UI. Loaded once from the bundled
/// JSON; if the resource is somehow missing the app still runs, just showing raw numbers
/// rather than refusing to start.
public struct GameData: Codable, Sendable {
    public let source: String
    public let chapters: [Int]

    public let consumables: [GameItem]
    public let keyItems: [GameItem]
    public let weapons: [GameItem]
    public let armors: [GameItem]
    public let spells: [GameItem]
    public let characters: [GameItem]
    public let lightWorldItems: [GameItem]

    public let rooms: [RoomEntry]
    /// Chapter number (as a string key) to that chapter's milestones, ascending.
    public let plotPoints: [String: [PlotPoint]]

    private enum CodingKeys: String, CodingKey {
        case source, chapters
        case consumables, keyItems, weapons, armors, spells, characters, lightWorldItems
        case rooms, plotPoints
    }

    public static let empty = GameData(
        source: "none", chapters: [],
        consumables: [], keyItems: [], weapons: [], armors: [],
        spells: [], characters: [], lightWorldItems: [],
        rooms: [], plotPoints: [:]
    )

    /// Result of loading the bundled tables, including why it failed if it did.
    ///
    /// Falling back to empty silently is tempting but wrong: the app would start up
    /// looking fine and label every item "Unknown", with nothing to explain it. The
    /// reason is kept so a test can assert on it and Advanced can show it.
    public struct Load: Sendable {
        public let data: GameData
        public let error: String?
    }

    private static let load: Load = {
        guard let url = Bundle.module.url(forResource: "gamedata", withExtension: "json") else {
            return Load(data: .empty, error: "gamedata.json is missing from the bundle")
        }
        do {
            let bytes = try Data(contentsOf: url)
            return Load(data: try JSONDecoder().decode(GameData.self, from: bytes), error: nil)
        } catch {
            return Load(data: .empty, error: "\(error)")
        }
    }()

    /// Loaded from the app bundle once, on first use.
    public static var shared: GameData { load.data }

    /// Nil when the tables loaded cleanly.
    public static var loadError: String? { load.error }

    // MARK: - Where you are

    /// Built once; 1,000 rooms is too many to scan on every SwiftUI redraw.
    private static let roomsByID: [Int: RoomEntry] =
        Dictionary(shared.rooms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Human name for a room id, e.g. 30108 → "Cold Place".
    public func roomName(_ id: Int) -> String? {
        Self.roomsByID[id]?.name
    }

    /// The furthest named milestone at or before `plot`.
    ///
    /// Saved plot values often sit between milestones — the game increments them in small
    /// steps — so an exact lookup usually finds nothing. Taking the highest one at or
    /// below the current value degrades gracefully to "the last thing that happened"
    /// rather than showing a bare number.
    public func milestone(chapter: Int, plot: Double) -> PlotPoint? {
        guard let points = plotPoints[String(chapter)] else { return nil }
        return points.last { $0.value <= plot && $0.unused != true }
    }

    /// One line describing where the player is, for the header.
    public func whereYouAre(chapter: Int, room: Int?, plot: Double?) -> String? {
        var parts: [String] = []
        if let room, let name = roomName(room) { parts.append(name) }
        if let plot, let milestone = milestone(chapter: chapter, plot: plot) {
            parts.append(milestone.name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public func items(in category: ItemCategory) -> [GameItem] {
        switch category {
        case .consumables: consumables
        case .keyItems: keyItems
        case .weapons: weapons
        case .armors: armors
        case .spells: spells
        case .characters: characters
        case .lightWorldItems: lightWorldItems
        }
    }

    public func item(_ id: Int, in category: ItemCategory) -> GameItem? {
        items(in: category).first { $0.id == id }
    }

    /// Display name for a stored number, falling back to the number itself so an unknown
    /// id from a newer game version still shows something meaningful.
    public func name(for id: Int, in category: ItemCategory, chapter: Int) -> String {
        item(id, in: category)?.name(inChapter: chapter) ?? "Unknown (\(id))"
    }

    /// Options for a picker, "Empty" first and the rest alphabetical so a child can scan
    /// them. Ids the game no longer uses still appear if they're already in the save.
    public func pickerOptions(
        in category: ItemCategory,
        chapter: Int,
        including currentID: Int? = nil
    ) -> [GameItem] {
        var options = items(in: category)
        if let currentID, !options.contains(where: { $0.id == currentID }) {
            options.append(
                GameItem(id: currentID, key: "UNKNOWN", name: "Unknown (\(currentID))",
                         namesByChapter: nil)
            )
        }
        return options.sorted {
            if $0.isEmpty != $1.isEmpty { return $0.isEmpty }
            return $0.name(inChapter: chapter).localizedCaseInsensitiveCompare(
                $1.name(inChapter: chapter)
            ) == .orderedAscending
        }
    }
}
