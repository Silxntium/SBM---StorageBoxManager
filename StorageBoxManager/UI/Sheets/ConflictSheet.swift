import SwiftUI

struct ConflictSheet: View {
    let prompt: ConflictPrompt
    let onSkip: (Bool) -> Void
    let onKeepBoth: (Bool) -> Void
    let onReplace: (Bool) -> Void

    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name Conflict")
                .font(.headline)
            Text(prompt.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Apply to all remaining", isOn: $applyToAll)

            HStack {
                Spacer()
                Button("Skip") { onSkip(applyToAll) }
                    .keyboardShortcut(.cancelAction)
                Button("Keep Both") { onKeepBoth(applyToAll) }
                Button("Replace") { onReplace(applyToAll) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }
}
