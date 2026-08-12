import SwiftUI
import DeltaruneCore

/// Who's in the party, their health, stats and equipment.
struct PartyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let document = model.document {
                    Card(
                        title: "Who's in your party",
                        subtitle: "The three characters fighting with you."
                    ) {
                        VStack(spacing: 10) {
                            ForEach(0..<3, id: \.self) { slot in
                                ItemPicker(
                                    label: "Slot \(slot + 1)",
                                    options: characterOptions,
                                    selection: document.int(.party(slot)) ?? 0
                                ) { model.setValue(.party(slot), $0) }
                            }
                        }
                    }

                    // Slot 0 is the unused EMPTY character, not Kris. See
                    // SaveFormat.characterSlots.
                    ForEach(Array(document.format.characterSlots), id: \.self) { index in
                        characterCard(index: index, document: document)
                    }

                    Card(title: "Quick Buttons", subtitle: "Shortcuts for the usual things.") {
                        Button("Heal everyone to full") {
                            model.edit { document in
                                for index in document.format.characterSlots {
                                    try document.healToFull(index)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.good)
                    }
                } else {
                    Text("Pick a save file to get started.").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func characterCard(index: Int, document: SaveDocument) -> some View {
        let health = document.int(.charHealth(index)) ?? 0
        let maxHealth = max(document.int(.charMaxHealth(index)) ?? 1, 1)

        return Card(title: characterName(index)) {
            VStack(spacing: Theme.rowSpacing) {
                healthBar(health: health, maxHealth: maxHealth)

                NumberRow(
                    label: "HP now",
                    range: EditPolicy.health,
                    value: health
                ) { model.setValue(.charHealth(index), $0) }

                NumberRow(
                    label: "Biggest HP",
                    range: EditPolicy.maxHealth,
                    value: maxHealth
                ) { newValue in
                    model.edit { try $0.setMaxHealth(index, to: newValue) }
                }

                HStack(spacing: 18) {
                    statField("Attack", .charAttack(index))
                    statField("Defence", .charDefence(index))
                    statField("Magic", .charMagic(index))
                }

                Divider()

                ItemPicker(
                    label: "Weapon",
                    options: options(for: .weapons),
                    selection: document.int(.charWeapon(index)) ?? 0
                ) { model.setValue(.charWeapon(index), $0) }

                ItemPicker(
                    label: "Armour 1",
                    options: options(for: .armors),
                    selection: document.int(.charPrimaryArmor(index)) ?? 0
                ) { model.setValue(.charPrimaryArmor(index), $0) }

                ItemPicker(
                    label: "Armour 2",
                    options: options(for: .armors),
                    selection: document.int(.charSecondaryArmor(index)) ?? 0
                ) { model.setValue(.charSecondaryArmor(index), $0) }

                HStack {
                    Spacer()
                    Button("Heal to full") {
                        model.edit { try $0.healToFull(index) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func healthBar(health: Int, maxHealth: Int) -> some View {
        let fraction = min(max(Double(health) / Double(maxHealth), 0), 1)

        return HStack(spacing: 10) {
            Image(systemName: "heart.fill").foregroundStyle(Theme.accent)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(fraction > 0.3 ? Theme.good : Theme.accent)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 14)

            Text("\(health) / \(maxHealth)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
    }

    private func statField(_ label: String, _ field: FieldID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: Binding(
                get: { model.value(field) },
                set: { model.setValue(field, $0) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .rounded).monospacedDigit())
            .frame(width: 80)
        }
    }

    /// The block index *is* the character id — block 1 is Kris, block 2 Susie, and so on.
    /// There is no offset to apply; adding one here is what mislabelled the whole party.
    private func characterName(_ index: Int) -> String {
        let named = GameData.shared.characters.first { $0.id == index }
        return named?.name(inChapter: model.chapter) ?? "Character \(index)"
    }

    private var characterOptions: [GameItemOption] {
        options(for: .characters)
    }

    private func options(for category: ItemCategory) -> [GameItemOption] {
        GameData.shared
            .pickerOptions(in: category, chapter: model.chapter)
            .map { GameItemOption(id: $0.id, name: $0.name(inChapter: model.chapter)) }
    }
}
