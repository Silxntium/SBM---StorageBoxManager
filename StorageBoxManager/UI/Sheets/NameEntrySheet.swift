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

    private var validationHint: String? {
        if trimmed.isEmpty { return nil }
        if trimmed.contains("/") { return "Names can't contain a slash." }
        if trimmed == "." || trimmed == ".." { return "\"\(trimmed)\" isn't allowed as a name." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(prompt, text: $text)
                        .focused($fieldFocused)
                        .onSubmit(confirm)
                } footer: {
                    if let validationHint {
                        Text(validationHint)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel, action: confirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValid)
                }
            }
        }
        .sheetFrame(width: 380, height: 190)
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

#Preview {
    NameEntrySheet(
        title: "New Folder",
        prompt: "Folder name",
        initialText: "",
        confirmLabel: "Create"
    ) { _ in }
}
