import Foundation
import Testing
@testable import DeltaruneCore

/// Assertions about *meaning*, not structure.
///
/// The round-trip gate proves the right lines are read; it said nothing about whether the
/// right names are attached to them. That gap once shipped a build where the unused
/// character slot was labelled "Kris" and every real character was shifted down one.
@Suite("Character slots", .enabled(if: Fixtures.arePresent))
struct CharacterSlotTests {

    @Test("Block 0 is the unused empty slot in every save", arguments: Fixtures.saves)
    func blockZeroIsEmpty(save: Fixtures.Save) throws {
        let document = try save.document()

        // A real character always has max HP. The placeholder never does.
        #expect(document.int(.charMaxHealth(0)) == 0)
        #expect(document.int(.charWeapon(0)) == 0)
    }

    @Test("Every real character slot has stats", arguments: Fixtures.saves)
    func realSlotsHaveStats(save: Fixtures.Save) throws {
        let document = try save.document()

        for slot in document.format.characterSlots {
            let maxHealth = try #require(document.int(.charMaxHealth(slot)))
            #expect(maxHealth > 0, "slot \(slot) in \(save.name) has no max HP")
        }
    }

    @Test("Chapter 1 exposes three characters, Chapter 2+ exposes four", arguments: Fixtures.saves)
    func characterSlotCount(save: Fixtures.Save) throws {
        let document = try save.document()

        switch document.format {
        case .v1:
            #expect(document.format.characterSlots == 1..<4)
        case .v2:
            #expect(document.format.characterSlots == 1..<5)
        }
        // The unused slot is excluded, so there is always one fewer than stored.
        #expect(document.format.characterSlots.count == document.format.characterCount - 1)
    }

    /// The slots must line up with the ids in the item tables, because that's how the UI
    /// turns a slot into a name. This reads the committed game data, not a save.
    @Test("Slot indices match the character ids in the game data")
    func slotsMatchGameDataIDs() {
        let expected = [1: "Kris", 2: "Susie", 3: "Ralsei", 4: "Noelle"]

        for (id, name) in expected {
            #expect(GameData.shared.characters.first { $0.id == id }?.name == name)
        }
        #expect(GameData.shared.characters.first { $0.id == 0 }?.name == "Empty")
    }

    @Test("Healing everyone skips the unused slot")
    func healingSkipsEmptySlot() throws {
        var document = try #require(Fixtures.any).document()
        let emptyBefore = document.rawLine(.charHealth(0))

        for slot in document.format.characterSlots {
            try document.healToFull(slot)
        }

        #expect(document.rawLine(.charHealth(0)) == emptyBefore)
        for slot in document.format.characterSlots {
            #expect(document.int(.charHealth(slot)) == document.int(.charMaxHealth(slot)))
        }
    }
}
