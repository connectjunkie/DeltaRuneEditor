import Foundation
import Testing
@testable import DeltaruneCore

/// Real DELTARUNE save files, supplied by whoever is running the tests.
///
/// Nothing is committed to the repository — save files are personal data. The suite
/// discovers whatever is present in `Tests/DeltaruneCoreTests/Fixtures/` and asserts
/// properties that hold for *any* valid save, not facts about one playthrough. See that
/// directory's README for how to add your own.
enum Fixtures {

    /// One real save file found on disk.
    struct Save: CustomStringConvertible, Sendable, Hashable {
        let name: String
        let chapter: Int
        let expectedFormat: SaveFormat
        var description: String { name }

        var url: URL { Fixtures.directory.appendingPathComponent(name) }
        var bytes: Data { get throws { try Data(contentsOf: url) } }
        func document() throws -> SaveDocument { try SaveDocument(bytes: bytes) }
    }

    static var directory: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }

    /// Every save file present, discovered rather than hard-coded, ordered for stable
    /// test output.
    static let saves: [Save] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .compactMap { name -> Save? in
                guard let parsed = SaveFileName(name), let format = parsed.format else { return nil }
                // Only offer files that actually exist and are readable.
                guard FileManager.default.isReadableFile(
                    atPath: directory.appendingPathComponent(name).path
                ) else { return nil }
                return Save(name: name, chapter: parsed.chapter, expectedFormat: format)
            }
            .sorted { $0.name < $1.name }
    }()

    /// Whether the suite has anything to work with. Used by `.enabled(if:)` traits so a
    /// checkout with no saves skips cleanly instead of failing.
    static var arePresent: Bool { !saves.isEmpty }

    /// A save in each format, for tests that need one specific layout.
    static var anyV1: Save? { saves.first { $0.expectedFormat == .v1 } }
    static var anyV2: Save? { saves.first { $0.expectedFormat == .v2 } }

    /// Any save at all, for tests that don't care which.
    static var any: Save? { saves.first }

    static var drIniURL: URL { directory.appendingPathComponent("dr.ini") }
    static var hasDrIni: Bool { FileManager.default.fileExists(atPath: drIniURL.path) }

    static func drIni() throws -> DrIni { try DrIni(contentsOf: drIniURL) }

    /// The `dr.ini` section for a save, when the file has one. Autosaves never do.
    static func iniSection(for save: Save) -> String? {
        guard hasDrIni, let parsed = SaveFileName(save.name),
              let ini = try? drIni(), ini.hasSection(parsed.iniSectionName)
        else { return nil }
        return parsed.iniSectionName
    }

    // MARK: - Scratch space

    /// A scratch directory that cleans itself up.
    static func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DeltaruneCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(root)
    }

    /// A throwaway copy of the whole fixture folder, for tests that write.
    static func withTemporarySaveFolder<T>(_ body: (URL) throws -> T) throws -> T {
        try withTemporaryDirectory { root in
            let folder = root.appendingPathComponent("com.tobyfox.deltarune")
            try FileManager.default.copyItem(at: directory, to: folder)
            // The bring-your-own-saves README lives alongside the saves; it isn't one.
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("README.md"))
            return try body(folder)
        }
    }
}

/// Reports plainly when there's nothing to test against, rather than leaving someone to
/// wonder why most of the suite was skipped.
@Suite("Fixtures")
struct FixturePresenceTests {

    @Test("Save files are available to test against")
    func fixturesArePresent() throws {
        try withKnownIssue("No save files in Tests/DeltaruneCoreTests/Fixtures/", isIntermittent: true) {
            try #require(
                Fixtures.arePresent,
                """
                No DELTARUNE save files found. Most of the suite will be skipped.
                Copy a save folder in to run it in full:
                  cp -R ~/Library/"Application Support"/com.tobyfox.deltarune/* \
                        Tests/DeltaruneCoreTests/Fixtures/
                """
            )
        } when: {
            !Fixtures.arePresent
        }
    }

    @Test("Discovered saves are classified correctly", .enabled(if: Fixtures.arePresent))
    func discoveryClassifies() throws {
        for save in Fixtures.saves {
            #expect(SaveFileName(save.name) != nil)
            #expect(save.expectedFormat == SaveFormat.forChapter(save.chapter))
        }
    }
}
