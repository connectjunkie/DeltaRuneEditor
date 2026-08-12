import SwiftUI

/// Shared look. Deliberately large type and generous spacing — the person using this is
/// nine, and small controls are the main reason apps feel unusable to children.
enum Theme {
    static let cardCorner: CGFloat = 14
    static let rowSpacing: CGFloat = 14
    static let bigNumberWidth: CGFloat = 120

    static let accent = Color(red: 0.90, green: 0.19, blue: 0.44)
    static let good = Color(red: 0.18, green: 0.65, blue: 0.36)
    static let warn = Color(red: 0.93, green: 0.58, blue: 0.12)
}

/// A titled panel used everywhere so the screens look like one app.
struct Card<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }
}

/// A labelled number field with steppers, big enough to hit easily.
struct NumberRow: View {
    let label: String
    var help: String?
    let range: ClosedRange<Int>
    let value: Int
    /// Main-actor isolated so it satisfies the Sendable setter `Binding` now expects,
    /// while still being able to capture the view model.
    let onChange: @MainActor (Int) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.body.weight(.medium))
                if let help {
                    Text(help).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)

            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: Theme.bigNumberWidth)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }

            Stepper("") {
                onChange(min(value + step, range.upperBound))
            } onDecrement: {
                onChange(max(value - step, range.lowerBound))
            }
            .labelsHidden()
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { _, new in if !focused { text = String(new) } }
    }

    /// Bigger jumps for bigger numbers, so reaching 9999 isn't 9,999 clicks.
    private var step: Int { range.upperBound > 5_000 ? 100 : 1 }

    private func commit() {
        let parsed = Int(text.trimmingCharacters(in: .whitespaces)) ?? value
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        text = String(clamped)
        if clamped != value { onChange(clamped) }
    }
}

/// A searchable picker over game items, showing real names instead of numbers.
struct ItemPicker: View {
    let label: String
    let options: [GameItemOption]
    let selection: Int
    let onChange: @MainActor (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.body.weight(.medium))
                .frame(width: 90, alignment: .leading)

            Picker("", selection: Binding(get: { selection }, set: onChange)) {
                ForEach(options) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Minimal shape the pickers need, so views don't depend on the core's model directly.
struct GameItemOption: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// Coloured message strip used for errors, warnings and confirmations.
struct Banner: View {
    enum Kind { case good, warn, bad }

    let kind: Kind
    let text: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button(action.title, action: action.run).buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.45)))
    }

    private var icon: String {
        switch kind {
        case .good: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .bad: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .good: Theme.good
        case .warn: Theme.warn
        case .bad: .red
        }
    }
}
