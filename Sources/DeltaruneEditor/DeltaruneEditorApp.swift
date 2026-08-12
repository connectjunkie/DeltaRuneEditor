import SwiftUI
import DeltaruneCore

@main
struct DeltaruneEditorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Deltarune Editor", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 620)
                .task { model.start() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save Changes") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.canSave)
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}
