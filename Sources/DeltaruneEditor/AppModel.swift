import Foundation
import Observation
import AppKit
import DeltaruneCore

/// Everything the screens read and act on.
///
/// All the risky work lives in `DeltaruneCore`; this holds the current selection, keeps an
/// eye on whether the game is running, and turns thrown errors into sentences a child can
/// read.
@MainActor
@Observable
final class AppModel {

    // MARK: - State

    private(set) var folder: SaveFolder?
    /// Saves in the order the picker shows them: most recently played first.
    private(set) var datedSaves: [SaveFolder.DatedSave] = []
    private(set) var saves: [SaveFileName] = []
    private(set) var document: SaveDocument?
    private(set) var snapshots: [BackupManifest] = []
    private(set) var isGameRunning = false

    var selectedSave: SaveFileName? {
        didSet {
            if selectedSave != oldValue { loadSelectedSave() }
        }
    }

    /// Green confirmation after a successful action.
    var successMessage: String?
    /// Red banner for anything that went wrong.
    var errorMessage: String?
    /// Set when a save file exists but can't be safely edited.
    var blockedMessage: String?

    private var editor: SaveEditor?
    private var gameMonitor: any GameRunningChecking = GameRunningMonitor()
    private var pollTimer: Timer?

    private static let folderDefaultsKey = "SaveFolderPath"

    var chapter: Int { selectedSave?.chapter ?? 1 }
    var hasUnsavedChanges: Bool { document?.isModified ?? false }
    var canSave: Bool { hasUnsavedChanges && !isGameRunning && blockedMessage == nil }

    // MARK: - Startup

