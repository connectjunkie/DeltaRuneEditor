import SwiftUI
import DeltaruneCore

/// The bag: twelve item slots and twelve key item slots, each a dropdown of real names.
struct ItemsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let document = model.document {
                    Card(
                        title: "Items",
                        subtitle: "The things you can use in a fight. Pick “Empty” to throw one away."
                    ) {
                        slots(document: document, category: .consumables, make: FieldID.invConsumable)
                    }

                    Card(
                        title: "Key Items",
                        subtitle: "Special things you're carrying."
                    ) {
                        slots(document: document, category: .keyItems, make: FieldID.invKeyItem)
                    }

                    if document.format == .v2 {
                        Card(
                            title: "Storage",
                            subtitle: "Extra items kept in the box. There's a lot of room in here."
                        ) {
                            storage(document: document)
                        }
                    }
                } else {
                    Text("Pick a save file to get started.").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Two columns of pickers, one per usable slot.
    private func slots(
        document: SaveDocument,
        category: ItemCategory,
        make: @escaping (Int) -> FieldID
    ) -> some View {
        let options = pickerOptions(for: category)

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
            spacing: 10
        ) {
            ForEach(Array(document.usableSlots(for: category)), id: \.self) { slot in
                ItemPicker(
                    label: "\(slot + 1).",
                    options: options,
                    selection: document.int(make(slot)) ?? 0
                ) { newValue in
                    model.setValue(make(slot), newValue)
                }
            }
        }
    }

    @State private var showAllStorage = false

    /// Storage has 72 slots. Showing all of them at once is overwhelming, so start with the
    /// first twelve and let the curious expand it.
    private func storage(document: SaveDocument) -> some View {
        let options = pickerOptions(for: .consumables)
        let total = document.format.usableStorageSlots
        let shown = showAllStorage ? total : min(12, total)

        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                spacing: 10
            ) {
                ForEach(0..<shown, id: \.self) { slot in
                    ItemPicker(
                        label: "\(slot + 1).",
                        options: options,
                        selection: document.int(.invStorage(slot)) ?? 0
                    ) { newValue in
                        model.setValue(.invStorage(slot), newValue)
                    }
                }
            }

            if total > 12 {
                Button(showAllStorage ? "Show fewer" : "Show all \(total) storage slots") {
                    withAnimation { showAllStorage.toggle() }
                }
                .buttonStyle(.link)
            }
        }
    }

    private func pickerOptions(for category: ItemCategory) -> [GameItemOption] {
        GameData.shared
            .pickerOptions(in: category, chapter: model.chapter)
            .map { GameItemOption(id: $0.id, name: $0.name(inChapter: model.chapter)) }
    }
}
