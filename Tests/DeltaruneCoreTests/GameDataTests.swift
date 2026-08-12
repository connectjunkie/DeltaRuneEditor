import Foundation
import Testing
@testable import DeltaruneCore

@Suite("Game data")
struct GameDataTests {

    private var data: GameData { GameData.shared }

    @Test("The bundled table actually loads")
    func loadsBundledResource() {
        #expect(GameData.loadError == nil, "\(GameData.loadError ?? "")")
        #expect(data.source != "none", "gamedata.json missing from the bundle")
        #expect(data.chapters == [1, 2, 3, 4, 5])
    }

    @Test("Every category has entries", arguments: ItemCategory.allCases)
    func everyCategoryPopulated(category: ItemCategory) {
        #expect(!data.items(in: category).isEmpty)
    }

    @Test("Ids are unique within a category", arguments: ItemCategory.allCases)
    func idsAreUnique(category: ItemCategory) {
        let ids = data.items(in: category).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Id 0 is the empty slot in every category", arguments: ItemCategory.allCases)
    func zeroIsEmpty(category: ItemCategory) throws {
        let empty = try #require(data.item(0, in: category))
        #expect(empty.isEmpty)
        #expect(empty.name == "Empty")
    }

    @Test("Names match what the game shows")
    func knownNames() {
        #expect(data.name(for: 1, in: .consumables, chapter: 1) == "Dark Candy")
        #expect(data.name(for: 2, in: .consumables, chapter: 1) == "ReviveMint")
        #expect(data.name(for: 1, in: .characters, chapter: 1) == "Kris")
        #expect(data.name(for: 2, in: .characters, chapter: 1) == "Susie")
        #expect(data.name(for: 3, in: .characters, chapter: 1) == "Ralsei")
        #expect(data.name(for: 4, in: .characters, chapter: 1) == "Noelle")
        #expect(data.name(for: 1, in: .weapons, chapter: 1) == "Wood Blade")
        #expect(data.name(for: 1, in: .armors, chapter: 1) == "Amber Card")
    }

    @Test("Items renamed in later chapters resolve per chapter")
    func perChapterNames() {
        #expect(data.name(for: 1, in: .consumables, chapter: 1) == "Dark Candy")
        #expect(data.name(for: 1, in: .consumables, chapter: 3) == "Dark Candy")
        #expect(data.name(for: 1, in: .consumables, chapter: 4) == "Darker Candy")
        #expect(data.name(for: 1, in: .consumables, chapter: 5) == "Darker Candy")
    }

    // MARK: - Where you are

    @Test("Rooms resolve to the names the game uses")
    func roomNames() {
        #expect(data.roomName(30_108) == "Cold Place")
        #expect(data.roomName(10_407) == "Card Castle - Throne")
        #expect(data.roomName(20_072) == "My Castle Town")
        #expect(data.roomName(999_999) == nil)
    }

    @Test("Plot values resolve to the story milestone reached")
    func plotMilestones() {
        #expect(data.milestone(chapter: 3, plot: 290)?.name == "Tenna Prefight Speech Started")
        #expect(data.milestone(chapter: 1, plot: 175)?.name == "Defeated K. Round 2")
    }

    /// Saved plot values sit between named milestones, so an exact match usually misses.
    @Test("A plot value between milestones reports the last one reached")
    func plotFallsBackToPreviousMilestone() {
        let exact = data.milestone(chapter: 3, plot: 290)
        let between = data.milestone(chapter: 3, plot: 295)
        #expect(between?.name == exact?.name)
    }

    /// The game slots extra story beats between whole numbers. Modelling these as
    /// integers made JSONDecoder reject the entire table.
    @Test("Fractional plot values are supported")
    func fractionalPlotValues() {
        let chapter4 = try? #require(data.plotPoints["4"])
        #expect(chapter4?.contains { $0.value == 238.1 } == true)
        #expect(data.milestone(chapter: 4, plot: 238.1)?.name == "Walking on Walls Room")
        #expect(data.milestone(chapter: 4, plot: 238.62)?.name == "Climbed First Cylinder Tower")
        #expect(data.milestone(chapter: 2, plot: 65.5)?.name == "Learned About Storage")
    }

    @Test("Where-you-are reads as one line")
    func whereYouAreLine() {
        #expect(data.whereYouAre(chapter: 3, room: 30_108, plot: 290)
                == "Cold Place · Tenna Prefight Speech Started")
        #expect(data.whereYouAre(chapter: 3, room: nil, plot: nil) == nil)
        #expect(data.whereYouAre(chapter: 3, room: 30_108, plot: nil) == "Cold Place")
    }

    @Test("Every fixture can say where it is",
          .enabled(if: Fixtures.arePresent), arguments: Fixtures.saves)
    func everyFixtureResolves(save: Fixtures.Save) throws {
        let document = try save.document()
        let line = data.whereYouAre(
            chapter: save.chapter,
            room: document.int(.room),
            plot: document.double(.plot)
        )
        #expect(line != nil, "\(save.name) reports no location")
    }

    @Test("An id the tables don't know still shows something")
    func unknownIdFallsBack() {
        #expect(data.name(for: 9_999, in: .consumables, chapter: 2) == "Unknown (9999)")
        #expect(data.item(9_999, in: .consumables) == nil)
    }

    @Test("Picker options put Empty first, then alphabetical")
    func pickerOrdering() throws {
        let options = data.pickerOptions(in: .consumables, chapter: 2)

        #expect(options.first?.isEmpty == true)
        let names = options.dropFirst().map { $0.name(inChapter: 2) }
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test("An unknown id already in the save is offered rather than silently dropped")
    func pickerIncludesUnknownCurrentValue() {
        let options = data.pickerOptions(in: .weapons, chapter: 2, including: 4_242)
        #expect(options.contains { $0.id == 4_242 })
        #expect(options.count == data.items(in: .weapons).count + 1)
    }

    /// Ties the tables back to real save data: every equipment and inventory id in the
    /// fixtures should be one the tables can name.
    @Test("Every id used by the real saves is in the tables",
          .enabled(if: Fixtures.arePresent), arguments: Fixtures.saves)
    func realSaveIdsAreKnown(save: Fixtures.Save) throws {
        let document = try save.document()
        var unknown: [String] = []

        func check(_ field: FieldID, _ category: ItemCategory) {
            guard let id = document.int(field), id != 0 else { return }
            if data.item(id, in: category) == nil {
                unknown.append("\(category.rawValue) id \(id)")
            }
        }

        for slot in 0..<3 { check(.party(slot), .characters) }
        for character in 0..<document.format.characterCount {
            check(.charWeapon(character), .weapons)
            check(.charPrimaryArmor(character), .armors)
            check(.charSecondaryArmor(character), .armors)
        }
        // Only the usable slots — slot 12 holds the 999 end-of-list marker, which is
        // deliberately not an item id. See InventorySlotTests.
        for index in document.usableSlots(for: .consumables) {
            check(.invConsumable(index), .consumables)
        }
        for index in document.usableSlots(for: .keyItems) {
            check(.invKeyItem(index), .keyItems)
        }

        #expect(unknown.isEmpty, "\(unknown)")
    }
}
