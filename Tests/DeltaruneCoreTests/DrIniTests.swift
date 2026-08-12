import Foundation
import Testing
@testable import DeltaruneCore

@Suite("dr.ini", .enabled(if: Fixtures.hasDrIni))
struct DrIniTests {

    private func ini() throws -> DrIni { try Fixtures.drIni() }

    /// Section names for the save slots, as opposed to `[VHS]`, `[URA]` and anything else
    /// the game keeps in there.
    private func slotSections(_ ini: DrIni) -> [String] {
        ini.sectionOrder.filter { $0.hasPrefix("G") }
    }

    @Test("Round trips the real dr.ini byte for byte")
    func roundTripIsByteIdentical() throws {
        let original = try Data(contentsOf: Fixtures.drIniURL)
        #expect(try DrIni(bytes: original).serialized() == original)
    }

    @Test("Parses sections and keys")
    func parsesSections() throws {
        let ini = try ini()

        #expect(!ini.sectionOrder.isEmpty)
        #expect(!slotSections(ini).isEmpty, "expected at least one save slot section")
        for name in ini.sectionOrder {
            #expect(ini.hasSection(name))
        }
    }

    @Test("Every slot section carries the file-select fields")
    func slotSectionsHaveMetadata() throws {
        let ini = try ini()

        for section in slotSections(ini) {
            #expect(ini.value(section: section, key: DrIni.Key.name) != nil)
            #expect(ini.number(section: section, key: DrIni.Key.room) != nil)
        }
    }

    @Test("Section naming follows the chapter rule")
    func sectionNaming() {
        #expect(SaveFileName("filech1_0")?.iniSectionName == "G0")
        #expect(SaveFileName("filech1_3")?.iniSectionName == "G3")
        #expect(SaveFileName("filech2_0")?.iniSectionName == "G_2_0")
        #expect(SaveFileName("filech3_0")?.iniSectionName == "G_3_0")
    }

    @Test("Patching one key leaves every other line alone")
    func patchingOneKeyPreservesEverythingElse() throws {
        var ini = try ini()
        let section = try #require(slotSections(ini).first)
        let others = ini.sectionOrder.filter { $0 != section }
            .map { name in (name, ini.sections[name]?.count ?? 0) }
        let roomBefore = ini.number(section: section, key: DrIni.Key.room)

        try ini.setString(section: section, key: DrIni.Key.name, to: "TESTNAME")

        #expect(ini.modifiedLineIndices.count == 1)
        #expect(ini.value(section: section, key: DrIni.Key.name) == "TESTNAME")
        #expect(ini.number(section: section, key: DrIni.Key.room) == roomBefore)
        for (name, count) in others {
            #expect(ini.sections[name]?.count == count, "section \(name) changed")
        }
    }

    @Test("Numbers are written back as quoted six-decimal reals")
    func numberFormatting() throws {
        var ini = try ini()
        let section = try #require(slotSections(ini).first)

        try ini.set(section: section, key: DrIni.Key.level, to: 12)

        let index = try #require(ini.sections[section]?[DrIni.Key.level])
        #expect(ini.lines[index] == "\(DrIni.Key.level)=\"12.000000\"")
        #expect(ini.number(section: section, key: DrIni.Key.level) == 12)
    }

    @Test("Sections the app knows nothing about survive a write")
    func preservesUnknownSections() throws {
        var ini = try ini()
        let section = try #require(slotSections(ini).first)
        let before = ini.sectionOrder

        try ini.setString(section: section, key: DrIni.Key.name, to: "TESTNAME")
        let reloaded = try DrIni(bytes: ini.serialized())

        #expect(reloaded.sectionOrder == before)
        for name in before {
            #expect(reloaded.sections[name]?.count == ini.sections[name]?.count)
        }
    }

