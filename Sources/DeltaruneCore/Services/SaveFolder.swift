import Foundation

/// The game's save directory and what's in it.
public struct SaveFolder: Sendable, Equatable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Where DELTARUNE keeps saves on macOS.
    public static var defaultURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.tobyfox.deltarune", isDirectory: true)
    }

    /// The standard location, if it exists and holds at least one save.
    public static func locateDefault() -> SaveFolder? {
        let candidate = SaveFolder(url: defaultURL)
        return candidate.exists && !candidate.saveFiles.isEmpty ? candidate : nil
    }

    public var exists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Save files present, ordered by chapter then slot.
    public var saveFiles: [SaveFileName] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names
            .compactMap(SaveFileName.init)
            .sorted {
                ($0.chapter, $0.rawSlot, $0.isAlternateRoute ? 1 : 0)
                    < ($1.chapter, $1.rawSlot, $1.isAlternateRoute ? 1 : 0)
            }
    }

    /// Only the three numbered slots per chapter — what the child actually picks from.
    public var playableSaves: [SaveFileName] {
        saveFiles.filter { $0.kind == .save }
    }

    public func url(for save: SaveFileName) -> URL {
        url.appendingPathComponent(save.filename)
    }

    // MARK: - Recency

    /// A save file paired with when it was last played.
    public struct DatedSave: Sendable, Equatable, Identifiable {
        public let save: SaveFileName
        public let lastPlayed: Date?
        /// True when the date came from the game's own record rather than the filesystem.
        public let isRecordedDate: Bool
        public var id: SaveFileName { save }
    }

    /// When a slot was last played: the game's own `dr.ini` date where there is one,
    /// otherwise the file's modification time.
    ///
    /// Autosaves get no `dr.ini` section, which is why the fallback exists. The fallback
    /// is only a hint — copying the folder rewrites modification times — so the recorded
    /// date always wins where it exists.
    public func lastPlayed(for save: SaveFileName, drIni: DrIni?) -> Date? {
        if let recorded = drIni?.lastPlayed(for: save) { return recorded }
        return try? FileManager.default
            .attributesOfItem(atPath: url(for: save).path)[.modificationDate] as? Date
    }

    /// Every save, most recently played first.
    ///
    /// Slots the game dated come first, newest to oldest. Everything else — autosaves,
    /// which get no `dr.ini` section — follows, ordered by file timestamp.
    ///
    /// The two are kept in separate groups on purpose. A file's timestamp says when it was
    /// *copied*, not when it was played, so in a folder that has been moved between Macs
    /// every undated file looks brand new. Letting those compete with real dates would
    /// float autosaves to the top of the list and hide the save he actually plays.
    public func savesByRecency(drIni: DrIni?) -> [DatedSave] {
        let dated = saveFiles.map { save in
            let recorded = drIni?.lastPlayed(for: save)
            return DatedSave(
                save: save,
                lastPlayed: recorded ?? modificationDate(of: save),
                isRecordedDate: recorded != nil
            )
        }

        return dated.sorted { lhs, rhs in
            if lhs.isRecordedDate != rhs.isRecordedDate { return lhs.isRecordedDate }

            switch (lhs.lastPlayed, rhs.lastPlayed) {
            case let (left?, right?) where left != right: return left > right
            case (nil, _?): return false
            case (_?, nil): return true
            default:
                // Stable tiebreak so the order never wobbles between launches.
                return (lhs.save.chapter, lhs.save.rawSlot)
                    > (rhs.save.chapter, rhs.save.rawSlot)
            }
        }
    }

    private func modificationDate(of save: SaveFileName) -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: url(for: save).path)[.modificationDate] as? Date
    }

    /// The save to open by default: the numbered slot he played most recently.
    ///
    /// Deliberately prefers a real save slot over an autosave. The autosave is often the
    /// newest file on disk, but it isn't what he loads from the file-select screen and the
    /// game rewrites it constantly.
    public func mostRecentlyPlayed(drIni: DrIni?) -> SaveFileName? {
        let ordered = savesByRecency(drIni: drIni)
        return ordered.first { $0.save.kind == .save }?.save ?? ordered.first?.save
    }

    public var drIniURL: URL { url.appendingPathComponent("dr.ini") }

    public func loadDrIni() throws -> DrIni? {
        guard FileManager.default.fileExists(atPath: drIniURL.path) else { return nil }
        return try DrIni(contentsOf: drIniURL)
    }
}
