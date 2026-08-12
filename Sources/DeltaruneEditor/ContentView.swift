import SwiftUI
import DeltaruneCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.folder == nil {
            WelcomeView()
        } else {
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            header
            Divider()
            banners
            content
            Divider()
            footer
        }
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var model = model

        return HStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill")
                .font(.title)
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Deltarune Editor").font(.title2.weight(.bold))
                if let document = model.document {
                    Text(document.string(.playerName) ?? "?")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    // Where he's up to, so it's obvious the right save is loaded.
                    if let place = model.whereYouAre {
                        Label(place, systemImage: "mappin.and.ellipse")
                            .font(.callout)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            Spacer()

            // Most recently played first, so the save he's on is at the top.
            Picker("Save file", selection: $model.selectedSave) {
                ForEach(model.datedSaves) { entry in
                    Text(model.pickerLabel(for: entry)).tag(Optional(entry.save))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 8) {
            if model.isGameRunning {
                Banner(
                    kind: .warn,
                    text: "Deltarune is open right now. Quit the game first, or it will undo your changes."
                )
            }
            if let blocked = model.blockedMessage {
                Banner(kind: .bad, text: blocked)
            }
            if let error = model.errorMessage {
                Banner(kind: .bad, text: error)
            }
            if let success = model.successMessage {
                Banner(kind: .good, text: success)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, model.hasAnyBanner ? 12 : 0)
    }

    // MARK: - Tabs

    private var content: some View {
        TabView {
            Tab("Items", systemImage: "backpack.fill") { ItemsView() }
            Tab("Money", systemImage: "dollarsign.circle.fill") { MoneyView() }
            Tab("Party", systemImage: "heart.fill") { PartyView() }
            Tab("History", systemImage: "clock.arrow.circlepath") { HistoryView() }
            Tab("Advanced", systemImage: "wrench.and.screwdriver.fill") { AdvancedView() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .disabled(model.document == nil && model.blockedMessage != nil)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if model.hasUnsavedChanges {
                Label("You have changes that aren't saved yet", systemImage: "pencil.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.warn)
            } else {
                Label("Everything is saved", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Undo My Changes") { model.discardChanges() }
                .disabled(!model.hasUnsavedChanges)

            Button {
                model.save()
            } label: {
                Label("Save Changes", systemImage: "square.and.arrow.down.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut("s")
            .disabled(!model.canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

extension AppModel {
    var hasAnyBanner: Bool {
        isGameRunning || blockedMessage != nil || errorMessage != nil || successMessage != nil
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)

            Text("Deltarune Editor").font(.largeTitle.weight(.bold))

            Text("""
                I couldn't find your Deltarune saves in the usual place.
                Click below and choose the folder called com.tobyfox.deltarune.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            Button("Find My Saves…") { model.chooseFolder() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)

            if let error = model.errorMessage {
                Banner(kind: .bad, text: error).frame(maxWidth: 460)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