    @Test("Setting a key that doesn't exist throws rather than adding a line")
    func unknownKeyThrows() throws {
        var ini = try ini()
        let section = try #require(slotSections(ini).first)
        let before = ini.lines.count

        #expect(throws: (any Error).self) {
            try ini.setString(section: section, key: "NotAKey", to: "x")
        }
        #expect(throws: (any Error).self) {
            try ini.setString(section: "NotASection", key: DrIni.Key.name, to: "x")
        }
        #expect(ini.lines.count == before)
        #expect(ini.isModified == false)
    }

    @Test("Reverting restores the original bytes")
    func revertRestoresBytes() throws {
        let original = try Data(contentsOf: Fixtures.drIniURL)
        var ini = try DrIni(bytes: original)
        let section = try #require(slotSections(ini).first)

        try ini.setString(section: section, key: DrIni.Key.name, to: "TESTNAME")
        try ini.set(section: section, key: DrIni.Key.level, to: 99)
        ini.revertAll()

        #expect(ini.serialized() == original)
    }

    @Test("A quote in a name cannot break the file")
    func sanitizesQuotes() throws {
        var ini = try ini()
        let section = try #require(slotSections(ini).first)

        try ini.setString(section: section, key: DrIni.Key.name, to: "SA\"M")

        #expect(ini.value(section: section, key: DrIni.Key.name) == "SAM")
        #expect(try DrIni(bytes: ini.serialized())
            .value(section: section, key: DrIni.Key.name) == "SAM")
    }

    @Test("Syncing after an edit updates only that slot's metadata",
          .enabled(if: Fixtures.arePresent))
    func syncUpdatesSlotMetadata() throws {
        var ini = try ini()
        let save = try #require(Fixtures.saves.first { Fixtures.iniSection(for: $0) != nil })
        let slot = try #require(SaveFileName(save.name))
        let section = slot.iniSectionName

        let untouched = ini.sectionOrder.filter { $0 != section }
            .compactMap { name -> (String, String)? in
                ini.value(section: name, key: DrIni.Key.name).map { (name, $0) }
            }
        let roomBefore = ini.number(section: section, key: DrIni.Key.room)

        var document = try save.document()
        try document.set(.lv, to: 7)
        try document.setString(.playerName, to: "TESTNAME")
        try ini.sync(with: document, for: slot)

        #expect(ini.value(section: section, key: DrIni.Key.name) == "TESTNAME")
        #expect(ini.number(section: section, key: DrIni.Key.level) == 7)
        #expect(ini.number(section: section, key: DrIni.Key.room) == roomBefore)
        for (name, value) in untouched {
            #expect(ini.value(section: name, key: DrIni.Key.name) == value)
        }
    }
}

/// Pure filename parsing — needs no save files.
@Suite("Save file names")
struct SaveFileNameTests {

    @Test(
        "Parses the names the game uses",
        arguments: [
            ("filech1_0", 1, 0, false),
            ("filech2_3", 2, 3, false),
            ("filech3_9", 3, 9, false),
            ("filech5_3_b", 5, 3, true),
        ]
    )
    func parsesValidNames(name: String, chapter: Int, slot: Int, alternate: Bool) throws {
        let parsed = try #require(SaveFileName(name))
        #expect(parsed.chapter == chapter)
        #expect(parsed.rawSlot == slot)
        #expect(parsed.isAlternateRoute == alternate)
        #expect(parsed.filename == name)
    }

    @Test(
        "Rejects anything that isn't a save file",
        arguments: ["dr.ini", "keyconfig_0.ini", "filech0_0", "filech6_0", "filech1_7", "", "filech", "README.md"]
    )
    func rejectsInvalidNames(name: String) {
        #expect(SaveFileName(name) == nil)
    }

    @Test("Classifies slots the way the file-select screen does")
    func classifiesSlots() throws {
        #expect(try #require(SaveFileName("filech2_0")).kind == .save)
        #expect(try #require(SaveFileName("filech2_2")).kind == .save)
        #expect(try #require(SaveFileName("filech2_3")).kind == .completion)
        #expect(try #require(SaveFileName("filech2_9")).kind == .autosave)
        #expect(try #require(SaveFileName("filech2_1")).displaySlot == 2)
        #expect(try #require(SaveFileName("filech2_4")).displaySlot == 2)
    }

    @Test("Friendly names read like something a child can pick from")
    func friendlyNames() throws {
        #expect(try #require(SaveFileName("filech2_0")).friendlyName == "Chapter 2 — Save 1")
        #expect(try #require(SaveFileName("filech1_9")).friendlyName == "Chapter 1 — Autosave")
        #expect(try #require(SaveFileName("filech3_4")).friendlyName == "Chapter 3 — Finished file 2")
    }
}
