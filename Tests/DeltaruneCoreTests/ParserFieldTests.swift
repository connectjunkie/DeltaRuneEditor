import Foundation
import Testing
@testable import DeltaruneCore

/// Checks the field map lands where it should.
///
/// These assert properties true of *any* valid save rather than values from one
/// playthrough, so they hold whichever save folder you supply.
@Suite("Parser field mapping", .enabled(if: Fixtures.arePresent))
struct ParserFieldTests {

    @Test("Names parse and can't contain a line break", arguments: Fixtures.saves)
    func parsesNames(save: Fixtures.Save) throws {
        let document = try save.document()
        let player = try #require(document.string(.playerName))
        let vessel = try #require(document.string(.vesselName))

        // A line break in either would shift every subsequent line.
        #expect(!player.contains("\n") && !player.contains("\r"))
        #expect(!vessel.contains("\n") && !vessel.contains("\r"))
    }

    @Test("The party lineup holds real character ids", arguments: Fixtures.saves)
    func parsesParty(save: Fixtures.Save) throws {
        let document = try save.document()

        for slot in 0..<3 {
            let id = try #require(document.int(.party(slot)))
            #expect(id == 0 || document.format.characterSlots.contains(id),
                    "party slot \(slot) points at character \(id)")
        }
    }

    @Test("The numeric header fields all parse", arguments: Fixtures.saves)
    func parsesHeaderNumbers(save: Fixtures.Save) throws {
        let document = try save.document()

        #expect(document.int(.money) != nil)
        #expect(document.int(.lv) != nil)
        #expect(document.int(.xp) != nil)
        #expect(document.bool(.inDarkWorld) != nil)
    }

    /// The strongest structural check available without running the game: the final three
    /// lines are plot/room/time, and `dr.ini` independently records the same room and name
    /// for the same slot. If the flag count — or anything before it — were off by even one
    /// line, these would disagree.
    @Test("The tail fields agree with dr.ini", arguments: Fixtures.saves)
    func tailAgreesWithIni(save: Fixtures.Save) throws {
        guard let section = Fixtures.iniSection(for: save) else { return }
        let ini = try Fixtures.drIni()
        let document = try save.document()

        let room = try #require(document.int(.room))
        #expect(Double(room) == ini.number(section: section, key: "Room"))
        #expect(document.string(.playerName) == ini.value(section: section, key: "Name"))
        #expect(document.double(.plot) != nil)
        #expect(document.double(.time) != nil)
    }

    @Test("The flag array is at least as large as the format requires", arguments: Fixtures.saves)
    func flagCount(save: Fixtures.Save) throws {
        let document = try save.document()

        #expect(document.flagCount >= document.format.minimumFlagCount)
        // Every flag is addressable, and there is no flag one past the end.
        #expect(document.fieldMap[.flag(document.flagCount - 1)] != nil)
        #expect(document.fieldMap[.flag(document.flagCount)] == nil)
    }

    @Test("Every character has a full stat block", arguments: Fixtures.saves)
    func parsesCharacterStats(save: Fixtures.Save) throws {
        let document = try save.document()
        let format = document.format

        for character in 0..<format.characterCount {
            #expect(document.int(.charMaxHealth(character)) != nil)
            #expect(document.int(.charAttack(character)) != nil)
            #expect(document.int(.charDefence(character)) != nil)
            for index in 0..<12 {
                #expect(document.fieldMap[.charSpell(character: character, index: index)] != nil)
            }
        }

        // And no stat block beyond the format's character count.
        #expect(document.fieldMap[.charHealth(format.characterCount)] == nil)
    }

    @Test("Inventory shape matches the format", arguments: Fixtures.saves)
    func parsesInventoryShape(save: Fixtures.Save) throws {
        let document = try save.document()

        func count(_ make: (Int) -> FieldID) -> Int {
            var found = 0
            while document.fieldMap[make(found)] != nil { found += 1 }
            return found
        }

        #expect(count(FieldID.invConsumable) == 13)
        #expect(count(FieldID.invKeyItem) == 13)

        switch document.format {
        case .v1:
            #expect(count(FieldID.invWeapon) == 13)
            #expect(count(FieldID.invArmor) == 13)
            #expect(count(FieldID.invStorage) == 0)
        case .v2:
            #expect(count(FieldID.invWeapon) == 48)
            #expect(count(FieldID.invArmor) == 48)
            #expect(count(FieldID.invStorage) == 72)
        }
    }

    @Test("Weapon stat entries gain two fields in V2", arguments: Fixtures.saves)
    func weaponStatFieldCount(save: Fixtures.Save) throws {
        let document = try save.document()
        let hasElement = document.fieldMap[
            .charWeaponStat(character: 0, slot: 0, field: .element)
        ] != nil

        #expect(hasElement == (document.format == .v2))
    }
}
