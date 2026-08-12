import SwiftUI
import DeltaruneCore

/// Money, level and experience — for both the Dark World and the Light World.
struct MoneyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.document != nil {
                    // No LV or EXP here on purpose: DELTARUNE has no levelling, so those
                    // fields read 1 and 0 in every save and changing them does nothing.
                    // They remain visible in Advanced.
                    Card(
                        title: "Dark World",
                        subtitle: "Dark Dollars are what you spend in the Dark World shops."
                    ) {
                        NumberRow(
                            label: "Dark Dollars",
                            help: "Up to \(EditPolicy.money.upperBound)",
                            range: EditPolicy.money,
                            value: model.value(.money)
                        ) { model.setValue(.money, $0) }
                    }

                    Card(
                        title: "Light World",
                        subtitle: "Money and health for back home in Hometown."
                    ) {
                        VStack(spacing: Theme.rowSpacing) {
                            NumberRow(
                                label: "Money",
                                range: EditPolicy.money,
                                value: model.value(.lightMoney)
                            ) { model.setValue(.lightMoney, $0) }

                            NumberRow(
                                label: "HP",
                                range: EditPolicy.health,
                                value: model.value(.lightHealth)
                            ) { model.setValue(.lightHealth, $0) }

                            NumberRow(
                                label: "Max HP",
                                range: EditPolicy.maxHealth,
                                value: model.value(.lightMaxHealth)
                            ) { model.setValue(.lightMaxHealth, $0) }
                        }
                    }

                    Card(title: "Quick Buttons", subtitle: "Shortcuts for the usual things.") {
                        HStack(spacing: 12) {
                            Button("Give me lots of money") {
                                model.setValue(.money, EditPolicy.money.upperBound)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.good)

                            Button("Empty my wallet") { model.setValue(.money, 0) }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Text("Pick a save file to get started.").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