    func start() {
        locateFolder()
        refreshGameRunning()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshGameRunning() }
        }
    }

    private func refreshGameRunning() {
        isGameRunning = gameMonitor.isGameRunning
    }

    /// Use the remembered folder if it's still valid, otherwise the standard location.
    private func locateFolder() {
        if let path = UserDefaults.standard.string(forKey: Self.folderDefaultsKey) {
            let remembered = SaveFolder(url: URL(fileURLWithPath: path))
            if remembered.exists, !remembered.saveFiles.isEmpty {
                adopt(remembered)
                return
            }
        }
        if let located = SaveFolder.locateDefault() {
            adopt(located)
        }
    }

    /// Let the user point at the folder themselves when it isn't where we expect.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Find your Deltarune saves"
        panel.message = "Choose the folder called com.tobyfox.deltarune"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveFolder.defaultURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let chosen = SaveFolder(url: url)
        guard !chosen.saveFiles.isEmpty else {
            errorMessage = "I couldn't find any Deltarune save files in that folder."
            return
        }
        adopt(chosen)
    }

    private func adopt(_ folder: SaveFolder) {
        self.folder = folder
        UserDefaults.standard.set(folder.url.path, forKey: Self.folderDefaultsKey)

        let backups = BackupStore(
            rootDirectory: Self.backupRoot,
            saveFolder: folder.url,
            appVersion: Self.appVersion
        )
        editor = SaveEditor(folder: folder, backups: backups, gameMonitor: gameMonitor)

        let ini = (try? folder.loadDrIni()) ?? nil
        datedSaves = folder.savesByRecency(drIni: ini)
        saves = datedSaves.map(\.save)
        refreshSnapshots()

        // Capture the pristine state before anything can be changed.
        do {
            try backups.ensureFirstRunSnapshot()
            refreshSnapshots()
        } catch {
            errorMessage = "I couldn't make a safety backup: \(error)"
        }

        // Open the slot he actually played last, not the first file alphabetically —
        // which was always Chapter 1 Slot 1, the oldest save in the folder.
        selectedSave = folder.mostRecentlyPlayed(drIni: ini) ?? saves.first
        loadSelectedSave()
    }

    // MARK: - Loading

    private func loadSelectedSave() {
        blockedMessage = nil
        errorMessage = nil
        successMessage = nil

        guard let editor, let save = selectedSave else {
            document = nil
            return
        }

        do {
            document = try editor.load(save)
        } catch {
            document = nil
            // The round-trip gate refusing a file is the safe outcome, not a crash.
            blockedMessage = """
                I can't read \(save.friendlyName) safely, so I won't change it.
                (\(error))
                """
        }
    }

    func reload() { loadSelectedSave() }

    private func refreshSnapshots() {
        snapshots = editor?.backups.snapshots ?? []
    }

    // MARK: - Editing

    /// Apply a change to the loaded document. Screens call this rather than touching the
    /// document directly, so nothing can edit a save that failed the gate.
    func edit(_ change: (inout SaveDocument) throws -> Void) {
        guard var working = document else { return }
        do {
            try change(&working)
            document = working
            successMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// "Cold Place · Tenna Prefight Speech Started", or nil if we can't name either.
    var whereYouAre: String? {
        guard let document else { return nil }
        return GameData.shared.whereYouAre(
            chapter: chapter,
            room: document.int(.room),
            // Read as a Double — plot values can be fractional (238.1, 238.65).
            plot: document.double(.plot)
        )
    }

    /// Save name plus when it was last played, so the picker is self-explanatory.
    func pickerLabel(for entry: SaveFolder.DatedSave) -> String {
        guard let date = entry.lastPlayed else { return entry.save.friendlyName }
        return "\(entry.save.friendlyName) — \(Self.friendly(date))"
    }

    func value(_ field: FieldID) -> Int { document?.int(field) ?? 0 }
    func text(_ field: FieldID) -> String { document?.string(field) ?? "" }

    func setValue(_ field: FieldID, _ value: Int) {
        edit { try $0.setClamped(field, to: value) }
    }

    func binding(_ field: FieldID) -> Int {
        value(field)
    }

    // MARK: - Saving

    func save() {
        guard let editor, let document, let selectedSave else { return }
        guard !isGameRunning else {
            errorMessage = EditorError.gameIsRunning.description
            return
        }

        do {
            let note = Self.describe(changes: document)
            if let report = try editor.commit(document, to: selectedSave, note: note) {
                successMessage = "Saved. I kept a backup of how it was "
                    + "(\(report.changedLineCount) change\(report.changedLineCount == 1 ? "" : "s"))."
                refreshSnapshots()
                loadSelectedSave()
            }
        } catch {
            errorMessage = "\(error)"
        }
    }

    func discardChanges() {
        loadSelectedSave()
    }

    // MARK: - History

    func restore(_ snapshot: BackupManifest) {
        guard let editor else { return }
        do {
            try editor.restore(snapshot: snapshot.id)
            successMessage = "Put everything back to \(Self.friendly(snapshot.createdAt))."
            refreshSnapshots()
            loadSelectedSave()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func restoreOriginal() {
        guard let editor else { return }
        do {
            try editor.restoreOriginal()
            successMessage = "Everything is back to how it was at the very start."
            refreshSnapshots()
            loadSelectedSave()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func revealBackupsInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.backupRoot])
    }

    // MARK: - Helpers

    static let appVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    /// Snapshots live outside the game folder so the game never sees them and a Steam file
    /// verification can't wipe the history.
    static var backupRoot: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DeltaruneEditor", isDirectory: true)
    }

    static func friendly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Turn the set of changed fields into a note for the History list.
    private static func describe(changes document: SaveDocument) -> String {
        var parts: Set<String> = []
        for field in document.modifiedFields {
            switch field {
            case .money, .lightMoney: parts.insert("money")
            case .lv, .xp, .lightLevel, .lightExperience: parts.insert("level")
            case .charHealth, .charMaxHealth: parts.insert("health")
            case .charAttack, .charDefence, .charMagic, .charGuts: parts.insert("stats")
            case .charWeapon, .charPrimaryArmor, .charSecondaryArmor: parts.insert("equipment")
            case .invConsumable, .invKeyItem, .invWeapon, .invArmor, .invStorage:
                parts.insert("items")
            case .party: parts.insert("party")
            case .playerName, .vesselName: parts.insert("name")
            default: parts.insert("other things")
            }
        }
        return parts.isEmpty ? "Before an edit" : "Before changing " + parts.sorted().joined(separator: ", ")
    }
}
