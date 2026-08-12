import Foundation
import Testing
@testable import DeltaruneCore

@Suite("Edit policy")
struct EditPolicyTests {

    @Test("Values are held inside their range")
    func clampsToRange() {
        #expect(EditPolicy.clamp(10_000_000, for: .money) == 999_999)
        #expect(EditPolicy.clamp(-50, for: .money) == 0)
        #expect(EditPolicy.clamp(500, for: .money) == 500)
        #expect(EditPolicy.clamp(0, for: .charMaxHealth(1)) == 1)
        #expect(EditPolicy.clamp(99_999, for: .charAttack(0)) == 999)
        #expect(EditPolicy.clamp(7, for: .party(0)) == 4)
    }

    @Test("Fields the simple UI doesn't offer are left alone")
    func unrangedFieldsPassThrough() {
        #expect(EditPolicy.range(for: .flag(10)) == nil)
        #expect(EditPolicy.clamp(123_456_789, for: .flag(10)) == 123_456_789)
    }

    /// Keeping the simple UI under a million means it never has to emit `1.5e+06`.
    @Test("Clamped values never reach exponential notation")
    func clampedValuesStayPlain() {
        for field in [FieldID.money, .xp, .lv, .charMaxHealth(1)] {
            let clamped = EditPolicy.clamp(Int.max, for: field)
            #expect(!GMNumber.format(clamped).contains("e"))
        }
    }

    @Test("setClamped applies the limit on the way in", .enabled(if: Fixtures.arePresent))
    func setClampedApplies() throws {
        var document = try #require(Fixtures.any).document()

        try document.setClamped(.money, to: 50_000_000)
        #expect(document.int(.money) == 999_999)
        #expect(document.rawLine(.money) == "999999 ")

        try document.setClamped(.charAttack(0), to: -5)
        #expect(document.int(.charAttack(0)) == 0)
    }

    @Test("Advanced writes are not clamped", .enabled(if: Fixtures.arePresent))
    func rawSetIsUnrestricted() throws {
        var document = try #require(Fixtures.any).document()
        try document.set(.money, to: 5_000_000)
        #expect(document.int(.money) == 5_000_000)
        #expect(document.rawLine(.money) == "5e+06 ")
    }

    @Test("Lowering max HP brings current HP down with it", .enabled(if: Fixtures.arePresent))
    func maxHealthDragsCurrentDown() throws {
        var document = try #require(Fixtures.any).document()
        try document.set(.charMaxHealth(1), to: 500)
        try document.set(.charHealth(1), to: 500)

        try document.setMaxHealth(1, to: 100)

        #expect(document.int(.charMaxHealth(1)) == 100)
        #expect(document.int(.charHealth(1)) == 100)
    }

    @Test("Raising max HP leaves current HP where it was", .enabled(if: Fixtures.arePresent))
    func raisingMaxLeavesCurrent() throws {
        var document = try #require(Fixtures.any).document()
        try document.set(.charMaxHealth(1), to: 100)
        try document.set(.charHealth(1), to: 30)

        try document.setMaxHealth(1, to: 900)

        #expect(document.int(.charMaxHealth(1)) == 900)
        #expect(document.int(.charHealth(1)) == 30)
    }

    @Test("Heal to full sets current HP to the maximum", .enabled(if: Fixtures.arePresent))
    func healToFull() throws {
        var document = try #require(Fixtures.any).document()
        try document.set(.charMaxHealth(1), to: 250)
        try document.set(.charHealth(1), to: 4)

        try document.healToFull(1)
        #expect(document.int(.charHealth(1)) == 250)
    }

    @Test("Clamping still can't write a terminator slot", .enabled(if: Fixtures.arePresent))
    func clampingRespectsReservedSlots() throws {
        var document = try #require(Fixtures.any).document()
        #expect(throws: (any Error).self) { try document.setClamped(.invConsumable(12), to: 3) }
        #expect(document.isModified == false)
    }
}
