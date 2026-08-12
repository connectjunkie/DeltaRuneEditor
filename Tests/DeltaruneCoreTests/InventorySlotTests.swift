import Foundation
import Testing
@testable import DeltaruneCore

/// The inventory arrays hold one more entry than the player can use. That last entry is an
/// end-of-list marker the game writes as 999, and putting an item in it corrupts the
/// inventory — the exact kind of mistake a save editor makes and a player pays for.
@Suite("Inventory terminator slots", .enabled(if: Fixtures.arePresent))
struct InventorySlotTests {

    @Test("The consumable terminator is 999 in every save", arguments: Fixtures.saves)
    func consumableTerminatorIs999(save: Fixtures.Save) throws {
        let document = try save.document()
        #expect(document.int(.invConsumable(12)) == SaveFormat.terminatorValue)
    }

    @Test("Chapter 1 also terminates its weapon and armour arrays", arguments: Fixtures.saves)
    func chapter1TerminatesWeaponsAndArmors(save: Fixtures.Save) throws {
        let document = try save.document()
        guard document.format == .v1 else { return }

        #expect(document.int(.invWeapon(12)) == SaveFormat.terminatorValue)
        #expect(document.int(.invArmor(12)) == SaveFormat.terminatorValue)
    }

    @Test("Terminator slots are refused", arguments: Fixtures.saves)
    func terminatorSlotsCannotBeWritten(save: Fixtures.Save) throws {
        var document = try save.document()

        #expect(!document.isEditable(.invConsumable(12)))
        #expect(throws: (any Error).self) { try document.set(.invConsumable(12), to: 5) }

        if document.format == .v1 {
            #expect(!document.isEditable(.invWeapon(12)))
            #expect(throws: (any Error).self) { try document.set(.invWeapon(12), to: 5) }
        }

        #expect(document.isModified == false, "a refused write must change nothing")
    }

    @Test("Ordinary slots stay editable", arguments: Fixtures.saves)
    func usableSlotsAreEditable(save: Fixtures.Save) throws {
        var document = try save.document()

        for slot in 0..<12 {
            #expect(document.isEditable(.invConsumable(slot)))
        }
        try document.set(.invConsumable(0), to: 1)
        try document.set(.invConsumable(11), to: 2)
        #expect(document.modifiedLineIndices.count == 2)
    }

    @Test("Usable slot counts match the layout", arguments: Fixtures.saves)
    func usableSlotCounts(save: Fixtures.Save) throws {
        let document = try save.document()

        #expect(document.usableSlots(for: .consumables) == 0..<12)
        #expect(document.usableSlots(for: .keyItems) == 0..<12)

        switch document.format {
        case .v1:
            #expect(document.usableSlots(for: .weapons) == 0..<12)
            #expect(document.usableSlots(for: .armors) == 0..<12)
        case .v2:
            #expect(document.usableSlots(for: .weapons) == 0..<48)
            #expect(document.usableSlots(for: .armors) == 0..<48)
        }
    }

    @Test("Filling the inventory leaves the terminator alone")
    func editingDoesNotDisturbTerminator() throws {
        var document = try #require(Fixtures.any).document()
        let terminatorLine = document.rawLine(.invConsumable(12))

        for slot in document.usableSlots(for: .consumables) {
            try document.set(.invConsumable(slot), to: 1)
        }

        #expect(document.rawLine(.invConsumable(12)) == terminatorLine)
        #expect(document.int(.invConsumable(12)) == SaveFormat.terminatorValue)
    }
}
