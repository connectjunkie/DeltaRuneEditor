import SwiftUI
import DeltaruneCore

/// The escape hatch: raw line editing, flags, and the details of the loaded file.
///
/// Kept behind its own tab and worded plainly, because this is the part where the safety
/// rails come off — values here are written without clamping.
struct AdvancedView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var flagIndexText = ""
    @State private var rawLineText = ""
    @State private var rawLineIndexText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Banner(
                    kind: .warn,
                    text: """
                        This part is for grown-ups. Values here are written exactly as typed, \
                        with no safety limits. Backups still happen on every save.
                        """
                )

                if let document = model.document {
                    fileInfo(document)
                    fieldInspector(document)
                    names(document)
                    flags(document)
                    rawLines(document)
                } else {
                    Text("Pick a save file to get started.").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - File info

    private func fileInfo(_ document: SaveDocument) -> some View {
        Card(title: "About this file") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                infoRow("File", model.selectedSave?.filename ?? "—")
                infoRow("Format", document.format == .v1 ? "V1 (Chapter 1)" : "V2 (Chapters 2–5)")
                infoRow("Lines", "\(document.lines.count)")
                infoRow("Flags", "\(document.flagCount)")
                infoRow("Line endings", document.lineEnding == "\r\n" ? "CRLF" : "LF")
                infoRow("Characters", "\(document.format.characterCount)")
                infoRow("Room", document.string(.room) ?? "—")
                // Shown raw: plot can be fractional, so don't round it here.
                infoRow("Plot", document.string(.plot) ?? "—")
                infoRow("Changed lines", "\(document.modifiedLineIndices.count)")
            }
            .font(.callout.monospacedDigit())
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }

    // MARK: - Field inspector

    /// Shows which line each displayed value actually came from.
    ///
    /// The round-trip gate proves we read the right lines but says nothing about whether
    /// the right label is on each one — which is how the first build managed to call the
    /// unused character slot "Kris". This makes that kind of mistake visible instead of
    /// merely plausible.
    private func fieldInspector(_ document: SaveDocument) -> some View {
        Card(
            title: "Where each value comes from",
            subtitle: "The line number in the file behind everything the other tabs show."
        ) {
            VStack(alignment: .leading, spacing: 2) {
                inspectorHeader()
                Divider()

                inspectorRow("Dark Dollars", .money, document)
                inspectorRow("LV (unused by the game)", .lv, document)
                inspectorRow("EXP (unused by the game)", .xp, document)
                inspectorRow("In Dark World", .inDarkWorld, document)
                inspectorRow("Room", .room, document)
                inspectorRow("Plot", .plot, document)

                Divider().padding(.vertical, 4)

                // Slot 0 is the placeholder for the empty character, not Kris.
                inspectorRow("slot 0 max HP (unused slot)", .charMaxHealth(0), document)
                ForEach(Array(document.format.characterSlots), id: \.self) { slot in
                    let name = GameData.shared.characters.first { $0.id == slot }?.name
                        ?? "slot \(slot)"
                    inspectorRow("\(name) max HP", .charMaxHealth(slot), document)
                }

                Divider().padding(.vertical, 4)

                inspectorRow("Light World money", .lightMoney, document)
                inspectorRow("Light World HP", .lightHealth, document)
                inspectorRow("First item slot", .invConsumable(0), document)
                inspectorRow("Item end marker", .invConsumable(12), document)
            }
            .font(.callout.monospaced())
        }
    }

    private func inspectorHeader() -> some View {
        HStack {
            Text("field").frame(width: 240, alignment: .leading)
            Text("line").frame(width: 70, alignment: .trailing)
            Text("value")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func inspectorRow(_ label: String, _ field: FieldID, _ document: SaveDocument) -> some View {
        HStack {
            Text(label)
                .frame(width: 240, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(document.fieldMap[field].map { String($0 + 1) } ?? "—")
                .frame(width: 70, alignment: .trailing)
            Text(document.string(field).map { "“\($0)”" } ?? "—")
            Spacer()
        }
    }

    // MARK: - Names

    private func names(_ document: SaveDocument) -> some View {
        Card(title: "Names", subtitle: "The player name and the vessel name.") {
            VStack(spacing: 10) {
                textRow("Player", field: .playerName, document: document)
                textRow("Vessel", field: .vesselName, document: document)
            }
        }
    }

    private func textRow(_ label: String, field: FieldID, document: SaveDocument) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            TextField("", text: Binding(
                get: { document.string(field) ?? "" },
                set: { newValue in model.edit { try $0.setString(field, to: newValue) } }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 260)
        }
    }

    // MARK: - Flags

    private func flags(_ document: SaveDocument) -> some View {
        Card(
            title: "Story flags",
            subtitle: "\(document.flagCount) flags. Enter a number to see and change one."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Flag number", text: $flagIndexText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Text(flagDescription(document)).foregroundStyle(.secondary)
                }

                if let index = flagIndex(document) {
                    HStack {
                        Text("Value").frame(width: 90, alignment: .leading)
                        TextField("", text: Binding(
                            get: { document.string(.flag(index)) ?? "" },
                            set: { newValue in
                                model.edit { try $0.set(.flag(index), toRaw: newValue) }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    }
                }
            }
        }
    }

    private func flagIndex(_ document: SaveDocument) -> Int? {
        guard let index = Int(flagIndexText.trimmingCharacters(in: .whitespaces)),
              index >= 0, index < document.flagCount else { return nil }
        return index
    }

    private func flagDescription(_ document: SaveDocument) -> String {
        if flagIndexText.isEmpty { return "" }
        return flagIndex(document) == nil ? "No flag with that number" : "Flag found"
    }

    // MARK: - Raw lines

    private func rawLines(_ document: SaveDocument) -> some View {
        Card(
            title: "Raw line editing",
            subtitle: """
                Change one line of the file directly. The trailing space is kept for you. \
                Line numbers start at 1.
                """
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Line number", text: $rawLineIndexText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)

                    Button("Load") {
                        if let index = rawIndex(document) {
                            rawLineText = document.lines[index].trimmingCharacters(in: .whitespaces)
                        }
                    }
                    .disabled(rawIndex(document) == nil)
                }

                HStack {
                    TextField("Value", text: $rawLineText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)

                    Button("Set this line") {
                        guard let index = rawIndex(document) else { return }
                        model.edit { document in
                            // Deliberately bypasses the field map: this is the escape hatch
                            // for a line we don't model. Trailing space is preserved.
                            try document.setRawLine(index, to: rawLineText)
                        }
                    }
                    .disabled(rawIndex(document) == nil)
                }

                if let index = rawIndex(document) {
                    Text("Currently: “\(document.lines[index])”")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rawIndex(_ document: SaveDocument) -> Int? {
        guard let line = Int(rawLineIndexText.trimmingCharacters(in: .whitespaces)),
              line >= 1, line <= document.lines.count else { return nil }
        return line - 1
    }
}
