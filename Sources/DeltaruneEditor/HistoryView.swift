import SwiftUI
import DeltaruneCore

/// Every version of the save folder the app has ever replaced, with a way back to each.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming: BackupManifest?
    @State private var confirmingOriginal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(
                    title: "Going back",
                    subtitle: """
                        Every time you save, I first keep a copy of how everything was. \
                        Nothing you do here can be lost — you can always come back.
                        """
                ) {
                    HStack(spacing: 12) {
                        Button("Put everything back to the very start") {
                            confirmingOriginal = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.warn)

                        Button("Show backups in Finder") { model.revealBackupsInFinder() }
                            .buttonStyle(.bordered)
                    }
                }

                Card(title: "Your backups", subtitle: subtitle) {
                    if model.snapshots.isEmpty {
                        Text("No backups yet. One gets made automatically the first time you save.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.snapshots) { snapshot in
                                row(snapshot)
                                if snapshot.id != model.snapshots.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .alert("Go back to this backup?", isPresented: .constant(confirming != nil)) {
            Button("Cancel", role: .cancel) { confirming = nil }
            Button("Go back") {
                if let snapshot = confirming { model.restore(snapshot) }
                confirming = nil
            }
        } message: {
            Text("""
                Everything will go back to how it was on \
                \(confirming.map { AppModel.friendly($0.createdAt) } ?? "").
                I'll keep a copy of how things are right now, so you can undo this too.
                """)
        }
        .alert("Start again from the beginning?", isPresented: $confirmingOriginal) {
            Button("Cancel", role: .cancel) {}
            Button("Put everything back") { model.restoreOriginal() }
        } message: {
            Text("""
                This undoes everything this app has ever changed, all the way back to \
                before you first used it. Your game itself is not affected.
                """)
        }
    }

    private var subtitle: String {
        let count = model.snapshots.count
        return count == 1 ? "1 backup kept" : "\(count) backups kept"
    }

    private func row(_ snapshot: BackupManifest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.isFirstRun ? "star.fill" : "clock.arrow.circlepath")
                .foregroundStyle(snapshot.isFirstRun ? Theme.warn : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.isFirstRun ? "The very beginning" : snapshot.note)
                    .font(.body.weight(.medium))
                Text("\(AppModel.friendly(snapshot.createdAt)) · \(snapshot.fileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Go back to this") { confirming = snapshot }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
    }
}
