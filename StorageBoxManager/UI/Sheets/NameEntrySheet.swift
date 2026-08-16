import SwiftUI

struct NameEntrySheet: View { // shared by "new folder" and "rename", just a name field + confirm
    let title: String
    let prompt: String
    let initialText: String
    let confirmLabel: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(confirm)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                Button(confirmLabel, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            text = initialText
            fieldFocused = true
        }
    }

    private func confirm() {
        guard isValid else { return }
        onConfirm(trimmed)
        dismiss()
    }
}
